import CoreImage
import CoreImage.CIFilterBuiltins

/// FX > Weather (one at a time): fog, rain, snow and god rays.
enum WeatherEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, fog, rain, snow, rays

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Off"
        case .rays: "God Rays"
        default: rawValue.capitalized
        }
    }
    /// What the effect's second slider does.
    var optionTitle: String {
        switch self {
        case .fog: "Height"
        case .rain: "Angle"
        case .snow: "Flake Size"
        case .rays: "Length"
        case .none: ""
        }
    }
}

/// FX > Art > Paint styles.
enum PaintStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case oil, watercolor, sketch

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// FX > Art > Mirror: which half is kept and reflected onto the other.
enum MirrorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, left, right, top, bottom

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

extension ImageProcessingService {
    // MARK: Weather

    func weather(_ image: CIImage, effect: WeatherEffect, amount: Double, option: Double, extent e: CGRect) -> CIImage {
        let k = CGFloat(min(max(amount, 0), 1)), o = CGFloat(min(max(option, 0), 1))
        guard k > 0 else { return image }
        switch effect {
        case .none: return image
        case .fog: return fog(image, k: k, height: o, extent: e)
        case .rain: return rain(image, k: k, angle: o, extent: e)
        case .snow: return snow(image, k: k, size: o, extent: e)
        case .rays: return godRays(image, k: k, length: o, extent: e)
        }
    }

