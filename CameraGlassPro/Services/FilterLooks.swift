import CoreImage
import CoreImage.CIFilterBuiltins

/// Filter groups shown as tabs in the filter picker.
enum FilterCategory: String, CaseIterable, Identifiable {
    case classic, film, creative, cinematic, portrait, nature, seasons, travel, blackWhite, vintage, moody, food, y2k, quality, digicam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .film: "Film"
        case .creative: "Creative"
        case .seasons: "Seasons"
        case .travel: "Travel"
        case .cinematic: "Cinematic"
        case .portrait: "Portrait"
        case .nature: "Nature"
        case .blackWhite: "B&W"
        case .vintage: "Vintage"
        case .moody: "Moody"
        case .food: "Food"
        case .y2k: "Y2K"
        case .quality: "Quality"
        case .digicam: "DigiCam FX"
        }
    }

    var filters: [PhotoFilter] { PhotoFilter.allCases.filter { $0.category == self && $0 != .none } }
}

extension PhotoFilter {
    var category: FilterCategory {
        switch self {
        case .none, .vivid, .mono, .noir, .chrome, .fade, .instant: .classic
        case .y2kGlow, .flashPop, .cyber, .pastel: .y2k
        case .hd, .clarity, .hdr, .crisp: .quality
        case .digicam, .ccd, .retro: .digicam
        case .portra, .ektar, .gold, .fuji400h, .cinestill, .trix: .film
        default: LookRecipe.recipe(self)?.category ?? .classic
        }
    }
}

