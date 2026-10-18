import AVFoundation
import CoreImage

/// Real Night Mode for Live Photos and videos: several frames around the key moment are lined up and
/// averaged, which cuts noise the way the Camera app's Night mode does, then the cleaner shadows are lifted.
/// Things that moved between frames are taken from the key frame only, so they don't ghost.
enum NightStacker {
    /// Most frames used (about half a second at 30 fps).
    static let maxFrames = 16

    static func stack(_ frames: [CIImage], reference: Int, context: CIContext) -> CIImage {
        guard frames.indices.contains(reference) else { return frames.first ?? CIImage.empty() }
        let ref = frames[reference]
        let e = ref.extent
        guard let accumulator = CIImageAccumulator(extent: e, format: .RGBAh) else { return ref }
        accumulator.setImage(ref)
        var count = 1
        for (index, frame) in frames.enumerated() where index != reference {
            // Frames that moved too far (a pan) can't be lined up well enough; skip them.
            guard let shift = offset(of: frame, to: ref, context: context),
                  hypot(shift.x, shift.y) < e.width * 0.05 else { continue }
            let aligned = frame.clampedToExtent()
                .transformed(by: CGAffineTransform(translationX: shift.x, y: shift.y))
                .cropped(to: e)
            count += 1
            // Running mean: mix in 1/n of the new frame (a linear dissolve, so alpha stays 1).
            let mixed = accumulator.image().applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: deghosted(aligned, reference: ref, extent: e),
                kCIInputTimeKey: 1 / Double(count),
            ]).cropped(to: e)
            accumulator.setImage(mixed)
        }
        let averaged = accumulator.image().cropped(to: e)
        // The averaged frame is clean enough to lift the shadows without lifting noise.
        return averaged.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": count > 1 ? 0.35 : 0.15, "inputHighlightAmount": 1,
        ]).cropped(to: e)
    }

    /// Translation that lines `frame` up with `reference` (hand shake: up to 5% of the frame), in pixels.
    static func offset(of frame: CIImage, to reference: CIImage, context: CIContext) -> CGPoint? {
        Registration.translation(of: frame, to: reference, maxShift: CGSize(width: 0.05, height: 0.05),
                                 minOverlap: 0.8, context: context)
    }

    /// `frame`, except where it differs clearly from the reference (something moved): there it's the reference.
    /// Both are blurred before comparing, so grain alone never counts as movement.
    static func deghosted(_ frame: CIImage, reference: CIImage, extent e: CGRect) -> CIImage {
        let sigma = Double(max(2, e.width / 500))
        func soft(_ image: CIImage) -> CIImage { image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: e) }
        let difference = soft(frame).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: soft(reference)])
            .cropped(to: e)
        // Gray mask: 0 below ~6% average difference, 1 above ~14%.
        let moved = difference.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 4.2, y: 4.2, z: 4.2, w: 0),
            "inputGVector": CIVector(x: 4.2, y: 4.2, z: 4.2, w: 0),
            "inputBVector": CIVector(x: 4.2, y: 4.2, z: 4.2, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: -0.75, y: -0.75, z: -0.75, w: 0),
        ]).applyingFilter("CIColorClamp").cropped(to: e)
        return reference.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: frame, kCIInputMaskImageKey: moved,
        ]).cropped(to: e)
    }
}

extension LiveEffectsService {
    /// Night: up to 16 frames around `keyTime`, lined up, averaged and brightened, with the edits on top.
    /// The result has the motion clip's resolution (a Live Photo's clip is smaller than its photo).
    static func night(from asset: AVAsset, around keyTime: CMTime, range: CMTimeRange,
                      adjustments: PhotoAdjustmentState, processor: ImageProcessingService) async throws -> Data {
        let all = frameTimes(in: range)
        guard !all.isEmpty else { throw EffectError.noFrames }
        let key = all.indices.min { abs(all[$0].seconds - keyTime.seconds) < abs(all[$1].seconds - keyTime.seconds) } ?? 0
        let start = max(0, min(key - NightStacker.maxFrames / 2, all.count - NightStacker.maxFrames))
        let times = Array(all[start..<min(all.count, start + NightStacker.maxFrames)])

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 2400, height: 2400)
        var frames: [CIImage] = []
        for await result in generator.images(for: times) {
            if let frame = try? result.image { frames.append(CIImage(cgImage: frame)) }
        }
        guard !frames.isEmpty else { throw EffectError.noFrames }
        let stacked = NightStacker.stack(frames, reference: min(key - start, frames.count - 1), context: processor.context)
        return try processor.encode(processor.apply(adjustments, to: stacked), as: .jpeg)
    }
}
