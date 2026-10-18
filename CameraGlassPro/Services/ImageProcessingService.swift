import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Core Image pipeline shared by the live preview and the full-resolution export.
final class ImageProcessingService: @unchecked Sendable {
    static let shared = ImageProcessingService()

    // CIContext is thread-safe; one instance avoids rebuilding GPU state per render.
    let context = CIContext(options: [.cacheIntermediates: false])
    private let mixerLock = NSLock()
    private var mixerCache: (mixer: ColorMixer, data: Data)?

    /// `subjectMask` lets callers reuse a precomputed Portrait mask (the photo preview);
    /// without one, Portrait finds the subject itself (exports, video frames).
    func apply(_ adjustments: PhotoAdjustmentState, to input: CIImage, subjectMask: CIImage? = nil,
               fastMask: Bool = false, backgroundPhoto: CIImage? = nil) -> CIImage {
        let a = adjustments.clamped()
        guard !a.isIdentity else { return input }
        var image = input

        let mask = a.needsSubject ? (subjectMask ?? SubjectMasker.mask(for: input, fast: fastMask)) : nil
        if let mask {
            image = composeSubject(a, to: image, mask: mask, backgroundPhoto: backgroundPhoto)
            if a.dispersion > 0 {
                image = dispersion(image, mask: mask.cropped(to: input.extent), amount: a.dispersion,
                                   size: a.dispersionSize, extent: input.extent)
            }
        }
        if a.doubleExposure > 0, let second = backgroundPhoto {
            image = doubleExposure(image, second: second, mask: mask, amount: a.doubleExposure, extent: input.extent)
        }

        // Sky found on the untouched photo, so edits never change what counts as sky.
        let sky = a.skyEdit.isNeutral ? nil : skyMask(for: input, extent: input.extent)

        if a.noiseReduction > 0 {
            image = reduceNoise(image, amount: a.noiseReduction, extent: input.extent)
        }

        if a.skinSmoothing > 0 {
            image = smoothSkin(image, amount: a.skinSmoothing, extent: input.extent)
        }

        if a.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(a.exposure)
            image = filter.outputImage ?? image
        }

