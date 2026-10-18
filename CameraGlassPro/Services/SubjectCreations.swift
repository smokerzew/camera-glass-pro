import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

extension ImageProcessingService {
    /// The edited subject on a transparent background, trimmed to the subject, as PNG data.
    func stickerPNG(edited: CIImage, mask: CIImage) -> Data? {
        let e = edited.extent
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(0.5, e.width / 1200))).cropped(to: e)
        let cut = CIFilter.blendWithMask()
        cut.inputImage = edited
        cut.backgroundImage = CIImage(color: .clear).cropped(to: e)
        cut.maskImage = soft
        guard let output = cut.outputImage?.cropped(to: e), let box = maskBounds(mask, extent: e) else { return nil }
        let trimmed = output.cropped(to: box).transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
        return context.pngRepresentation(of: trimmed, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Bounding box of the white part of a mask (with a little margin), or nil when it's empty.
    func maskBounds(_ mask: CIImage, extent e: CGRect) -> CGRect? {
        let side = 160
        let small = mask.cropped(to: e)
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
                .concatenating(CGAffineTransform(scaleX: CGFloat(side) / e.width, y: CGFloat(side) / e.height)))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(small, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[(y * side + x) * 4] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bitmap rows run top to bottom; Core Image y runs bottom to top.
        let sx = e.width / CGFloat(side), sy = e.height / CGFloat(side)
        let box = CGRect(x: e.minX + CGFloat(minX) * sx, y: e.maxY - CGFloat(maxY + 1) * sy,
                         width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy)
        return box.insetBy(dx: -e.width * 0.02, dy: -e.height * 0.02).intersection(e).integral
    }
}

/// "3D" photo: the subject floats in front of a slowly moving background (4 s, 30 fps H.264 movie).
enum ParallaxVideo {
    static let seconds = 4.0

    static func render(edited: CIImage, mask: CIImage, processor: ImageProcessingService, to url: URL) async throws {
        let source = edited.extent
        let scale = min(1, 1280 / max(source.width, source.height))
        let width = Int(source.width * scale) / 2 * 2, height = Int(source.height * scale) / 2 * 2
        guard width > 16, height > 16 else { throw LiveEffectsService.EffectError.noFrames }
        let e = CGRect(x: 0, y: 0, width: width, height: height)
        let fit = CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / source.width, y: CGFloat(height) / source.height))
        let base = edited.transformed(by: fit).cropped(to: e)
        let m = mask.transformed(by: fit).cropped(to: e)

        // Background plate with the subject removed (filled from the surrounding background), so moving the
        // background never reveals a second copy of the subject.
        let plate = processor.subjectPlate(base, mask: m, extent: e).clampedToExtent()
        let soft = m.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 500))).cropped(to: e)
        let subject = base.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: e), kCIInputMaskImageKey: soft,
        ])

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.startWriting() else { throw writer.error ?? LiveEffectsService.EffectError.writeFailed }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(seconds * Double(LiveEffectsService.fps))
        let center = CGPoint(x: e.midX, y: e.midY)
        func around(_ s: CGFloat, dx: CGFloat, dy: CGFloat) -> CGAffineTransform {
            CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: center.x + dx, y: center.y + dy))
        }
        for i in 0..<frames {
            try Task.checkCancellation()
            let t = Double(i) / Double(frames - 1)
            let ease = CGFloat(0.5 - 0.5 * cos(.pi * t))
            // Background drifts one way and zooms in; the subject grows slightly and drifts the other way.
            let back = plate.transformed(by: around(1.08 + 0.05 * ease, dx: (-0.025 + 0.05 * ease) * e.width,
                                                    dy: (0.01 - 0.02 * ease) * e.height))
            let front = subject.transformed(by: around(1.0 + 0.045 * ease, dx: (0.012 - 0.024 * ease) * e.width, dy: 0))
            let frame = front.composited(over: back).cropped(to: e)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw LiveEffectsService.EffectError.writeFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw LiveEffectsService.EffectError.writeFailed }
            processor.context.render(frame, to: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: LiveEffectsService.fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? LiveEffectsService.EffectError.writeFailed }
    }
}