/// The looks behind every `PhotoFilter`.
///
/// Rules every look follows (so they stay photographic on portraits, landscapes, indoor and night shots):
/// - Tone is shaped with curves (soft shoulder, gently lifted toe) instead of raw contrast, so
///   highlights roll off and shadows keep detail instead of clipping or crushing.
/// - Color casts are split-toned: they tint shadows or highlights lightly and leave midtones (skin) alone.
/// - No look adds grain, text, borders or frames. Grain is the separate Grain control.
/// - Every radius scales with the image, so the preview matches the full-resolution export.
extension ImageProcessingService {
    func applyLook(_ look: PhotoFilter, to image: CIImage, extent: CGRect) -> CIImage {
        if let recipe = LookRecipe.recipe(look) { return recipeLook(recipe, to: image, extent: extent) }
        let w = extent.width
        switch look {
        case .none:
            return image

        // MARK: Classic (Apple's photo effects, plus a restrained Vivid)
        case .vivid:
            return curve(vibrance(image, 0.35), [(0, 0), (0.25, 0.23), (0.5, 0.5), (0.75, 0.78), (1, 1)])
        case .mono: return builtIn(CIFilter.photoEffectMono(), image)
        case .noir: return builtIn(CIFilter.photoEffectNoir(), image)
        case .chrome: return builtIn(CIFilter.photoEffectChrome(), image)
        case .fade: return builtIn(CIFilter.photoEffectFade(), image)
        case .instant: return builtIn(CIFilter.photoEffectInstant(), image)

        // MARK: Film stocks (color and tone only; picking one also sets its grain, see `filmTexture`)
        case .portra:
            // Kodak Portra 400: warm, soft contrast, gentle saturation, flattering skin.
            let soft = curve(temperature(image, shift: 250), [(0, 0.025), (0.25, 0.26), (0.5, 0.52), (0.75, 0.77), (1, 0.98)])
            return splitTone(saturation(soft, 0.9), shadows: (-0.004, 0.002, 0.008), highlights: (0.014, 0.007, 0), amount: 1)
        case .ektar:
            // Kodak Ektar 100: punchy color, deep blues and reds, firm contrast.
            let punchy = curve(vibrance(image, 0.45), [(0, 0), (0.25, 0.21), (0.5, 0.5), (0.75, 0.8), (1, 1)])
            return splitTone(saturation(punchy, 1.12), shadows: (-0.004, 0, 0.012), highlights: (0.006, 0.002, 0), amount: 1)
        case .gold:
            // Kodak Gold 200: golden warmth, yellow highlights, everyday snapshot contrast.
            let warm = curve(temperature(image, shift: 450), [(0, 0.02), (0.25, 0.24), (0.5, 0.52), (0.75, 0.79), (1, 0.98)])
            return splitTone(saturation(warm, 1.06), shadows: (0.004, 0.002, -0.004), highlights: (0.016, 0.012, -0.01), amount: 1)
        case .fuji400h:
            // Fuji Pro 400H: airy pastels, cyan-green shadows, soft highlights.
            let airy = curve(image, [(0, 0.05), (0.25, 0.29), (0.5, 0.54), (0.75, 0.78), (1, 0.97)])
            return splitTone(saturation(airy, 0.88), shadows: (-0.008, 0.01, 0.008), highlights: (0.006, 0.002, 0.006), amount: 1)
        case .cinestill:
            // CineStill 800T: tungsten-balanced, so cool overall, teal shadows, warm practical lights.
            let cool = curve(temperature(image, shift: -650), [(0, 0.03), (0.25, 0.25), (0.5, 0.51), (0.75, 0.79), (1, 0.98)])
            return splitTone(saturation(cool, 1.04), shadows: (-0.012, 0.006, 0.018), highlights: (0.014, 0.004, -0.006), amount: 1)
        case .trix:
            // Kodak Tri-X 400: black and white with rich blacks and bright, punchy midtones.
            return curve(saturation(image, 0), [(0, 0.02), (0.25, 0.2), (0.5, 0.5), (0.75, 0.82), (1, 1)])

        // MARK: Y2K
        case .y2kGlow:
            // Soft diffusion like a Pro-Mist filter: a faint, tight glow from the highlights only,
            // slightly lifted blacks and cool shadows. No wide halos.
            let glow = softGlow(image, radius: w / 260, amount: 0.22)
            let toned = curve(glow, [(0, 0.03), (0.25, 0.26), (0.5, 0.52), (0.75, 0.77), (1, 0.98)])
            return splitTone(saturation(toned, 1.06), shadows: (-0.004, 0.004, 0.018), highlights: (0.012, 0.006, 0), amount: 1)
        case .flashPop:
            // On-camera flash: brighter subject, firm but not clipped contrast, gentle edge falloff.
            let lit = exposure(image, 0.18)
            let snappy = curve(lit, [(0, 0), (0.25, 0.21), (0.5, 0.52), (0.75, 0.81), (1, 0.98)])
            return vignette(saturation(snappy, 1.05), intensity: 0.45, radius: 1.8)
        case .cyber:
            // Night-city grade: teal-leaning shadows, faint magenta highlights, deep but not crushed blacks.
            let toned = curve(image, [(0, 0.015), (0.25, 0.22), (0.5, 0.5), (0.75, 0.79), (1, 0.98)])
            return splitTone(saturation(toned, 1.08), shadows: (-0.012, 0.006, 0.02), highlights: (0.016, -0.004, 0.012), amount: 1)
        case .pastel:
            // Airy and soft: lifted blacks, gentle contrast, slightly muted color, warm highlights.
            let airy = curve(image, [(0, 0.07), (0.25, 0.3), (0.5, 0.54), (0.75, 0.78), (1, 0.97)])
            return splitTone(saturation(airy, 0.86), shadows: (0.006, 0, 0.012), highlights: (0.012, 0.006, 0), amount: 1)

        // MARK: Quality
        case .hd:
            // Fine detail and a touch of vibrance; sharpening radius tracks resolution (no halos).
            let sharp = sharpen(image, amount: 0.4, radius: max(1, w / 1600))
            return vibrance(curve(sharp, [(0, 0), (0.25, 0.24), (0.5, 0.5), (0.75, 0.76), (1, 1)]), 0.15)
        case .clarity:
            // Local contrast (wide, low-strength unsharp mask) with highlight recovery.
            let local = unsharp(image, radius: w / 90, intensity: 0.3)
            return highlightShadow(local, highlights: 0.85, shadows: 0.15)
        case .hdr:
            // Natural HDR: recover highlights, open shadows, a little local contrast. Not grungy.
            let opened = highlightShadow(image, highlights: 0.65, shadows: 0.4)
            return vibrance(unsharp(opened, radius: w / 70, intensity: 0.22), 0.18)
        case .crisp:
            let clean = noiseReduce(image, level: 0.01, sharpness: 0.5)
            return curve(sharpen(clean, amount: 0.45, radius: max(1, w / 1800)),
                         [(0, 0), (0.25, 0.235), (0.5, 0.5), (0.75, 0.77), (1, 1)])

        // MARK: DigiCam FX (2000s compact digital cameras)
        case .digicam:
            // Cool auto white balance, punchy CCD color, a firm shoulder that keeps highlights,
            // a faint highlight bloom and light crisp sharpening.
            let cool = temperature(image, shift: -350)
            let toned = curve(cool, [(0, 0.01), (0.25, 0.23), (0.5, 0.52), (0.75, 0.8), (1, 0.97)])
            let bloomed = softGlow(saturation(toned, 1.1), radius: w / 320, amount: 0.15)
            return sharpen(bloomed, amount: 0.3, radius: max(1, w / 1600))
        case .ccd:
            // Old CCD sensor color: slightly warm-green midtones, creamy highlights, soft faded blacks.
            let faded = curve(image, [(0, 0.04), (0.25, 0.27), (0.5, 0.52), (0.75, 0.77), (1, 0.96)])
            return splitTone(saturation(faded, 1.04), shadows: (0, 0.008, -0.004), highlights: (0.014, 0.012, -0.006), amount: 1)
        case .retro:
            // Early-2000s snapshot: compressed dynamic range, warm-magenta cast in highlights, mild falloff.
            let flat = curve(image, [(0, 0.05), (0.25, 0.28), (0.5, 0.52), (0.75, 0.76), (1, 0.94)])
            let toned = splitTone(saturation(flat, 0.94), shadows: (0.004, 0, 0.01), highlights: (0.016, 0.004, 0.006), amount: 1)
            return vignette(toned, intensity: 0.3, radius: 2)

        default: // recipe looks return above
            return image
        }
    }

