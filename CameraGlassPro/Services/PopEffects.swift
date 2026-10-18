import CoreImage
import CoreImage.CIFilterBuiltins

/// FX > Pop: glitch, light leak, duotone, kaleidoscope, fisheye, pixel art, 3D anaglyph, CRT TV, comic and glitter.
/// One at a time; `amount` blends the effect over the photo, `option` (0...1) is the effect's own setting.
extension ImageProcessingService {
    func pop(_ image: CIImage, effect: PopEffect, amount: Double, option: Double, extent e: CGRect) -> CIImage {
        guard amount > 0, effect != .none else { return image }
        let k = min(amount, 1)
        let o = CGFloat(min(max(option, 0), 1))
        let styled: CIImage
        switch effect {
        case .none: return image
        case .glitch: styled = glitch(image, extent: e)
        case .lightLeak: styled = lightLeak(image, extent: e)
        case .duotone:
            let pair = Self.duotonePalettes[PopEffect.duotoneIndex(option)]
            styled = image.applyingFilter("CIFalseColor", parameters: ["inputColor0": pair.dark, "inputColor1": pair.light])
        case .kaleidoscope:
            styled = image.clampedToExtent().applyingFilter("CIKaleidoscope", parameters: [
                "inputCount": PopEffect.kaleidoscopeSegments(option),
                kCIInputCenterKey: CIVector(x: e.midX, y: e.midY), kCIInputAngleKey: 0.0,
            ])
        case .fisheye:
            styled = image.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: CIVector(x: e.midX, y: e.midY),
                kCIInputRadiusKey: max(e.width, e.height) * 0.75, kCIInputScaleKey: 0.75,
            ])
            return vignette(image.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: styled.cropped(to: e), kCIInputTimeKey: k,
            ]), amount: 0.6 * k, extent: e).cropped(to: e)
        case .pixelArt:
            let block = max(4, max(e.width, e.height) * (0.008 + 0.04 * o))
            // Blur first: CIPixellate samples one pixel per block, which would alias.
            styled = image.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(block) * 0.35)
                .applyingFilter("CIPixellate", parameters: [kCIInputCenterKey: CIVector(x: e.minX, y: e.minY), kCIInputScaleKey: block])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25])
                .applyingFilter("CILinearToSRGBToneCurve")
                .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 7])
                .applyingFilter("CISRGBToneCurveToLinear")
        case .anaglyph: styled = anaglyph(image, extent: e)
        case .crt: styled = crt(image, extent: e)
        case .comic:
            styled = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4])
                .applyingFilter("CIComicEffect")
        case .glitter: styled = glitter(image, extent: e)
        }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: styled.cropped(to: e), kCIInputTimeKey: k,
        ]).cropped(to: e)
    }

    /// Duotone shadow and highlight colors, in the order of `PopEffect.duotoneNames`.
    private static let duotonePalettes: [(dark: CIColor, light: CIColor)] = [
        (CIColor(red: 0.12, green: 0.05, blue: 0.4), CIColor(red: 1, green: 0.45, blue: 0.7)),
        (CIColor(red: 0.0, green: 0.2, blue: 0.25), CIColor(red: 1, green: 0.6, blue: 0.25)),
        (CIColor(red: 0.25, green: 0.05, blue: 0.35), CIColor(red: 1, green: 0.9, blue: 0.3)),
        (CIColor(red: 0.05, green: 0.08, blue: 0.25), CIColor(red: 0.95, green: 0.2, blue: 0.2)),
        (CIColor(red: 0.05, green: 0.25, blue: 0.15), CIColor(red: 1, green: 0.75, blue: 0.85)),
    ]

    /// Torn horizontal slices shifted sideways, with the red and blue channels pulled apart.
    private func glitch(_ image: CIImage, extent e: CGRect) -> CIImage {
        var rng = SplitMix64(seed: 0x6C17C4) // same slices every frame, so video doesn't flicker
        var output = image
        for _ in 0..<9 {
            let height = e.height * CGFloat.random(in: 0.01...0.07, using: &rng)
            let y = e.minY + CGFloat.random(in: 0...1, using: &rng) * (e.height - height)
            let shift = e.width * CGFloat.random(in: -0.08...0.08, using: &rng)
            let band = CGRect(x: e.minX, y: y, width: e.width, height: height)
            output = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: shift, y: 0))
                .cropped(to: band).composited(over: output)
        }
        guard let kernel = Self.kernel("combineChannels") else { return output }
        let split = e.width * 0.012
        func moved(_ dx: CGFloat) -> CIImage {
            output.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: 0)).cropped(to: e)
        }
        return kernel.apply(extent: e, arguments: [moved(split), output, moved(-split)])?.cropped(to: e) ?? output
    }

    /// Warm orange and magenta film light bleeding in from the edges.
    private func lightLeak(_ image: CIImage, extent e: CGRect) -> CIImage {
        let size = max(e.width, e.height)
        func leak(_ x: CGFloat, _ y: CGFloat, _ color: CIColor, _ radius: CGFloat) -> CIImage {
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: x, y: y)
            g.radius0 = 0
            g.radius1 = Float(radius)
            g.color0 = color
            g.color1 = CIColor(red: 0, green: 0, blue: 0)
            return (g.outputImage ?? CIImage(color: .black)).cropped(to: e)
        }
        let orange = leak(e.minX, e.maxY - e.height * 0.3, CIColor(red: 1, green: 0.45, blue: 0.1), size * 0.6)
        let pink = leak(e.maxX, e.minY + e.height * 0.2, CIColor(red: 0.9, green: 0.15, blue: 0.4), size * 0.45)
        let warm = orange.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        return pink.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: warm])
    }

    /// Red/cyan 3D: the red channel from a view shifted left, green and blue from one shifted right.
    private func anaglyph(_ image: CIImage, extent e: CGRect) -> CIImage {
        guard let kernel = Self.kernel("combineChannels") else { return image }
        let shift = e.width * 0.012
        func moved(_ dx: CGFloat) -> CIImage {
            image.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: 0)).cropped(to: e)
        }
        let right = moved(shift)
        return kernel.apply(extent: e, arguments: [moved(-shift), right, right])?.cropped(to: e) ?? image
    }

    /// Old tube TV: soft picture, bright scan lines, a little bloom, curved dark corners.
    private func crt(_ image: CIImage, extent e: CGRect) -> CIImage {
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = .white
        stripes.color1 = CIColor(red: 0.35, green: 0.35, blue: 0.35)
        stripes.width = Float(max(1.5, e.height / 260))
        stripes.sharpness = 0.3
        let lines = (stripes.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: e)
        let soft = image.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 700)).cropped(to: e)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2, kCIInputContrastKey: 1.1])
        let scanned = lines.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: soft])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.5])
        let curved = scanned.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: CIVector(x: e.midX, y: e.midY), kCIInputRadiusKey: max(e.width, e.height), kCIInputScaleKey: 0.15,
        ]).cropped(to: e)
        return vignette(ortonGlow(curved, amount: 0.3, extent: e), amount: 0.8, extent: e)
    }

    /// Scattered glints over the photo, brightest on the light parts, like glitter on the lens.
    private func glitter(_ image: CIImage, extent e: CGRect) -> CIImage {
        let cell = max(1, max(e.width, e.height) / 500)
        let cells = CGRect(x: 0, y: 0, width: ceil(e.width / cell) + 2, height: ceil(e.height / cell) + 2)
        // Keep only the top ~1.5% of random values as specks, white and a touch of gold.
        let specks = (CIFilter.randomGenerator().outputImage ?? CIImage(color: .black))
            .cropped(to: cells)
            .settingAlphaOne(in: cells)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 40, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 36, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 30, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -39.4, y: -35.5, z: -29.6, w: 0),
            ])
            .applyingFilter("CIColorClamp")
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell).concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
            .cropped(to: e)
        let glints = specks.applyingGaussianBlur(sigma: Double(cell) * 0.6).cropped(to: e)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.2])
        let sparkled = glints.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        return sparkle(sparkled, amount: 0.5, extent: e)
    }
}
