import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Filter groups shown as tabs in the filter picker.
enum FilterCategory: String, CaseIterable, Identifiable {
    case classic, y2k, quality, digicam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
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
        case .digicam, .ccd, .lofi, .dateStamp: .digicam
        }
    }
}

/// The looks behind every `PhotoFilter`. All are Core Image chains, so they run the same on the
/// photo preview, the full-resolution export and every video frame.
extension ImageProcessingService {
    func applyLook(_ look: PhotoFilter, to image: CIImage, extent: CGRect) -> CIImage {
        switch look {
        case .none:
            return image

        // Classic
        case .vivid: return vibrance(image, 0.6)
        case .mono: return builtIn(CIFilter.photoEffectMono(), image)
        case .noir: return builtIn(CIFilter.photoEffectNoir(), image)
        case .chrome: return builtIn(CIFilter.photoEffectChrome(), image)
        case .fade: return builtIn(CIFilter.photoEffectFade(), image)
        case .instant: return builtIn(CIFilter.photoEffectInstant(), image)

        // Y2K
        case .y2kGlow:
            // Soft bloom, punchy color and a cool cast, like early-2000s glossy edits.
            let base = tone(image, saturation: 1.3, contrast: 1.06, brightness: 0.03)
            return tint(bloom(base, radius: extent.width / 60, intensity: 0.75), r: -0.02, g: 0, b: 0.04)
        case .flashPop:
            // Direct on-camera flash: bright subject, hard contrast, dark falloff.
            let lit = tone(exposure(image, 0.45), saturation: 1.15, contrast: 1.28, brightness: 0)
            return vignette(lit, intensity: 1.3, radius: 1.6)
        case .cyber:
            // Teal shadows, magenta highlights, glow.
            let split = channels(image, r: 1.05, g: 0.92, b: 1.12, bias: (0.02, -0.01, 0.06))
            return bloom(tone(split, saturation: 1.35, contrast: 1.15, brightness: 0), radius: extent.width / 80, intensity: 0.5)
        case .pastel:
            // Lifted, low-contrast, slightly pink.
            let soft = tone(image, saturation: 0.72, contrast: 0.82, brightness: 0.08)
            return tint(soft, r: 0.04, g: 0.0, b: 0.03)

        // Quality
        case .hd:
            let sharp = sharpen(unsharp(image, radius: extent.width / 400, intensity: 0.5), 0.6)
            return vibrance(tone(sharp, saturation: 1.0, contrast: 1.08, brightness: 0), 0.3)
        case .clarity:
            // Wide unsharp mask = local contrast; recover highlights and lift shadows.
            let local = unsharp(image, radius: extent.width / 60, intensity: 0.6)
            return highlightShadow(local, highlights: 0.75, shadows: 0.35)
        case .hdr:
            let recovered = highlightShadow(image, highlights: 0.55, shadows: 0.7)
            return vibrance(unsharp(recovered, radius: extent.width / 50, intensity: 0.45), 0.45)
        case .crisp:
            let clean = noiseReduce(image, level: 0.015, sharpness: 0.9)
            return tone(sharpen(clean, 0.8), saturation: 1.05, contrast: 1.12, brightness: 0)

        // DigiCam FX (early-2000s compact digital cameras)
        case .digicam:
            // Hot highlights with CCD bloom, cool white balance, crunchy sharpening, fine noise.
            let hot = tone(exposure(image, 0.3), saturation: 1.22, contrast: 1.12, brightness: 0)
            let cool = temperature(hot, shift: -900)
            let crunchy = sharpen(bloom(cool, radius: extent.width / 120, intensity: 0.45), 0.9)
            return grain(crunchy, amount: 0.25, extent: extent)
        case .ccd:
            // Greenish-warm CCD color, clipped highlights, noise.
            let tinted = channels(image, r: 1.04, g: 1.06, b: 0.9, bias: (0.01, 0.02, -0.01))
            let clipped = tone(exposure(tinted, 0.25), saturation: 1.12, contrast: 1.2, brightness: 0.01)
            return grain(clipped, amount: 0.35, extent: extent)
        case .lofi:
            // Low resolution, blocky upscale, saturated, noisy.
            let small = lowResolution(image, factor: max(3, extent.width / 640), extent: extent)
            return grain(tone(small, saturation: 1.25, contrast: 1.1, brightness: 0.02), amount: 0.3, extent: extent)
        case .dateStamp:
            let base = applyLook(.digicam, to: image, extent: extent)
            return dateStamp(on: base, extent: extent)
        }
    }

    // MARK: Building blocks

    private func builtIn(_ filter: CIFilter, _ image: CIImage) -> CIImage {
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private func tone(_ image: CIImage, saturation: Double, contrast: Double, brightness: Double) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = Float(saturation)
        f.contrast = Float(contrast)
        f.brightness = Float(brightness)
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

    private func bloom(_ image: CIImage, radius: CGFloat, intensity: Double) -> CIImage {
        let f = CIFilter.bloom()
        f.inputImage = image
        f.radius = Float(max(2, radius))
        f.intensity = Float(intensity)
        return f.outputImage ?? image
    }

    private func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        let f = CIFilter.vignette()
        f.inputImage = image
        f.intensity = Float(intensity)
        f.radius = Float(radius)
        return f.outputImage ?? image
    }

    private func tint(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
        channels(image, r: 1, g: 1, b: 1, bias: (r, g, b))
    }

    private func channels(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat, bias: (CGFloat, CGFloat, CGFloat)) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: bias.0, y: bias.1, z: bias.2, w: 0)
        return f.outputImage ?? image
    }

    private func sharpen(_ image: CIImage, _ amount: Double) -> CIImage {
        let f = CIFilter.sharpenLuminance()
        f.inputImage = image
        f.sharpness = Float(amount)
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

    private func grain(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
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
        guard let layer = mono.outputImage?.cropped(to: extent) else { return image }
        let add = CIFilter.additionCompositing()
        add.inputImage = layer
        add.backgroundImage = image
        return add.outputImage ?? image
    }

    /// Shrinks then enlarges with nearest-neighbor sampling for a low-megapixel, blocky look.
    private func lowResolution(_ image: CIImage, factor: CGFloat, extent: CGRect) -> CIImage {
        let down = image.cropped(to: extent)
            .transformed(by: CGAffineTransform(scaleX: 1 / factor, y: 1 / factor))
        return down.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            .cropped(to: extent)
    }

    /// Orange LCD-style date in the bottom-right corner, like a 2000s digicam print.
    /// Uses today's date as a style element; no capture metadata is read or written.
    private func dateStamp(on image: CIImage, extent: CGRect) -> CIImage {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "''yy  MM  dd"
        let fontSize = max(10, extent.height * 0.035)
        let text = NSAttributedString(string: formatter.string(from: .now), attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor(red: 1, green: 0.55, blue: 0.12, alpha: 0.95),
        ])
        let generator = CIFilter.attributedTextImageGenerator()
        generator.text = text
        generator.scaleFactor = 1
        guard let label = generator.outputImage else { return image }
        let glow = bloom(label, radius: fontSize * 0.25, intensity: 0.8)
        let margin = extent.height * 0.04
        let placed = glow.transformed(by: CGAffineTransform(
            translationX: extent.maxX - label.extent.width - margin - label.extent.minX,
            y: extent.minY + margin - label.extent.minY
        ))
        return placed.composited(over: image)
    }
}
