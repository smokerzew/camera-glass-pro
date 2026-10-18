import CoreImage
import CoreImage.CIFilterBuiltins

extension ImageProcessingService {
    /// Dispersion: the side of the subject facing `degrees` (0 right, 90 up) breaks into chunks that drift
    /// that way. The edge erodes organically (more pieces near the leading edge), big and small chunks break
    /// off together, and the trail thins out: farther pieces are smaller, sparser, fainter and a little streaked.
    /// `amount` sets how much breaks off and how far it flies; `size` sets the chunk size.
    func dispersion(_ image: CIImage, mask: CIImage, amount: Double, size: Double, degrees: Double = 0,
                    extent e: CGRect) -> CIImage {
        guard amount > 0, let box = maskBounds(mask, extent: e), let holesKernel = Self.kernel("dispersionHoles")
        else { return image }
        let k = CGFloat(min(amount, 1))
        let chunk = max(2, e.width * (0.003 + 0.02 * CGFloat(min(max(size, 0), 1))))

        // Drift direction (Core Image y points up, like the slider's 90° = up).
        let radians = CGFloat(degrees) * .pi / 180
        let dir = CGPoint(x: cos(radians), y: sin(radians))
        let side = CGPoint(x: -dir.y, y: dir.x)
        let reach = abs(dir.x) * box.width / 2 + abs(dir.y) * box.height / 2
        let center = CGPoint(x: box.midX, y: box.midY)

        // How likely each spot is to break off: 0 deep inside, rising to 1 at the leading edge.
        let zoneGradient = CIFilter.linearGradient()
        let start = reach * (0.7 - 1.2 * k)
        zoneGradient.point0 = CGPoint(x: center.x + dir.x * start, y: center.y + dir.y * start)
        zoneGradient.point1 = CGPoint(x: center.x + dir.x * reach * 1.05, y: center.y + dir.y * reach * 1.05)
        zoneGradient.color0 = .black
        zoneGradient.color1 = .white
        guard let zone = zoneGradient.outputImage?.cropped(to: e) else { return image }

        /// Random value per square cell (uniform 0...1 in red).
        func grid(cell: CGFloat, seed: CGFloat) -> CIImage {
            let columns = ceil(e.width / cell) + 2, rows = ceil(e.height / cell) + 2
            let cells = CGRect(x: seed, y: seed * 0.7, width: columns, height: rows)
            return (CIFilter.randomGenerator().outputImage ?? CIImage(color: .black))
                .cropped(to: cells)
                .settingAlphaOne(in: cells) // the generator's alpha is random too
                .transformed(by: CGAffineTransform(translationX: -cells.minX, y: -cells.minY))
                .samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: cell, y: cell).concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
                .samplingNearest()
                .cropped(to: e)
        }
        /// Cells that break off: a cell goes when its random value is below the zone's chance there.
        func holes(cell: CGFloat, seed: CGFloat, density: CGFloat) -> CIImage {
            holesKernel.apply(extent: e, arguments: [grid(cell: cell, seed: seed), zone, Float(density)]) ?? CIImage(color: .black).cropped(to: e)
        }
        /// Cells kept for one wave of the trail (a share `keep` of them, at random).
        func scatter(cell: CGFloat, seed: CGFloat, keep: CGFloat) -> CIImage {
            grid(cell: cell, seed: seed).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -60, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: -60, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: -60, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 60 * keep, y: 60 * keep, z: 60 * keep, w: 1),
            ]).applyingFilter("CIColorClamp").cropped(to: e)
        }
        func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
            a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b]).cropped(to: e)
        }
        func blend(_ top: CIImage, over base: CIImage, mask: CIImage) -> CIImage {
            top.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base, kCIInputMaskImageKey: mask])
                .cropped(to: e)
        }

        // Big and small chunks break off together.
        let big = holes(cell: chunk, seed: 0, density: 0.55 + 0.4 * k)
        let small = holes(cell: chunk * 0.5, seed: 11, density: 0.7 + 0.3 * k)
        let gaps = big.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: small]).cropped(to: e)
        let subject = mask.cropped(to: e)
        let removed = multiply(subject, gaps)
        let kept = multiply(subject, gaps.applyingFilter("CIColorInvert").cropped(to: e))

        var output = blend(image, over: subjectPlate(image, mask: subject, extent: e), mask: kept)

        // The trail: seven waves, each farther, with smaller, sparser, fainter pieces on a gentle curve.
        let travel = reach * (0.6 + 2.2 * k)
        let waves = 7
        for wave in 1...waves {
            let t = CGFloat(wave) / CGFloat(waves)
            let distance = travel * pow(t, 1.3)
            let curve = distance * 0.15 * sin(t * .pi)
            let move = CGAffineTransform(translationX: dir.x * distance + side.x * curve, y: dir.y * distance + side.y * curve)
            let cell = max(2, chunk * (1 - 0.55 * t))
            let fade = 0.95 - 0.8 * t
            let pieces = multiply(removed, scatter(cell: cell, seed: 37 * CGFloat(wave), keep: 0.75 - 0.6 * t))
                .transformed(by: move).cropped(to: e)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: fade, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: fade, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: fade, w: 0),
                ])
            var moved = image.transformed(by: move)
            if t > 0.4 { // a little streak on the faster, farther pieces
                moved = moved.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
                    kCIInputRadiusKey: cell * 0.5 * t, kCIInputAngleKey: atan2(dir.y, dir.x),
                ])
            }
            output = blend(moved, over: output, mask: pieces)
        }
        return output.cropped(to: e)
    }

    /// The scene with the subject removed: its area is filled from the surrounding background only
    /// (a normalized blur that ignores the subject's own pixels), so no smudge of the subject is left behind.
    func subjectPlate(_ image: CIImage, mask: CIImage, extent e: CGRect) -> CIImage {
        // Slightly grown mask, so the subject's edge pixels don't bleed into the fill.
        let grown = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 120))).cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 4, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 4, w: 0),
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: e)
        // Background only (transparent where the subject is), blurred, then divided by its coverage:
        // the color matrix un-premultiplies (color / alpha) and makes it opaque again.
        let background = CIImage(color: .clear).cropped(to: e).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: grown,
        ]).cropped(to: e)
        let fill = background.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(2, e.width / 15)))
            .cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        return fill.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: grown,
        ]).cropped(to: e)
    }

    /// Ghost: a translucent copy of the subject (or of the whole photo) moved `distance` toward `degrees`.
    /// With `hideOriginal` the subject leaves its place and only the ghost remains.
    func ghost(_ image: CIImage, mask: CIImage?, opacity: Double, distance: Double, degrees: Double,
               hideOriginal: Bool, extent e: CGRect) -> CIImage {
        guard opacity > 0 else { return image }
        let a = CGFloat(min(opacity, 1))
        let radians = CGFloat(degrees) * .pi / 180
        let shift = CGFloat(min(max(distance, 0), 1)) * 0.35 * max(e.width, e.height)
        let move = CGAffineTransform(translationX: cos(radians) * shift, y: sin(radians) * shift)
        let moved = image.clampedToExtent().transformed(by: move).cropped(to: e)

        guard let mask else {
            // Whole photo: a see-through copy laid over the original (1 = an even double exposure).
            return image.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: moved, kCIInputTimeKey: a * 0.5,
            ]).cropped(to: e)
        }
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 500))).cropped(to: e)
        let scene = hideOriginal ? subjectPlate(image, mask: soft, extent: e) : image
        let ghostMask = soft.clampedToExtent().transformed(by: move).cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: a, w: 0),
            ])
        let ghostImage = image.transformed(by: move)
        return ghostImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: scene, kCIInputMaskImageKey: ghostMask,
        ]).cropped(to: e)
    }
}