        if a.brightness != 0 || a.contrast != 1 || a.saturation != 1 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.brightness = Float(a.brightness)
            filter.contrast = Float(a.contrast)
            filter.saturation = Float(a.saturation)
            image = filter.outputImage ?? image
        }

        if a.warmth != 0 {
            // A target neutral below the source neutral renders warmer; above renders cooler
            // (sign verified by ImageProcessingTests.testWarmthDirection on CI).
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 - a.warmth * 2500, y: 0)
            image = filter.outputImage ?? image
        }

        let shadowAmount = min(1, a.shadows + (a.nightLook ? 0.5 : 0))
        if a.highlights != 0 || shadowAmount != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.highlightAmount = Float(1 + a.highlights)
            filter.shadowAmount = Float(shadowAmount)
            image = filter.outputImage ?? image
        }

        if a.nightLook {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = image
            filter.noiseLevel = 0.02
            filter.sharpness = 0.4
            image = filter.outputImage ?? image
        }

        if a.texture != 0 {
            // Unsharp mask with a size-relative radius: positive adds local contrast, negative softens.
            let filter = CIFilter.unsharpMask()
            filter.inputImage = image
            filter.radius = Float(max(2, input.extent.width / 300))
            filter.intensity = Float(a.texture * 0.8)
            image = filter.outputImage ?? image
        }

        if let sky {
            image = applySkyEdit(a.skyEdit, to: image, mask: sky, extent: input.extent)
        }

        if !a.colorMixer.isNeutral {
            image = applyColorMixer(a.colorMixer, to: image)
        }

        image = applyStyle(a, to: image)
        let unfiltered = image
        image = applyLook(a.filter, to: image, extent: input.extent)
        if a.halation > 0 {
            image = halation(image, amount: a.halation, extent: input.extent)
        }
        if a.filter != .none, a.filterStrength < 1 {
            image = unfiltered.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: image, kCIInputTimeKey: max(0, a.filterStrength),
            ])
        }

        // Some filters sample beyond the edges; keep the original bounds, then crop/rotate/straighten.
        image = applyGeometry(a, to: image.cropped(to: input.extent))
        let extent = image.extent

        if a.sharpen > 0 {
            image = sharpen(image, amount: a.sharpen, extent: extent)
        }
        if a.tiltShift > 0 {
            image = tiltShift(image, amount: a.tiltShift, position: a.tiltShiftPosition, extent: extent)
        }
        for local in a.localAdjustments where !local.edit.isNeutral {
            image = applyLocal(local, to: image, extent: extent)
        }
        if a.vignette != 0 {
            image = vignette(image, amount: a.vignette, extent: extent)
        }
        // Privacy last (before grain), so nothing after it can reveal what was hidden.
        image = redact(image, faces: a.faceRedaction, strokes: a.redactionStrokes, strength: a.redactionStrength, extent: extent)
        if a.grain > 0 {
            image = filmGrain(image, amount: a.grain, size: a.grainSize, extent: extent)
        }
        return image.cropped(to: extent)
    }

    /// Average sRGB luminance (0...1) of a square around `point` (normalized, top-left origin).
    func averageLuma(of image: CGImage, around point: CGPoint, radius: CGFloat) -> Double? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let side = min(extent.width, extent.height) * radius * 2
        let region = CGRect(x: extent.minX + point.x * extent.width - side / 2,
                            y: extent.minY + (1 - point.y) * extent.height - side / 2, // CI is bottom-left
                            width: side, height: side).intersection(extent)
        guard !region.isEmpty,
              let average = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: region),
              ])?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    /// Photographic Style: undertone + Tone (contrast/shadow depth) + Color (saturation), scaled by Palette.
    func applyStyle(_ a: PhotoAdjustmentState, to image: CIImage) -> CIImage {
        let style = a.style
        let palette = min(max(a.stylePalette, 0), 1)
        let tone = min(max(a.styleTone + style.character.tone * palette, -1), 1)
        let color = min(max(a.styleColor + style.character.color * palette, -1), 1)
        guard style != .standard || tone != 0 || color != 0 else { return image }

        var output = image
        if tone != 0 {
            // Up: richer contrast and deeper shadows. Down: brighter, flatter shadows.
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.contrast = Float(1 + tone * 0.22)
            controls.brightness = Float(-tone * 0.025)
            output = controls.outputImage ?? output
            let shadows = CIFilter.highlightShadowAdjust()
            shadows.inputImage = output
            shadows.shadowAmount = Float(-tone * 0.35)
            shadows.highlightAmount = 1
            output = shadows.outputImage ?? output
        }
        let saturation = style.isMonochrome ? 0 : 1 + color * 0.55
        if saturation != 1 {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.saturation = Float(max(0, saturation))
            if style.isMonochrome { controls.contrast = Float(style == .starkBW ? 1.15 : 0.92) }
            output = controls.outputImage ?? output
        }
        let tint = style.undertone
        if !style.isMonochrome, (tint.r, tint.g, tint.b) != (0.0, 0.0, 0.0), palette > 0 {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = output
            matrix.biasVector = CIVector(x: tint.r * palette, y: tint.g * palette, z: tint.b * palette, w: 0)
            output = matrix.outputImage ?? output
        }
        return output
    }

    /// Film grain, independent of filters. Monochrome, soft-edged grains added equally to R, G and B
    /// in display (sRGB) space, so they never tint colors. Strength follows luminance like film:
    /// strongest in midtones, lighter in shadows, gone in bright highlights. Two grain sizes scaled
    /// to the image, so preview and export match. `amount` 0 returns the image untouched.
    func filmGrain(_ image: CIImage, amount: Double, size: GrainSize = .medium, extent: CGRect) -> CIImage {
        guard amount > 0, let random = CIFilter.randomGenerator().outputImage,
              let kernel = Self.grainKernel else { return image }
        let cell = max(1, extent.width / size.cellDivisor)
        func octave(_ scale: CGFloat, offset: CGFloat) -> CIImage {
            random.transformed(by: CGAffineTransform(translationX: offset, y: offset * 0.6))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .applyingGaussianBlur(sigma: Double(0.55 * scale))
                .cropped(to: extent)
        }
        let display = image.applyingFilter("CILinearToSRGBToneCurve")
        let strength = Float(min(amount, 1) * 14 / 255) // 1 ≈ 12/255 grain spread in midtones
        guard let grained = kernel.apply(extent: extent,
                                         arguments: [display, octave(cell, offset: 0), octave(cell * 2.2, offset: 517), strength])
        else { return image }
        return grained.applyingFilter("CISRGBToneCurveToLinear").cropped(to: extent)
    }

    /// Film halation: light from bright areas scatters back through the film base and glows
    /// red-orange around them (CineStill-style). Only highlights feed the glow; dark areas are untouched.
    func halation(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        guard let kernels = Self.halationKernels,
              let source = kernels.source.apply(extent: image.extent.isInfinite ? extent : image.extent, arguments: [image])
        else { return image }
        let wide = source.clampedToExtent().applyingGaussianBlur(sigma: Double(extent.width / 70)).cropped(to: extent)
        let tight = source.clampedToExtent().applyingGaussianBlur(sigma: Double(extent.width / 300)).cropped(to: extent)
        // Added in the kernel: Core Image's addition blend also adds alpha, which brightened whole images.
        return kernels.add.apply(extent: extent, arguments: [image, wide, tight, Float(0.9 * k)])?.cropped(to: extent) ?? image
    }

    /// One graduated or radial filter: the region edit, blended in through its soft mask.
    func applyLocal(_ local: LocalAdjustment, to image: CIImage, extent e: CGRect) -> CIImage {
        let l = local.clamped
        let mask: CIImage?
        switch l.shape {
        case .graduated:
            // Full effect from the edge to `reach * (1 - softness)`, fading to nothing at `reach`.
            let horizontal = l.edge == .left || l.edge == .right
            let span = horizontal ? e.width : e.height
            let reach = CGFloat(l.position) * span
            let full = max(0, reach * CGFloat(1 - l.softness))
            let fade = max(full + 1, reach)
            let (from, to): (CGPoint, CGPoint)
            switch l.edge {
            case .top: (from, to) = (CGPoint(x: e.midX, y: e.maxY - full), CGPoint(x: e.midX, y: e.maxY - fade))
            case .bottom: (from, to) = (CGPoint(x: e.midX, y: e.minY + full), CGPoint(x: e.midX, y: e.minY + fade))
            case .left: (from, to) = (CGPoint(x: e.minX + full, y: e.midY), CGPoint(x: e.minX + fade, y: e.midY))
            case .right: (from, to) = (CGPoint(x: e.maxX - full, y: e.midY), CGPoint(x: e.maxX - fade, y: e.midY))
            }
            let gradient = CIFilter.linearGradient()
            gradient.point0 = from
            gradient.point1 = to
            gradient.color0 = .white
            gradient.color1 = .black
            mask = gradient.outputImage
        case .radial:
            let outer = CGFloat(l.size) * hypot(e.width, e.height) / 2
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: e.minX + CGFloat(l.centerX) * e.width, y: e.maxY - CGFloat(l.centerY) * e.height)
            gradient.radius0 = Float(outer * CGFloat(1 - l.softness))
            gradient.radius1 = Float(max(outer, 1))
            gradient.color0 = l.inverted ? .black : .white
            gradient.color1 = l.inverted ? .white : .black
            mask = gradient.outputImage
        }
        guard let mask else { return image }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = regionEdit(l.edit, to: image)
        blend.backgroundImage = image
        blend.maskImage = mask.cropped(to: e)
        return (blend.outputImage ?? image).cropped(to: e)
    }

    /// Darkens (+) or lightens (−) toward the corners with a soft radial falloff, framed on the
    /// final (cropped) picture. In exposure stops, so colors keep their hue.
    func vignette(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount != 0 else { return image }
        let half = hypot(extent.width, extent.height) / 2
        let mask = CIFilter.radialGradient()
        mask.center = CGPoint(x: extent.midX, y: extent.midY)
        mask.radius0 = Float(half * 0.3)
        mask.radius1 = Float(half * 1.05)
        mask.color0 = CIColor.white
        mask.color1 = CIColor.black
        let edge = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.8 * min(max(amount, -1), 1)])
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: edge, kCIInputMaskImageKey: mask.outputImage ?? CIImage.empty(),
        ]).cropped(to: extent)
    }

    /// Color Mixer through a 3D lookup table in sRGB (rebuilt only when the mixer changes).
    func applyColorMixer(_ mixer: ColorMixer, to image: CIImage) -> CIImage {
        mixerLock.lock()
        if mixerCache?.mixer != mixer { mixerCache = (mixer, mixer.cubeData()) }
        let data = mixerCache?.data ?? Data()
        mixerLock.unlock()
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(ColorMixer.cubeSize)
        filter.cubeData = data
        filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        return filter.outputImage ?? image
    }

    /// Kernels from Kernels.metal, compiled into the app's default.metallib at build time.
    static func kernel(_ name: String) -> CIColorKernel? {
        guard let url = Bundle(for: ImageProcessingService.self).url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: name, fromMetalLibraryData: data)
    }

    static let grainKernel = kernel("filmGrain")

    static let halationKernels: (source: CIColorKernel, add: CIColorKernel)? = {
        guard let source = kernel("halationSource"), let add = kernel("halationAdd") else { return nil }
        return (source, add)
    }()

    /// One-tap Auto: picks exposure, contrast, highlights, shadows, saturation and warmth from the
    /// photo's own histogram and color cast. Returns `current` with only those values replaced.
    func autoEnhanced(_ current: PhotoAdjustmentState, for image: CGImage) -> PhotoAdjustmentState {
        let side = 96
        let input = CIImage(cgImage: image)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / input.extent.width,
                                                             y: CGFloat(side) / input.extent.height))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(scaled, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Self.autoEnhanced(current, rgba: pixels)
    }

    /// Pure analysis behind Auto, on sRGB RGBA8 pixels (testable without rendering).
    static func autoEnhanced(_ current: PhotoAdjustmentState, rgba: [UInt8]) -> PhotoAdjustmentState {
        var lumas: [Double] = []
        var chroma = 0.0, cast = 0.0, castCount = 0.0
        for i in stride(from: 0, to: rgba.count - 3, by: 4) {
            let r = Double(rgba[i]) / 255, g = Double(rgba[i + 1]) / 255, b = Double(rgba[i + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            lumas.append(y)
            chroma += max(r, g, b) - min(r, g, b)
            if y > 0.2, y < 0.85 { cast += b - r; castCount += 1 }
        }
        guard !lumas.isEmpty else { return current }
        lumas.sort()
        let count = Double(lumas.count)
        let mean = lumas.reduce(0, +) / count
        let low = lumas[Int(count * 0.01)], high = lumas[Int(count * 0.99)]
        let clipped = Double(lumas.filter { $0 > 0.97 }.count) / count
        let dark = Double(lumas.filter { $0 < 0.08 }.count) / count
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func rounded(_ v: Double) -> Double { (v * 100).rounded() / 100 }

        var next = current
        // Half-way towards a 0.45 sRGB mean; little brightening when highlights would clip.
        var ev = 0.5 * log2(linear(0.45) / max(linear(mean), 0.0005))
        if high > 0.95 { ev = min(ev, 0.3) }
        next.exposure = rounded(min(max(ev, -0.8), 1))
        next.highlights = rounded(clipped > 0.005 || ev > 0.2 ? -min(0.7, clipped * 10 + max(0, ev) * 0.3) : 0)
        next.shadows = rounded(dark > 0.05 ? min(0.5, dark * 1.5) : 0)
        let range = high - low
        next.contrast = rounded(range < 0.75 ? 1 + min(0.25, (0.75 - range) * 0.5) : 1)
        let meanChroma = chroma / count
        next.saturation = rounded(meanChroma < 0.3 ? 1 + min(0.2, (0.3 - meanChroma) * 0.8) : 1)
        let blueCast = castCount > 0 ? cast / castCount : 0
        next.warmth = rounded(abs(blueCast) > 0.03 ? min(max(blueCast * 1.5, -0.3), 0.3) : 0) // blue cast → warmer
        return next.clamped()
    }

    /// Focus peaking: transparent image with the strongest edges painted red.
    /// Display-only; never part of an export.
    func peakingOverlay(for input: CIImage) -> CIImage {
        let edges = CIFilter.edges()
        edges.inputImage = input.clampedToExtent() // the photo border is not an in-focus edge
        edges.intensity = 6
        guard let edgeImage = edges.outputImage else { return CIImage.empty() }

        // Edge strength (sum of channels) becomes alpha; RGB is a fixed red. Weak edges fall below 0.
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = edgeImage
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 1.2, y: 1.2, z: 1.2, w: 0)
        matrix.biasVector = CIVector(x: 1, y: 0.12, z: 0.1, w: -0.9)

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = matrix.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return (clamp.outputImage ?? CIImage.empty()).cropped(to: input.extent)
    }

    /// Highlight clipping ("zebras"): diagonal red stripes where luminance is near white. Display-only.
    func zebraOverlay(for input: CIImage) -> CIImage {
        // Mask alpha rises steeply above ~96% luminance.
        let mask = CIFilter.colorMatrix()
        mask.inputImage = input
        mask.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mask.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mask.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mask.aVector = CIVector(x: 0.2126 * 40, y: 0.7152 * 40, z: 0.0722 * 40, w: 0)
        mask.biasVector = CIVector(x: 1, y: 1, z: 1, w: -0.96 * 40)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = mask.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)

        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 1, green: 0.25, blue: 0.25, alpha: 0.85)
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        stripes.width = Float(max(4, input.extent.width / 120))
        stripes.sharpness = 1
        let diagonal = (stripes.outputImage ?? CIImage.empty())
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
            .cropped(to: input.extent)

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = diagonal
        blend.backgroundImage = CIImage.empty().cropped(to: input.extent)
        blend.maskImage = clamp.outputImage
        return (blend.outputImage ?? CIImage.empty()).cropped(to: input.extent)
    }

    /// Peaking and/or zebras combined into one transparent overlay.
    func analysisOverlay(for input: CIImage, peaking: Bool, zebras: Bool) -> CIImage {
        var overlay = CIImage.empty().cropped(to: input.extent)
        if zebras { overlay = zebraOverlay(for: input).composited(over: overlay) }
        if peaking { overlay = peakingOverlay(for: input).composited(over: overlay) }
        return overlay
    }

    func renderAnalysisOverlay(_ source: CGImage, peaking: Bool, zebras: Bool) -> CGImage? {
        let input = CIImage(cgImage: source)
        return context.createCGImage(analysisOverlay(for: input, peaking: peaking, zebras: zebras), from: input.extent)
    }

    func renderPreview(_ source: CGImage, adjustments: PhotoAdjustmentState, subjectMask: CIImage? = nil,
                       backgroundPhoto: CIImage? = nil) -> CGImage? {
        let input = CIImage(cgImage: source)
        let output = apply(adjustments, to: input, subjectMask: subjectMask, backgroundPhoto: backgroundPhoto)
        // The output's own size: rotation and crop change it (cutting at the input size left black bars).
        return context.createCGImage(output, from: output.extent)
    }

    func encode(_ image: CIImage, as format: ExportFormat) throws -> Data {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let quality = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92]
        let data: Data?
        switch format {
        case .jpeg:
            data = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: quality)
        case .heic:
            data = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace, options: quality)
        case .png:
            data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace, options: [:])
        }
        guard let data else { throw PhotoExportError.renderFailed }
        return data
    }
}
