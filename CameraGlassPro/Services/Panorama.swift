import CoreImage
import Foundation

/// PANO mode: stitches 2-8 overlapping photos, taken left to right (or right to left) by turning in place,
/// into one wide panorama. Each photo is projected onto a cylinder, neighbors are lined up with Vision,
/// exposure is matched in the overlap, the seams are feathered, and the ragged edges are cropped away.
enum PanoStitcher {
    static let maxPhotos = 8
    /// Cylinder radius as a fraction of photo width: about a 26 mm (main camera) field of view.
    static let mainCameraFocal: CGFloat = 0.75

    enum PanoError: LocalizedError {
        case needTwo, noOverlap

        var errorDescription: String? {
            switch self {
            case .needTwo: "Pick at least two photos for a panorama."
            case .noOverlap: "These photos don't overlap enough to stitch. Take each one so it shares about a third with the last."
            }
        }
    }

    /// `focalScale` nil skips the cylinder (photos that were shifted, not turned).
    static func stitch(_ inputs: [CIImage], focalScale: CGFloat? = mainCameraFocal, context: CIContext) throws -> CIImage {
        guard inputs.count >= 2 else { throw PanoError.needTwo }
        // Same height for all, origin at zero, then onto the cylinder.
        let height = inputs.map(\.extent.height).min() ?? 1
        let images: [CIImage] = inputs.prefix(maxPhotos).map { image in
            let e = image.extent
            let s = height / e.height
            let flat = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
                .concatenating(CGAffineTransform(scaleX: s, y: s)))
            return focalScale.map { cylinder(flat, focal: $0 * flat.extent.width) } ?? flat
        }

        // Positions: each photo lined up on the one before it.
        var placed: [CIImage] = [images[0]]
        var position = CGPoint.zero
        for index in 1..<images.count {
            let image = images[index]
            guard let shift = Registration.translation(of: image, to: images[index - 1],
                                                       maxShift: CGSize(width: 0.95, height: 0.15), context: context)
            else { continue }
            let width = image.extent.width
            // A near-zero shift is a duplicate; more than 90% means they don't overlap.
            guard abs(shift.x) > width * 0.05, abs(shift.x) < width * 0.9, abs(shift.y) < height * 0.25 else { continue }
            position = CGPoint(x: position.x + shift.x, y: position.y + shift.y)
            placed.append(image.transformed(by: CGAffineTransform(translationX: position.x, y: position.y)))
        }
        guard placed.count >= 2 else { throw PanoError.noOverlap }

        // Feathered seams, in placing order, with each photo's exposure matched to the canvas in the overlap.
        var canvas = placed[0]
        for index in 1..<placed.count {
            var next = placed[index]
            let overlap = canvas.extent.intersection(next.extent)
            guard !overlap.isEmpty else { continue }
            if let a = averageLuma(canvas, in: overlap, context: context), let b = averageLuma(next, in: overlap, context: context), b > 0.001 {
                let gain = min(max(a / b, 0.8), 1.25)
                next = next.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                ]).cropped(to: next.extent)
            }
            // A soft ramp across the middle third of the overlap, toward the new photo's side.
            let goingRight = next.extent.midX > canvas.extent.midX
            let ramp = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: overlap.midX - overlap.width / 6, y: 0),
                "inputPoint1": CIVector(x: overlap.midX + overlap.width / 6, y: 0),
                "inputColor0": goingRight ? CIColor.black : CIColor.white,
                "inputColor1": goingRight ? CIColor.white : CIColor.black,
            ])?.outputImage ?? CIImage(color: .white)
            let mask = ramp.cropped(to: next.extent).composited(over: CIImage(color: .black))
            canvas = next.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: canvas, kCIInputMaskImageKey: mask,
            ]).cropped(to: canvas.extent.union(next.extent))
        }

        // Keep the band every photo covers (the cylinder bends their top and bottom edges).
        let bands = placed.map { image -> (CGFloat, CGFloat) in
            let e = image.extent
            // At the photo's side edges (angle atan(1/2f)) its height shrinks by cos of that angle.
            let sag = focalScale.map { e.height * (1 - cos(atan(1 / (2 * $0)))) / 2 } ?? 0
            return (e.minY + sag, e.maxY - sag)
        }
        let bottom = (bands.map(\.0).max() ?? 0).rounded(.up)
        let top = (bands.map(\.1).min() ?? height).rounded(.down)
        let left = (placed.map(\.extent.minX).min() ?? 0).rounded(.up)
        let right = (placed.map(\.extent.maxX).max() ?? 0).rounded(.down)
        guard top - bottom > height * 0.3, right > left else { throw PanoError.noOverlap }
        let crop = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        return canvas.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    /// Projects a photo (origin at zero) onto a cylinder of radius `focal` pixels; the result starts at zero.
    static func cylinder(_ image: CIImage, focal: CGFloat) -> CIImage {
        guard let kernel = ImageProcessingService.cylinderWarpKernel, focal > 0 else { return image }
        let e = image.extent
        let half = focal * atan(e.width / 2 / focal)
        let out = CGRect(x: e.midX - half, y: e.minY, width: half * 2, height: e.height).integral
        guard let warped = kernel.apply(extent: out, roiCallback: { _, _ in e }, image: image,
                                        arguments: [Float(e.midX), Float(e.midY), Float(focal)]) else { return image }
        // Outside the photo the warp samples nothing: keep it transparent, then move to zero.
        return warped.cropped(to: out).transformed(by: CGAffineTransform(translationX: -out.minX, y: -out.minY))
    }

    private static func averageLuma(_ image: CIImage, in rect: CGRect, context: CIContext) -> CGFloat? {
        guard let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return CGFloat(0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2])
    }
}
