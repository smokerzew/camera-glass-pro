import AVFoundation
import CoreImage
import Vision

/// Smooth slow motion: plays a clip 4× slower without stutter by making three new frames between every
/// pair of real ones from the motion between them (Vision optical flow), instead of repeating frames.
enum FrameInterpolator {
    /// New frames per real frame gap (4× slower at the same frame rate).
    static let factor = 4
    /// Longest source stretch used, in seconds (the result is four times longer).
    static let maxSourceSeconds = 5.0

    /// Motion of every pixel from `a` to `b`, as an image whose red/green are x/y pixel motion at the
    /// flow's own resolution. Nil when Vision can't compute it.
    static func flow(from a: CIImage, to b: CIImage) -> CIImage? {
        let request = VNGenerateOpticalFlowRequest(targetedCIImage: b, options: [:])
        request.computationAccuracy = .medium
        let handler = VNImageRequestHandler(ciImage: a, options: [:])
        guard (try? handler.perform([request])) != nil, let buffer = request.results?.first?.pixelBuffer else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }

    /// Flow stretched over `extent`; `scale` converts its values to output pixels.
    static func fitted(_ flow: CIImage, to extent: CGRect) -> (image: CIImage, scale: CGSize) {
        let f = flow.extent
        let sx = extent.width / max(f.width, 1), sy = extent.height / max(f.height, 1)
        let image = flow.transformed(by: CGAffineTransform(translationX: -f.minX, y: -f.minY)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
        return (image, CGSize(width: sx, height: sy))
    }

    /// The frame at `t` between `a` and `b`. `direction` (±1 per axis) matches Vision's flow convention to
    /// Core Image's coordinates; `calibrate` finds it.
    static func frame(between a: CIImage, and b: CIImage, flow: CIImage, t: CGFloat, direction: CGPoint) -> CIImage {
        let e = a.extent
        guard let kernel = ImageProcessingService.interpolateKernel else { return t < 0.5 ? a : b }
        let (field, scale) = fitted(flow, to: e)
        let margin = max(e.width, e.height) / 8
        return kernel.apply(extent: e, roiCallback: { _, rect in rect.insetBy(dx: -margin, dy: -margin) },
                            arguments: [a.clampedToExtent(), b.clampedToExtent(), field.clampedToExtent(), Float(t),
                                        CIVector(x: scale.width * direction.x, y: scale.height * direction.y)])?
            .cropped(to: e) ?? (t < 0.5 ? a : b)
    }

    /// Which of the four sign conventions works (checked once per clip): with the right one, `a` moved halfway
    /// forward and `b` moved halfway back land on the same picture.
    static func calibrate(a: CIImage, b: CIImage, flow: CIImage, context: CIContext) -> CGPoint {
        let black = CIImage(color: .black).cropped(to: a.extent)
        var best = (error: CGFloat.greatestFiniteMagnitude, direction: CGPoint(x: 1, y: -1))
        for direction in [CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: -1), CGPoint(x: -1, y: 1)] {
            // Each side alone (mixed half and half with black, so both are at half brightness).
            let forward = frame(between: a, and: black, flow: flow, t: 0.5, direction: direction)
            let back = frame(between: black, and: b, flow: flow, t: 0.5, direction: direction)
            let error = averageDifference(forward, back, context: context)
            if error < best.error { best = (error, direction) }
        }
        return best.direction
    }

    static func averageDifference(_ x: CIImage, _ y: CIImage, context: CIContext) -> CGFloat {
        let difference = x.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: y])
        guard let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: difference, kCIInputExtentKey: CIVector(cgRect: x.extent),
        ])?.outputImage else { return .greatestFiniteMagnitude }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return CGFloat(pixel[0] + pixel[1] + pixel[2])
    }
}

extension LiveEffectsService {
    /// Smooth slow motion of `range` (up to 5 s of it): real frames with three made-up ones between each,
    /// written at 30 fps, so it plays 4× slower. Silent (slowed sound isn't useful).
    static func smoothSlowMotion(from asset: AVAsset, range: CMTimeRange, adjustments: PhotoAdjustmentState,
                                 processor: ImageProcessingService, to url: URL) async throws {
        let limited = CMTimeRange(start: range.start,
                                  duration: CMTimeMinimum(range.duration, CMTime(seconds: FrameInterpolator.maxSourceSeconds, preferredTimescale: 600)))
        let recipe = AdjustmentBox()
        recipe.value = adjustments.withoutGeometry
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        if !adjustments.isIdentity {
            generator.videoComposition = try? await VideoService.composition(for: asset, recipe: recipe, processor: processor)
        }

        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var index: Int64 = 0
        func append(_ image: CIImage) async throws {
            guard let input, let adaptor, let pool = adaptor.pixelBufferPool else { throw EffectError.writeFailed }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw EffectError.writeFailed }
            processor.context.render(image, to: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: fps))
            index += 1
        }

        var previous: CIImage?
        var direction: CGPoint?
        for await result in generator.images(for: frameTimes(in: limited)) {
            try Task.checkCancellation()
            guard let cgFrame = try? result.image else { continue }
            let frame = CIImage(cgImage: cgFrame)
            if writer == nil {
                let created = try AVAssetWriter(outputURL: url, fileType: .mov)
                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: cgFrame.width, AVVideoHeightKey: cgFrame.height,
                ])
                videoInput.expectsMediaDataInRealTime = false
                created.add(videoInput)
                adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: cgFrame.width,
                    kCVPixelBufferHeightKey as String: cgFrame.height,
                ])
                guard created.startWriting() else { throw EffectError.writeFailed }
                created.startSession(atSourceTime: .zero)
                writer = created
                input = videoInput
            }
            if let previous {
                if let flow = FrameInterpolator.flow(from: previous, to: frame) {
                    let dir = direction ?? FrameInterpolator.calibrate(a: previous, b: frame, flow: flow, context: processor.context)
                    direction = dir
                    for step in 1..<FrameInterpolator.factor {
                        let t = CGFloat(step) / CGFloat(FrameInterpolator.factor)
                        try await append(FrameInterpolator.frame(between: previous, and: frame, flow: flow, t: t, direction: dir))
                    }
                } else {
                    for _ in 1..<FrameInterpolator.factor { try await append(previous) } // no motion found: hold
                }
            }
            try await append(frame)
            previous = frame
        }
        guard let writer, let input else { throw EffectError.noFrames }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? EffectError.writeFailed }
    }
}
