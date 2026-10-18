import CoreImage
import CoreImage.CIFilterBuiltins

/// Light FX (window blinds, spotlight, glow, sparkle) and Retro FX (VHS, halftone, chroma), plus the depth map.
extension ImageProcessingService {
    // MARK: Light

    /// Slatted sunlight through window blinds: soft diagonal bars of warm light and shadow.
    func windowBlinds(_ image: CIImage, amount: Double, angle: Double, size: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        let bar = e.height * (0.02 + 0.06 * CGFloat(min(max(size, 0), 1)))
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = .white
        stripes.color1 = .black
        stripes.width = Float(bar)
        stripes.sharpness = 0.4
        let center = CGPoint(x: e.midX, y: e.midY)
        let bars = (stripes.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(angle) * .pi / 180))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            .applyingGaussianBlur(sigma: Double(bar * 0.3)) // soft shadow edges
            .cropped(to: e)
        let shade = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -2.0 * k])
        let lit = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - 900 * k, y: 0),
        ]).applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.2 * k])
        return lit.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: shade, kCIInputMaskImageKey: bars,
        ]).cropped(to: e)
    }

    /// A pool of light on the subject (or the middle); everything else falls into darkness.
    func spotlight(_ image: CIImage, amount: Double, size: Double, center: CGPoint, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        let radius = max(e.width, e.height) * (0.15 + 0.45 * CGFloat(min(max(size, 0), 1)))
        let pool = CIFilter.radialGradient()
        pool.center = center
        pool.radius0 = Float(radius * 0.55)
        pool.radius1 = Float(radius * 1.25)
        pool.color0 = .white
        pool.color1 = .black
        let dark = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -2.4 * k])
        let bright = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.2 * k])
        return bright.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: dark, kCIInputMaskImageKey: pool.outputImage?.cropped(to: e) ?? CIImage(color: .white),
        ]).cropped(to: e)
    }

    /// Orton glow: dreamy, luminous softness laid over a sharp photo (a classic landscape finish).
    func ortonGlow(_ image: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        let soft = image.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 60)).cropped(to: e)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.35])
        let screened = soft.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: screened, kCIInputTimeKey: 0.6 * k,
        ]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.12 * k]).cropped(to: e)
    }

    /// Sparkle: four-point star glints on the brightest highlights (Y2K glam, star filter).
    func sparkle(_ image: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        let points = CIFilter.toneCurve()
        points.inputImage = image
        points.point0 = .zero
        points.point1 = CGPoint(x: 0.7, y: 0)
        points.point2 = CGPoint(x: 0.85, y: 0.15)
        points.point3 = CGPoint(x: 0.95, y: 0.7)
        points.point4 = CGPoint(x: 1, y: 1)
        let highlights = (points.outputImage ?? image).clampedToExtent()
        let length = e.width / 30 * (0.5 + k)
        var glints = CIImage(color: .black).cropped(to: e)
        let arms: [(CGFloat, CGFloat)] = [(0, 1), (.pi / 2, 1), (.pi / 4, 0.45), (3 * .pi / 4, 0.45)]
        for (angle, scale) in arms {
            let streak = highlights.applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: length * scale, kCIInputAngleKey: angle,
            ]).cropped(to: e).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 3 * k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 3 * k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 3 * k, w: 0),
            ])
            glints = streak.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: glints]).cropped(to: e)
        }
        return glints.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
    }

    // MARK: Retro

    /// VHS tape: color bleed, scan lines, a tape color cast, a soft picture and tape noise.
    func vhs(_ image: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0, let kernel = Self.kernel("vhsLook") else { return image }
        let k = min(amount, 1)
        let soft = image.clampedToExtent().applyingGaussianBlur(sigma: Double(max(0.5, e.width / 900))).cropped(to: e)
        let smear = image.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: e.width / 90, kCIInputAngleKey: 0,
        ]).transformed(by: CGAffineTransform(translationX: e.width / 300, y: 0)).cropped(to: e)
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = .white
        stripes.color1 = CIColor(red: 0.55, green: 0.55, blue: 0.55)
        stripes.width = Float(max(1.5, e.height / 300))
        stripes.sharpness = 0.5
        let lines = (stripes.outputImage ?? CIImage(color: .white)).transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: e)
        let taped = kernel.apply(extent: e, arguments: [soft, smear, lines, Float(k)])?.cropped(to: e) ?? image
        return filmGrain(taped, amount: 0.45 * k, size: .medium, extent: e)
    }

    /// 2005 laptop webcam: soft low-resolution detail, a greenish washed-out color with blown highlights,
    /// visible color banding, speckled color noise in the shadows and dark corners. Blended by `amount`.
    func webcam(_ image: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = min(amount, 1)
        // Low resolution (about 480 px across), smoothly blown back up: mushy, soft detail.
        let s = min(0.5, 480 / max(e.width, e.height)) // at least half resolution, even on small images
        let origin = CGAffineTransform(translationX: -e.minX, y: -e.minY)
        let lowRes = image.clampedToExtent()
            .transformed(by: origin.concatenating(CGAffineTransform(scaleX: s, y: s)))
            .applyingGaussianBlur(sigma: 0.6)
            .transformed(by: CGAffineTransform(scaleX: 1 / s, y: 1 / s).concatenating(origin.inverted()))
            .cropped(to: e)
        // Webcam color: green-cyan cast, low saturation, flat contrast, auto-exposure that blows highlights.
        let graded = lowRes.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.9, y: 0.08, z: 0, w: 0),
            "inputGVector": CIVector(x: 0.04, y: 1.0, z: 0.04, w: 0),
            "inputBVector": CIVector(x: 0, y: 0.12, z: 0.8, w: 0),
            "inputBiasVector": CIVector(x: 0.006, y: 0.02, z: 0.012, w: 0),
        ]).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.72, kCIInputContrastKey: 0.9, kCIInputBrightnessKey: 0.02,
        ]).applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.25])
        // Banding: too few tones (in display values).
        let banded = graded.applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 26])
            .applyingFilter("CISRGBToneCurveToLinear")
            .cropped(to: e)
        // Colored sensor speckle, about the size of the webcam's pixels.
        var noisy = banded
        if let kernel = Self.kernel("webcamNoise") {
            let cell = max(1, 1 / s)
            let cells = CGRect(x: 0, y: 0, width: ceil(e.width / cell) + 2, height: ceil(e.height / cell) + 2)
            let noise = (CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray))
                .cropped(to: cells)
                .settingAlphaOne(in: cells) // the generator's alpha is random too
                .samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: cell, y: cell).concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
                .cropped(to: e)
            noisy = kernel.apply(extent: e, arguments: [banded, noise, Float(k)])?.cropped(to: e) ?? banded
        }
        let finished = vignette(noisy, amount: 0.4, extent: e)
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: finished, kCIInputTimeKey: k,
        ]).cropped(to: e)
    }

    /// Halftone print. `balance` -1 shows more black ink, +1 more white paper; `dot` sets the dot size.
    /// Color uses CMYK dots, otherwise black dots on white. `amount` blends with the photo.
    func halftone(_ image: CIImage, amount: Double, dot: Double, balance: Double, color: Bool, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let size = max(3, max(e.width, e.height) * (0.004 + 0.022 * CGFloat(min(max(dot, 0), 1))))
        let shifted = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.6 * min(max(balance, -1), 1)])
        let center = CIVector(x: e.minX, y: e.minY)
        let printed: CIImage
        if color {
            printed = shifted.applyingFilter("CICMYKHalftone", parameters: [
                kCIInputCenterKey: center, kCIInputWidthKey: size, kCIInputAngleKey: 0.0,
                kCIInputSharpnessKey: 0.7, "inputGCR": 1.0, "inputUCR": 0.5,
            ])
        } else {
            printed = shifted.applyingFilter("CIDotScreen", parameters: [
                kCIInputCenterKey: center, kCIInputWidthKey: size, kCIInputAngleKey: CGFloat.pi / 4, kCIInputSharpnessKey: 0.7,
            ])
        }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: printed.cropped(to: e), kCIInputTimeKey: min(amount, 1),
        ]).cropped(to: e)
    }

    /// Chroma: red and blue drift apart toward the edges, like a cheap lens or a 2000s digicam.
    func chroma(_ image: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0, let kernel = Self.kernel("combineChannels") else { return image }
        let k = CGFloat(min(amount, 1))
        let center = CGPoint(x: e.midX, y: e.midY)
        func scaled(_ s: CGFloat) -> CIImage {
            image.clampedToExtent().transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))).cropped(to: e)
        }
        let spread = 0.012 * k
        return kernel.apply(extent: e, arguments: [scaled(1 + spread), image, scaled(1 - spread)])?.cropped(to: e) ?? image
    }

    // MARK: Depth map

    /// Estimated depth (near = bright): the subject is nearest, the ground near the bottom, the far scene at
    /// the top, with a little brightness detail. Gray or heat colors, blended by `amount`. Not measured depth.
    func depthMap(_ image: CIImage, mask: CIImage?, amount: Double, heat: Bool, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let scene = CIFilter.linearGradient()
        scene.point0 = CGPoint(x: e.midX, y: e.minY)
        scene.point1 = CGPoint(x: e.midX, y: e.maxY)
        scene.color0 = CIColor(red: 0.55, green: 0.55, blue: 0.55)
        scene.color1 = CIColor(red: 0.04, green: 0.04, blue: 0.04)
        let gray = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 120)).cropped(to: e)
        var depth = (scene.outputImage ?? CIImage(color: .black)).cropped(to: e)
            .applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: gray, kCIInputTimeKey: 0.25])
            .cropped(to: e)
        if let mask {
            let near = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95)).cropped(to: e)
            let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 200)).cropped(to: e)
            depth = near.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: depth, kCIInputMaskImageKey: soft,
            ]).cropped(to: e)
        }
        if heat, let kernel = Self.kernel("visionLook") {
            depth = kernel.apply(extent: e, arguments: [depth, Float(0), Float(1)])?.cropped(to: e) ?? depth
        }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: depth, kCIInputTimeKey: min(amount, 1),
        ]).cropped(to: e)
    }
}
