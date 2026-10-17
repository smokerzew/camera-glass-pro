import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Core Image pipeline shared by the live preview and the full-resolution export.
final class ImageProcessingService: @unchecked Sendable {
    static let shared = ImageProcessingService()

    // CIContext is thread-safe; one instance avoids rebuilding GPU state per render.
    let context = CIContext(options: [.cacheIntermediates: false])

    /// `subjectMask` lets callers reuse a precomputed Portrait mask (the photo preview);
    /// without one, Portrait finds the subject itself (exports, video frames).
    func apply(_ adjustments: PhotoAdjustmentState, to input: CIImage, subjectMask: CIImage? = nil,
               fastMask: Bool = false, backgroundPhoto: CIImage? = nil) -> CIImage {
        let a = adjustments.clamped()
        guard !a.isIdentity else { return input }
        var image = input

        if a.needsSubject, let mask = subjectMask ?? SubjectMasker.mask(for: input, fast: fastMask) {
            image = composeSubject(a, to: image, mask: mask, backgroundPhoto: backgroundPhoto)
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

        image = applyStyle(a, to: image)
        image = applyLook(a.filter, to: image, extent: input.extent)

        // Some filters sample beyond the edges; keep the original bounds, then crop/rotate/straighten.
        image = applyGeometry(a, to: image.cropped(to: input.extent))
        let extent = image.extent

        if a.grain > 0 {
            image = filmGrain(image, amount: a.grain, extent: extent)
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

    /// Film grain, independent of filters. Fine, soft, monochrome grains whose visibility follows
    /// luminance like real film (strongest in midtones, fading in deep shadows and bright highlights,
    /// via a soft-light blend). Grain size scales with the image, so preview and export match.
    /// `amount` 0 returns the image untouched.
    func filmGrain(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0, let random = CIFilter.randomGenerator().outputImage else { return image }
        let size = max(1, extent.width / 2000) // ~1 px grains at 2000 px wide
        // Average the three random channels: monochrome, near-Gaussian (no harsh speckle).
        let third: CGFloat = 1.0 / 3.0
        let mono = random.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: third, y: third, z: third, w: 0),
            "inputGVector": CIVector(x: third, y: third, z: third, w: 0),
            "inputBVector": CIVector(x: third, y: third, z: third, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        // Round, soft-edged grains at the image's scale.
        let grains = mono
            .transformed(by: CGAffineTransform(scaleX: size, y: size))
            .applyingGaussianBlur(sigma: Double(0.55 * size))
            .cropped(to: extent)
        // Contrast of the grain layer around mid-gray (0.5 = no change in a soft-light blend).
        let k = CGFloat(min(max(amount, 0), 1) * 1.6)
        let layer = grains.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            "inputBiasVector": CIVector(x: 0.5 - 0.5 * k, y: 0.5 - 0.5 * k, z: 0.5 - 0.5 * k, w: 0),
        ])
        return layer.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    /// Focus peaking: transparent image with the strongest edges painted red.
    /// Display-only; never part of an export.
    func peakingOverlay(for input: CIImage) -> CIImage {
        let edges = CIFilter.edges()
        edges.inputImage = input
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
        return context.createCGImage(apply(adjustments, to: input, subjectMask: subjectMask,
                                           backgroundPhoto: backgroundPhoto), from: input.extent)
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