    /// Fog: a soft, cool haze, thickest higher up in the frame (far away) and thinnest near the bottom.
    private func fog(_ image: CIImage, k: CGFloat, height: CGFloat, extent e: CGRect) -> CIImage {
        let haze = image.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 40)).cropped(to: e)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.3])
            .applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: CIImage(color: CIColor(red: 0.78, green: 0.8, blue: 0.84)).cropped(to: e), kCIInputTimeKey: 0.65,
            ]).cropped(to: e)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: e.midX, y: e.minY + e.height * (0.05 + 0.4 * height))
        gradient.point1 = CGPoint(x: e.midX, y: e.minY + e.height * (0.55 + 0.4 * height))
        gradient.color0 = CIColor(red: 0.25 * k, green: 0.25 * k, blue: 0.25 * k)
        gradient.color1 = CIColor(red: 0.85 * k, green: 0.85 * k, blue: 0.85 * k)
        guard let mask = gradient.outputImage?.cropped(to: e) else { return image }
        return haze.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
            .cropped(to: e)
    }

    /// Sparse random specks (fixed pattern, so video doesn't flicker), `keep` = share of cells that become specks.
    private func specks(_ e: CGRect, cell: CGFloat, keep: CGFloat, seed: CGFloat) -> CIImage {
        let cells = CGRect(x: 0, y: 0, width: ceil(e.width / cell) + 2, height: ceil(e.height / cell) + 2)
        let gain = 1 / max(keep, 0.001)
        return (CIFilter.randomGenerator().outputImage ?? CIImage(color: .black))
            .transformed(by: CGAffineTransform(translationX: seed, y: seed * 0.7))
            .cropped(to: cells)
            .settingAlphaOne(in: cells)
            .applyingFilter("CIColorMatrix", parameters: [ // only the top `keep` share of values survives
                "inputRVector": CIVector(x: 0, y: gain, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: gain, z: 0, w: 0), "inputBiasVector": CIVector(x: 1 - gain, y: 1 - gain, z: 1 - gain, w: 0),
            ])
            .applyingFilter("CIColorClamp")
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell).concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
            .cropped(to: e)
    }

    /// Rain: thin bright streaks at an angle, a slightly cooler, softer scene.
    private func rain(_ image: CIImage, k: CGFloat, angle: CGFloat, extent e: CGRect) -> CIImage {
        let cell = max(1, e.width / 700)
        let drops = specks(e, cell: cell, keep: 0.004 + 0.006 * k, seed: 311)
        let tilt = (-90 + (angle - 0.5) * 50) * .pi / 180 // mostly falling, leaning up to ±25°
        let streaks = drops.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: e.width / 40, kCIInputAngleKey: tilt,
        ]).cropped(to: e).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 2.2 * k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 2.3 * k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 2.5 * k, w: 0),
        ])
        let wet = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.2 * k, kCIInputBrightnessKey: -0.03 * k])
            .applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + 600 * k, y: 0),
            ])
        return streaks.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: wet]).cropped(to: e)
    }

    /// Snow: soft round flakes of two sizes, a touch cooler and brighter.
    private func snow(_ image: CIImage, k: CGFloat, size: CGFloat, extent e: CGRect) -> CIImage {
        let base = max(1.5, e.width / 500) * (0.6 + 1.6 * size)
        let near = specks(e, cell: base * 1.6, keep: 0.01 + 0.02 * k, seed: 97).applyingGaussianBlur(sigma: Double(base * 0.5))
        let far = specks(e, cell: base * 0.8, keep: 0.015 + 0.03 * k, seed: 513).applyingGaussianBlur(sigma: Double(base * 0.3))
        let flakes = near.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: far]).cropped(to: e)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.2 * k])
        let cold = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + 800 * k, y: 0),
        ]).applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.15 * k])
        return flakes.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: cold]).cropped(to: e)
    }

    /// God rays: warm beams streaming out from the brightest part of the photo.
    private func godRays(_ image: CIImage, k: CGFloat, length: CGFloat, extent e: CGRect) -> CIImage {
        let source = brightestPoint(image, extent: e)
        let lights = image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 2.2, kCIInputBrightnessKey: -0.45])
            .applyingFilter("CIColorClamp").cropped(to: e)
        let beams = lights.clampedToExtent().applyingFilter("CIZoomBlur", parameters: [
            kCIInputCenterKey: CIVector(x: source.x, y: source.y), "inputAmount": e.width / 6 * (0.4 + 1.2 * length),
        ]).cropped(to: e).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.6 * k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1.35 * k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.9 * k, w: 0),
        ])
        return beams.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
    }

    /// The brightest spot (on a small copy), in image coordinates.
    func brightestPoint(_ image: CIImage, extent e: CGRect) -> CGPoint {
        let side = 48
        let small = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(side) / e.width, y: CGFloat(side) / e.height)))
            .clampedToExtent().applyingGaussianBlur(sigma: 1.5)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(small, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var best = (value: -1, x: side / 2, y: side / 2)
        for y in 0..<side { for x in 0..<side {
            let i = (y * side + x) * 4
            let v = Int(pixels[i]) * 2 + Int(pixels[i + 1]) * 5 + Int(pixels[i + 2])
            if v > best.value { best = (v, x, y) }
        } }
        // Bitmap rows run top to bottom; Core Image's y runs up.
        return CGPoint(x: e.minX + (CGFloat(best.x) + 0.5) / CGFloat(side) * e.width,
                       y: e.maxY - (CGFloat(best.y) + 0.5) / CGFloat(side) * e.height)
    }

    // MARK: Light additions

    /// Anamorphic flare: long horizontal blue streaks through the bright lights, like cinema lenses.
    func anamorphicFlare(_ image: CIImage, amount: Double, width: Double, extent e: CGRect) -> CIImage {
        let k = CGFloat(min(max(amount, 0), 1))
        guard k > 0 else { return image }
        let lights = image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 3, kCIInputBrightnessKey: -0.7])
            .applyingFilter("CIColorClamp").cropped(to: e)
        let streak = lights.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: e.width * (0.08 + 0.3 * CGFloat(min(max(width, 0), 1))), kCIInputAngleKey: 0,
        ]).cropped(to: e).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.5 * k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1.6 * k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 4 * k, w: 0),
        ])
        return streak.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
    }

    /// Prism: a soft rainbow of refracted light falling across one side, like shooting through a glass prism.
    func prism(_ image: CIImage, amount: Double, position: Double, extent e: CGRect) -> CIImage {
        let k = CGFloat(min(max(amount, 0), 1))
        guard k > 0 else { return image }
        let y = e.minY + e.height * (1 - CGFloat(min(max(position, 0), 1)))
        let colors: [CIColor] = [CIColor(red: 1, green: 0.2, blue: 0.2), CIColor(red: 1, green: 0.75, blue: 0.1),
                                 CIColor(red: 0.2, green: 1, blue: 0.4), CIColor(red: 0.2, green: 0.6, blue: 1), CIColor(red: 0.7, green: 0.3, blue: 1)]
        var rainbow = CIImage(color: .black).cropped(to: e)
        for (i, color) in colors.enumerated() {
            let band = CIFilter.radialGradient()
            band.center = CGPoint(x: e.minX + e.width * (0.04 + 0.05 * CGFloat(i)), y: y + e.height * 0.04 * CGFloat(i))
            band.radius0 = 0
            band.radius1 = Float(e.width * 0.16)
            band.color0 = CIColor(red: color.red * 0.55 * k, green: color.green * 0.55 * k, blue: color.blue * 0.55 * k)
            band.color1 = .black
            if let glow = band.outputImage?.cropped(to: e) {
                rainbow = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: rainbow]).cropped(to: e)
            }
        }
        let streak = rainbow.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: e.width / 10, kCIInputAngleKey: -0.35,
        ]).cropped(to: e)
        return streak.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
    }

    // MARK: Art additions

    /// Paint: oil (smooth, painterly strokes), watercolor (soft washes with darker edges) or pencil sketch.
    func paint(_ image: CIImage, style: PaintStyle, amount: Double, extent e: CGRect) -> CIImage {
        let k = min(max(amount, 0), 1)
        guard k > 0 else { return image }
        let styled: CIImage
        switch style {
        case .oil:
            // Median smoothing at a reduced size flattens detail into brush-like patches, then a crisp edge.
            let s = min(1, 900 / max(e.width, e.height))
            let small = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
                .concatenating(CGAffineTransform(scaleX: s, y: s)))
            var smooth = small
            for _ in 0..<3 { smooth = smooth.applyingFilter("CIMedianFilter") }
            styled = smooth.transformed(by: CGAffineTransform(scaleX: 1 / s, y: 1 / s)
                .concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
                .applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: max(2, e.width / 400), kCIInputIntensityKey: 0.8])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
                .cropped(to: e)
        case .watercolor:
            let wash = image.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 300)).cropped(to: e)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.1, kCIInputBrightnessKey: 0.04])
                .applyingFilter("CILinearToSRGBToneCurve").applyingFilter("CIColorPosterize", parameters: ["inputLevels": 12])
                .applyingFilter("CISRGBToneCurveToLinear")
            let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3]).cropped(to: e)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                .applyingFilter("CIColorInvert")
            styled = edges.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: wash]).cropped(to: e)
        case .sketch:
            let gray = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            // Pencil: the gray photo divided by its blurred inverse (a classic color-dodge sketch).
            let inverse = gray.applyingFilter("CIColorInvert").clampedToExtent()
                .applyingGaussianBlur(sigma: Double(max(2, e.width / 250))).cropped(to: e)
            styled = inverse.applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: gray])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.2])
                .cropped(to: e)
        }
        return image.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: styled, kCIInputTimeKey: k])
            .cropped(to: e)
    }

    /// Mirror: one half of the picture reflected onto the other, for symmetry.
    func mirror(_ image: CIImage, mode: MirrorMode, extent e: CGRect) -> CIImage {
        let flip: CGAffineTransform
        let keep: CGRect
        switch mode {
        case .off: return image
        case .left:
            keep = CGRect(x: e.minX, y: e.minY, width: e.width / 2, height: e.height)
            flip = CGAffineTransform(translationX: 2 * e.midX, y: 0).scaledBy(x: -1, y: 1)
        case .right:
            keep = CGRect(x: e.midX, y: e.minY, width: e.width / 2, height: e.height)
            flip = CGAffineTransform(translationX: 2 * e.midX, y: 0).scaledBy(x: -1, y: 1)
        case .top:
            keep = CGRect(x: e.minX, y: e.midY, width: e.width, height: e.height / 2)
            flip = CGAffineTransform(translationX: 0, y: 2 * e.midY).scaledBy(x: 1, y: -1)
        case .bottom:
            keep = CGRect(x: e.minX, y: e.minY, width: e.width, height: e.height / 2)
            flip = CGAffineTransform(translationX: 0, y: 2 * e.midY).scaledBy(x: 1, y: -1)
        }
        let half = image.cropped(to: keep)
        return half.composited(over: half.transformed(by: flip)).cropped(to: e)
    }
}
