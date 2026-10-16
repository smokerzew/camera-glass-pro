import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Core Image pipeline shared by the live preview and the full-resolution export.
final class ImageProcessingService: @unchecked Sendable {
    static let shared = ImageProcessingService()

    // CIContext is thread-safe; one instance avoids rebuilding GPU state per render.
    let context = CIContext(options: [.cacheIntermediates: false])

    func apply(_ adjustments: PhotoAdjustmentState, to input: CIImage) -> CIImage {
        let a = adjustments.clamped()
        guard !a.isIdentity else { return input }
        var image = input

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

        image = applyLook(a.filter, to: image, extent: input.extent)

        if a.grain > 0 {
            image = addGrain(amount: a.grain, to: image, extent: input.extent)
        }

        // Some filters sample beyond the edges; keep the original bounds.
        return image.cropped(to: input.extent)
    }

    /// Monochrome noise centered on zero, added on top; scaled so grain looks similar at any resolution.
    private func addGrain(amount: Double, to image: CIImage, extent: CGRect) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let scale = max(1, extent.width / 1500)
        let strength = CGFloat(amount * 0.18)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        mono.rVector = CIVector(x: strength, y: 0, z: 0, w: 0)
        mono.gVector = CIVector(x: strength, y: 0, z: 0, w: 0)
        mono.bVector = CIVector(x: strength, y: 0, z: 0, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: -strength / 2, y: -strength / 2, z: -strength / 2, w: 1)
        guard let grain = mono.outputImage?.cropped(to: extent) else { return image }
        let add = CIFilter.additionCompositing()
        add.inputImage = grain
        add.backgroundImage = image
        return add.outputImage ?? image
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

    func renderPreview(_ source: CGImage, adjustments: PhotoAdjustmentState) -> CGImage? {
        let input = CIImage(cgImage: source)
        return context.createCGImage(apply(adjustments, to: input), from: input.extent)
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