    /// Renders a `LookRecipe`: white balance, optional black and white, tone curve, color, split toning,
    /// then optional bloom and local contrast. Same building blocks and rules as the hand-built looks.
    func recipeLook(_ r: LookRecipe, to image: CIImage, extent: CGRect) -> CIImage {
        var x = image
        if r.exposure != 0 { x = exposure(x, r.exposure) }
        if r.temperature != 0 { x = temperature(x, shift: r.temperature) }
        if let m = r.mix, m.count == 3 {
            x = x.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: m[0].0, y: m[0].1, z: m[0].2, w: 0),
                "inputGVector": CIVector(x: m[1].0, y: m[1].1, z: m[1].2, w: 0),
                "inputBVector": CIVector(x: m[2].0, y: m[2].1, z: m[2].2, w: 0),
            ])
        }
        if let w = r.mono {
            let weights = CIVector(x: w.0, y: w.1, z: w.2, w: 0)
            x = x.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": weights, "inputGVector": weights, "inputBVector": weights,
            ])
        }
        x = curve(x, r.curve)
        if let levels = r.posterize, let tones = r.duotone {
            // A few flat tones mapped from the dark color to the light one, in display values.
            let (dark, light) = tones
            x = x.applyingFilter("CILinearToSRGBToneCurve")
                .applyingFilter("CIColorPosterize", parameters: ["inputLevels": levels])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: light.0 - dark.0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: light.1 - dark.1, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: light.2 - dark.2, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: dark.0, y: dark.1, z: dark.2, w: 0),
                ])
                .applyingFilter("CISRGBToneCurveToLinear")
        }
        x = saturation(x, r.saturation)
        if r.vibrance != 0 { x = vibrance(x, r.vibrance) }
        if r.shadows != (0, 0, 0) || r.highlights != (0, 0, 0), let kernel = Self.kernel("lookSplitTone"),
           let toned = kernel.apply(extent: x.extent.isInfinite ? extent : x.extent, arguments: [
               x, CIVector(x: r.shadows.0, y: r.shadows.1, z: r.shadows.2),
               CIVector(x: r.highlights.0, y: r.highlights.1, z: r.highlights.2),
           ]) {
            x = toned
        }
        if r.glow > 0 { x = softGlow(x.cropped(to: extent), radius: extent.width / 260, amount: r.glow) }
        if r.clarity > 0 { x = unsharp(x, radius: extent.width / 90, intensity: r.clarity) }
        return x
    }

    // MARK: Building blocks

    private func builtIn(_ filter: CIFilter, _ image: CIImage) -> CIImage {
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    /// Five-point tone curve on all channels (x, y in 0...1).
    private func curve(_ image: CIImage, _ points: [(CGFloat, CGFloat)]) -> CIImage {
        guard points.count == 5 else { return image }
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = CGPoint(x: points[0].0, y: points[0].1)
        f.point1 = CGPoint(x: points[1].0, y: points[1].1)
        f.point2 = CGPoint(x: points[2].0, y: points[2].1)
        f.point3 = CGPoint(x: points[3].0, y: points[3].1)
        f.point4 = CGPoint(x: points[4].0, y: points[4].1)
        return f.outputImage ?? image
    }

    private func saturation(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 1 else { return image }
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = Float(value)
        return f.outputImage ?? image
    }

    private func exposure(_ image: CIImage, _ ev: Double) -> CIImage {
        let f = CIFilter.exposureAdjust()
        f.inputImage = image
        f.ev = Float(ev)
        return f.outputImage ?? image
    }

    private func vibrance(_ image: CIImage, _ amount: Double) -> CIImage {
        let f = CIFilter.vibrance()
        f.inputImage = image
        f.amount = Float(amount)
        return f.outputImage ?? image
    }

    /// Glow from the highlights only, mixed in lightly: diffusion without halos around edges.
    private func softGlow(_ image: CIImage, radius: CGFloat, amount: Double) -> CIImage {
        let extent = image.extent
        // Keep only the bright parts (luminance above ~70%), then blur them.
        let highlights = curve(image, [(0, 0), (0.6, 0), (0.75, 0.15), (0.9, 0.6), (1, 1)])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(1, radius)))
            .cropped(to: extent)
        let scaled = highlights.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
        ])
        // Screen blend never pushes past white, so highlights don't clip.
        return scaled.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    private func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        let f = CIFilter.vignette()
        f.inputImage = image
        f.intensity = Float(intensity)
        f.radius = Float(radius)
        return f.outputImage ?? image
    }

    /// Tints shadows and highlights separately, weighted by luminance, so midtones (skin) stay neutral.
    private func splitTone(_ image: CIImage, shadows: (CGFloat, CGFloat, CGFloat),
                           highlights: (CGFloat, CGFloat, CGFloat), amount: CGFloat) -> CIImage {
        let extent = image.extent
        func tinted(_ bias: (CGFloat, CGFloat, CGFloat)) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: bias.0 * amount, y: bias.1 * amount, z: bias.2 * amount, w: 0),
            ])
        }
        // Luminance mask: white in highlights, black in shadows.
        let luminance = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
        ])
        let blend = CIFilter.blendWithMask()
        blend.inputImage = tinted(highlights)
        blend.backgroundImage = tinted(shadows)
        blend.maskImage = luminance
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    private func sharpen(_ image: CIImage, amount: Double, radius: CGFloat) -> CIImage {
        let f = CIFilter.sharpenLuminance()
        f.inputImage = image
        f.sharpness = Float(amount)
        f.radius = Float(radius)
        return f.outputImage ?? image
    }

    private func unsharp(_ image: CIImage, radius: CGFloat, intensity: Double) -> CIImage {
        let f = CIFilter.unsharpMask()
        f.inputImage = image
        f.radius = Float(max(1, radius))
        f.intensity = Float(intensity)
        return f.outputImage ?? image
    }

    private func highlightShadow(_ image: CIImage, highlights: Double, shadows: Double) -> CIImage {
        let f = CIFilter.highlightShadowAdjust()
        f.inputImage = image
        f.highlightAmount = Float(highlights)
        f.shadowAmount = Float(shadows)
        return f.outputImage ?? image
    }

    private func noiseReduce(_ image: CIImage, level: Double, sharpness: Double) -> CIImage {
        let f = CIFilter.noiseReduction()
        f.inputImage = image
        f.noiseLevel = Float(level)
        f.sharpness = Float(sharpness)
        return f.outputImage ?? image
    }

    private func temperature(_ image: CIImage, shift: CGFloat) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        f.neutral = CIVector(x: 6500, y: 0)
        f.targetNeutral = CIVector(x: 6500 - shift, y: 0)
        return f.outputImage ?? image
    }
}
