import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Live Photo-style effects made from a video or a Live Photo's motion: Loop, Bounce and
/// Long Exposure (as in Photos), plus turning a video into a real Live Photo.
enum LiveEffect: String, CaseIterable, Identifiable {
    case livePhoto, loop, bounce, longExposure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .livePhoto: "LIVE PHOTO"
        case .loop: "LOOP"
        case .bounce: "BOUNCE"
        case .longExposure: "LONG EXPOSURE"
        }
    }

    var systemImage: String {
        switch self {
        case .livePhoto: "livephoto"
        case .loop: "repeat"
        case .bounce: "arrow.left.arrow.right"
        case .longExposure: "camera.aperture"
        }
    }
}

enum LiveEffectsService {
    enum EffectError: LocalizedError {
        case noFrames, writeFailed

        var errorDescription: String? {
            switch self {
            case .noFrames: "No frames could be read from the video."
            case .writeFailed: "The effect couldn't be written."
            }
        }
    }

    static let fps: Int32 = 30
    static let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Effects", isDirectory: true)

    static func newURL(_ ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    /// Frame times at `fps` across `range`.
    static func frameTimes(in range: CMTimeRange) -> [CMTime] {
        let count = max(1, Int((range.duration.seconds * Double(fps)).rounded(.down)))
        return (0..<count).map { CMTimeAdd(range.start, CMTime(value: CMTimeValue($0), timescale: fps)) }
    }

    /// Loop plays the clip three times; Bounce plays it forward then backward, twice.
    static func sequence(for effect: LiveEffect, in range: CMTimeRange) -> [CMTime] {
        let forward = frameTimes(in: range)
        switch effect {
        case .loop: return forward + forward + forward
        case .bounce:
            let backward = Array(forward.reversed().dropFirst().dropLast())
            return (forward + backward) + (forward + backward)
        case .livePhoto, .longExposure: return forward
        }
    }

    /// Reads frames (with the current adjustments applied) and writes them as an H.264 movie.
    static func renderMovie(
        from asset: AVAsset, times: [CMTime], adjustments: PhotoAdjustmentState,
        processor: ImageProcessingService, to url: URL,
        metadata: [AVMetadataItem] = [], stillImageTime: CMTime? = nil
    ) async throws {
        let recipe = AdjustmentBox()
        recipe.value = adjustments
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        if !adjustments.isIdentity {
            generator.videoComposition = try? await VideoService.composition(for: asset, recipe: recipe, processor: processor)
        }

        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var stillAdaptor: AVAssetWriterInputMetadataAdaptor?
        var index: Int64 = 0

        for await result in generator.images(for: times) {
            guard let frame = try? result.image else { continue }
            if writer == nil {
                let created = try AVAssetWriter(outputURL: url, fileType: .mov)
                created.metadata = metadata
                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: frame.width,
                    AVVideoHeightKey: frame.height,
                ])
                videoInput.expectsMediaDataInRealTime = false
                created.add(videoInput)
                adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: frame.width,
                    kCVPixelBufferHeightKey as String: frame.height,
                ])
                if stillImageTime != nil, let format = stillImageTimeFormat() {
                    let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
                    created.add(metadataInput)
                    stillAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
                }
                guard created.startWriting() else { throw EffectError.writeFailed }
                created.startSession(atSourceTime: .zero)
                writer = created
                input = videoInput
            }
            guard let input, let adaptor, let pool = adaptor.pixelBufferPool else { throw EffectError.writeFailed }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw EffectError.writeFailed }
            processor.context.render(CIImage(cgImage: frame), to: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: fps))
            index += 1
        }

        guard let writer, let input else { throw EffectError.noFrames }
        if let stillAdaptor, let stillImageTime {
            let item = AVMutableMetadataItem()
            item.key = "com.apple.quicktime.still-image-time" as NSString
            item.keySpace = .quickTimeMetadata
            item.value = 0 as NSNumber
            item.dataType = kCMMetadataBaseDataType_SInt8 as String
            stillAdaptor.append(AVTimedMetadataGroup(
                items: [item],
                timeRange: CMTimeRange(start: stillImageTime, duration: CMTime(value: 1, timescale: 100))
            ))
            stillAdaptor.assetWriterInput.markAsFinished()
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? EffectError.writeFailed }
    }

    /// Long Exposure: averages up to 60 frames into one still (silky water, light trails).
    static func longExposure(from asset: AVAsset, range: CMTimeRange, adjustments: PhotoAdjustmentState,
                             processor: ImageProcessingService) async throws -> Data {
        let all = frameTimes(in: range)
        let step = max(1, all.count / 60)
        let times = stride(from: 0, to: all.count, by: step).map { all[$0] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 2400, height: 2400)

        var accumulator: CIImageAccumulator?
        var count = 0
        for await result in generator.images(for: times) {
            guard let cgFrame = try? result.image else { continue }
            let frame = CIImage(cgImage: cgFrame)
            if accumulator == nil { accumulator = CIImageAccumulator(extent: frame.extent, format: .RGBAf) }
            guard let accumulator else { continue }
            count += 1
            // Running mean: acc = acc * (n-1)/n + frame / n
            let weight = 1 / CGFloat(count)
            let scaledFrame = frame.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: weight, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: weight, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: weight, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            let kept = accumulator.image().applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1 - weight, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 - weight, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - weight, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            accumulator.setImage(count == 1 ? frame : scaledFrame.applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: kept,
            ]).cropped(to: frame.extent))
        }
        guard let accumulator, count > 0 else { throw EffectError.noFrames }
        let averaged = processor.apply(adjustments, to: accumulator.image().cropped(to: accumulator.extent))
        return try processor.encode(averaged, as: .jpeg)
    }

    // MARK: Video → Live Photo

    /// Writes a Live Photo pair: a JPEG still (key frame) and a movie of `range`, linked by a shared
    /// content identifier and a still-image-time marker, as Photos expects.
    static func makeLivePhoto(from asset: AVAsset, range: CMTimeRange, keyTime: CMTime,
                              adjustments: PhotoAdjustmentState, processor: ImageProcessingService) async throws -> (photo: URL, video: URL) {
        let identifier = UUID().uuidString
        let photoURL = try newURL("jpg")
        let videoURL = try newURL("mov")

        // Still image at the key time, with the pairing identifier in Apple's maker note (key "17").
        let still = try await VideoService.frame(of: asset, at: keyTime, composition: nil)
        let edited = processor.apply(adjustments, to: CIImage(cgImage: still))
        guard let stillImage = processor.context.createCGImage(edited, from: edited.extent),
              let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw EffectError.writeFailed }
        CGImageDestinationAddImage(destination, stillImage, [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EffectError.writeFailed }

        // Movie with the same identifier and the still marker at the key frame.
        let identifierItem = AVMutableMetadataItem()
        identifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        identifierItem.keySpace = .quickTimeMetadata
        identifierItem.value = identifier as NSString
        identifierItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        let keyOffset = CMTimeSubtract(keyTime, range.start)
        try await renderMovie(from: asset, times: frameTimes(in: range), adjustments: adjustments, processor: processor,
                              to: videoURL, metadata: [identifierItem], stillImageTime: keyOffset)
        return (photoURL, videoURL)
    }

    static func saveLivePhotoToLibrary(photo: URL, video: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ScreenCapture.CaptureError.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photo, options: nil)
            request.addResource(with: .pairedVideo, fileURL: video, options: nil)
        }
    }

    /// Format description for the still-image-time timed metadata track.
    private static func stillImageTimeFormat() -> CMFormatDescription? {
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8 as String,
        ]
        var description: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &description)
        return description
    }
}
