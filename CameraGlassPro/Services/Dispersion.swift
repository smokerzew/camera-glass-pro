import CoreImage
import CoreImage.CIFilterBuiltins

extension ImageProcessingService {
    /// Dispersion: the side of the subject facing `degrees` (0 right, 90 up) breaks into square particles
    /// that drift that way. `amount` sets how much breaks off and how far it flies; `size` the particle size.
    func dispersion(_ image: CIImage, mask: CIImage, amount: Double, size: Double, degrees: Double = 0,
                    extent e: CGRect) -> CIImage {
        guard amount > 0, let box = maskBounds(mask, extent: e) else { return image }
        let k = CGFloat(min(amount, 1))
        let cell = max(2, e.width * (0.004 + 0.022 * CGFloat(min(max(size, 0), 1))))

        // Drift direction (Core Image y points up, like the slider's 90° = up).
        let radians = CGFloat(degrees) * .pi / 180
        let dir = CGPoint(x: cos(radians), y: sin(radians))
        let side = CGPoint(x: -dir.y, y: dir.x)
        // Where the subject breaks up: from part-way across it to its edge facing `dir` (wider with more strength).
        let reach = abs(dir.x) * box.width / 2 + abs(dir.y) * box.height / 2
        let center = CGPoint(x: box.midX, y: box.midY)
        let zoneGradient = CIFilter.linearGradient()
        zoneGradient.point0 = CGPoint(x: center.x + dir.x * reach * (0.6 - 1.1 * k), y: center.y + dir.y * reach * (0.6 - 1.1 * k))
        zoneGradient.point1 = CGPoint(x: center.x + dir.x * reach, y: center.y + dir.y * reach)
        zoneGradient.color0 = .black
        zoneGradient.color1 = .white
        guard let zone = zoneGradient.outputImage?.cropped(to: e) else { return image }

        /// Square cells that are on (white) where the random value passes `threshold`.
        func particles(seed: CGFloat, threshold: CGFloat) -> CIImage {
            let columns = ceil(e.width / cell) + 2, rows = ceil(e.height / cell) + 2
            let grid = CGRect(x: seed, y: seed * 0.7, width: columns, height: rows)
            return (CIFilter.randomGenerator().outputImage ?? CIImage(color: .black))
                .cropped(to: grid)
                .settingAlphaOne(in: grid) // the generator's alpha is random too
                .transformed(by: CGAffineTransform(translationX: -grid.minX, y: -grid.minY))
                .samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: cell, y: cell).concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
                .samplingNearest()
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 40, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 40, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 40, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: -40 * threshold, y: -40 * threshold, z: -40 * threshold, w: 1),
                ])
                .applyingFilter("CIColorClamp")
                .cropped(to: e)
        }
        func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
            a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b]).cropped(to: e)
        }
        func blend(_ top: CIImage, over base: CIImage, mask: CIImage) -> CIImage {
            top.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base, kCIInputMaskImageKey: mask])
                .cropped(to: e)
        }

        // Holes: particle cells inside the zone, more of them with more strength.
        let holes = multiply(particles(seed: 0, threshold: 0.75 - 0.45 * k), zone)
        let subject = mask.cropped(to: e)
        let removed = multiply(subject, holes)
        let kept = multiply(subject, holes.applyingFilter("CIColorInvert").cropped(to: e))

        // Behind the gaps: the scene with the subject's area filled by a heavy blur (no ghost of the subject).
        let grown = subject.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 40)).cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 3, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 3, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 3, w: 0),
            ])
            .applyingFilter("CIColorClamp")
        let fill = image.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 25)).cropped(to: e)
        let plate = blend(fill, over: image, mask: grown)
        var output = blend(image, over: plate, mask: kept)

        // The broken-off pieces fly along `dir` (curving slightly), thinning out and fading as they go.
        let step = cell * (2 + 14 * k)
        for (index, fade) in [(1, 0.95), (2, 0.7), (3, 0.45), (4, 0.25)] {
            let i = CGFloat(index)
            let move = CGAffineTransform(translationX: (dir.x + side.x * 0.25) * step * i,
                                         y: (dir.y + side.y * 0.25) * step * i)
            let scatter = multiply(removed, particles(seed: 37 * i, threshold: 0.2 + 0.12 * i))
            let pieces = scatter.transformed(by: move).cropped(to: e)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: fade, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: fade, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: fade, w: 0),
                ])
            output = blend(image.transformed(by: move), over: output, mask: pieces)
        }
        return output.cropped(to: e)
    }
}
