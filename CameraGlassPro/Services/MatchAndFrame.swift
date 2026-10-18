import AVFoundation
import CoreImage

extension ImageProcessingService {
    /// Brightness and color statistics of a photo (from a small copy).
    func colorStats(of image: CGImage) -> ColorStats {
        let side = 128
        let input = CIImage(cgImage: image)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / input.extent.width,
                                                             y: CGFloat(side) / input.extent.height))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(scaled, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return ColorStats.from(rgba: pixels)
    }

    func applyLookMatch(_ match: LookMatch, to image: CIImage, extent: CGRect) -> CIImage {
        guard match.isUsable, match.amount > 0, let kernel = Self.kernel("matchLook") else { return image }
        let scale = CIVector(x: match.scale[0], y: match.scale[1], z: match.scale[2])
        let offset = CIVector(x: match.offset[0], y: match.offset[1], z: match.offset[2])
        return kernel.apply(extent: image.extent.isInfinite ? extent : image.extent,
                            arguments: [image, scale, offset, Float(min(match.amount, 1))]) ?? image
    }

    /// The video frame at `time` at full resolution, oriented, with the edits applied (no crop: videos keep their frame).
    func editedFrame(of asset: AVAsset, at time: CMTime, adjustments: PhotoAdjustmentState,
                     backgroundPhoto: CIImage?) async throws -> CIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (frame, _) = try await generator.image(at: time)
        return apply(adjustments.withoutGeometry, to: CIImage(cgImage: frame), backgroundPhoto: backgroundPhoto)
    }
}
