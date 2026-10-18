import CoreGraphics
import CoreImage
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Target values the AI picks for the editor's own controls. Plain data, so it is testable without the model.
struct AIEditValues: Equatable, Sendable {
    var exposure = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var warmth = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var vignette = 0.0
    var grain = 0.0
    var halation = 0.0
    var skinSmoothing = 0.0
    var subjectBrightness = 0.0
    var backgroundBrightness = 0.0
    var backgroundSaturation = 0.0
    /// A `PhotoFilter` raw value, or "keep" to leave the current filter.
    var look = "keep"
    var summary = ""

    /// The current edit with these values written into its sliders (all clamped to their ranges).
    func applied(to current: PhotoAdjustmentState) -> PhotoAdjustmentState {
        var next = current
        next[.exposure] = exposure
        next[.contrast] = contrast
        next[.saturation] = saturation
        next[.warmth] = warmth
        next[.highlights] = highlights
        next[.shadows] = shadows
        next[.vignette] = vignette
        next[.grain] = grain
        next[.halation] = halation
        next[.skin] = skinSmoothing
        next.subjectEdit.exposure = Self.unit(subjectBrightness)
        next.backgroundEdit.exposure = Self.unit(backgroundBrightness)
        next.backgroundEdit.saturation = Self.unit(backgroundSaturation)
        if look != "keep", let filter = PhotoFilter(rawValue: look) { next.filter = filter }
        return next
    }

    private static func unit(_ v: Double) -> Double { v.isFinite ? min(max(v, -1), 1) : 0 }

    /// The current edit as the starting point the model sees.
    init(from state: PhotoAdjustmentState) {
        exposure = state.exposure
        contrast = state.contrast
        saturation = state.saturation
        warmth = state.warmth
        highlights = state.highlights
        shadows = state.shadows
        vignette = state.vignette
        grain = state.grain
        halation = state.halation
        skinSmoothing = state.skinSmoothing
        subjectBrightness = state.subjectEdit.exposure
        backgroundBrightness = state.backgroundEdit.exposure
        backgroundSaturation = state.backgroundEdit.saturation
        look = state.filter.rawValue
    }

    init() {}

    var promptDescription: String {
        String(format: "exposure %.2f, contrast %.2f, saturation %.2f, warmth %.2f, highlights %.2f, shadows %.2f, "
               + "vignette %.2f, grain %.2f, halation %.2f, skinSmoothing %.2f, subjectBrightness %.2f, "
               + "backgroundBrightness %.2f, backgroundSaturation %.2f, look %@",
               exposure, contrast, saturation, warmth, highlights, shadows, vignette, grain, halation, skinSmoothing,
               subjectBrightness, backgroundBrightness, backgroundSaturation, look)
    }
}

enum AIEditError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message): message
        }
    }
}

/// Turns a sentence ("moody and cinematic", "brighter face, darker sky") into editor settings with Apple's
/// on-device language model (iOS 26, Apple Intelligence). It only moves the app's own controls; it never
/// generates or invents pixels, and nothing leaves the phone.
enum AIEditService {
    /// Why AI edits can't run on this phone, or nil when they can.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "AI edits need an iPhone with Apple Intelligence (iPhone 15 Pro or newer)."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to use AI edits."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still getting ready. Try again in a little while."
            default:
                return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "AI edits need iOS 26 with Apple Intelligence."
    }

    static func plan(for request: String, current: PhotoAdjustmentState, photoFacts: String) async throws -> AIEditValues {
        if let reason = unavailableReason { throw AIEditError.unavailable(reason) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
                The photo: \(photoFacts)
                Current settings: \(AIEditValues(from: current).promptDescription)
                Request: \(request)
                """
            do {
                let response = try await session.respond(to: prompt, generating: GeneratedEdit.self)
                return response.content.values
            } catch {
                throw AIEditError.failed("The on-device AI couldn't do that edit. Try wording it differently.")
            }
        }
        #endif
        throw AIEditError.unavailable("AI edits need iOS 26 with Apple Intelligence.")
    }

    private static let instructions = """
        You are the editing assistant inside a photo editor. The user describes how they want their photo to look. \
        You cannot see the photo; you get short facts about it and the current slider settings. \
        Return the full set of target slider values. Start from the current settings and change only what the \
        request asks for or clearly implies; keep every other value exactly as it is. Prefer natural, photographic \
        results: moderate moves (for example exposure changes of 0.2 to 0.8, warmth of 0.1 to 0.4) unless the user \
        asks for something strong. Use "keep" for the look unless the user asks for a style, film or filter. \
        Film looks: portra (warm, soft skin), ektar (punchy color), gold (golden warmth), fuji400h (pastel, airy), \
        cinestill (cool night film with red glow), trix (black and white film). Subject and background values change \
        only the main subject or only what is behind it. The summary is one short, friendly sentence about what changed.
        """
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Target values for the photo editor's controls")
struct GeneratedEdit {
    @Guide(description: "Exposure in EV stops. 0 means the original brightness.", .range(-2.0...2.0))
    var exposure: Double
    @Guide(description: "Contrast multiplier. 1 is normal.", .range(0.5...1.5))
    var contrast: Double
    @Guide(description: "Saturation multiplier. 1 is normal, 0 is black and white.", .range(0.0...2.0))
    var saturation: Double
    @Guide(description: "Warmth. Positive is warmer (orange), negative is cooler (blue). 0 is unchanged.", .range(-1.0...1.0))
    var warmth: Double
    @Guide(description: "Highlight recovery. 0 is none, -1 darkens bright areas the most.", .range(-1.0...0.0))
    var highlights: Double
    @Guide(description: "Shadows. Positive brightens dark areas, negative deepens them.", .range(-1.0...1.0))
    var shadows: Double
    @Guide(description: "Vignette. Positive darkens the corners, negative lightens them.", .range(-1.0...1.0))
    var vignette: Double
    @Guide(description: "Film grain amount. 0 is none.", .range(0.0...1.0))
    var grain: Double
    @Guide(description: "Red-orange glow around bright lights, like CineStill film. 0 is none.", .range(0.0...1.0))
    var halation: Double
    @Guide(description: "Skin smoothing on faces. 0 is none.", .range(0.0...1.0))
    var skinSmoothing: Double
    @Guide(description: "Brightness of only the main subject (person, pet or object). 0 is unchanged.", .range(-1.0...1.0))
    var subjectBrightness: Double
    @Guide(description: "Brightness of only the background behind the subject. 0 is unchanged.", .range(-1.0...1.0))
    var backgroundBrightness: Double
    @Guide(description: "Saturation of only the background. 0 is unchanged, -1 is black and white.", .range(-1.0...1.0))
    var backgroundSaturation: Double
    @Guide(description: "Color look to apply, or keep to leave the current one")
    var look: GeneratedLook
    @Guide(description: "One short sentence telling the user what you changed")
    var summary: String

    var values: AIEditValues {
        var v = AIEditValues()
        v.exposure = exposure
        v.contrast = contrast
        v.saturation = saturation
        v.warmth = warmth
        v.highlights = highlights
        v.shadows = shadows
        v.vignette = vignette
        v.grain = grain
        v.halation = halation
        v.skinSmoothing = skinSmoothing
        v.subjectBrightness = subjectBrightness
        v.backgroundBrightness = backgroundBrightness
        v.backgroundSaturation = backgroundSaturation
        v.look = String(describing: look)
        v.summary = summary
        return v
    }
}

@available(iOS 26.0, *)
@Generable
enum GeneratedLook {
    case keep, none, vivid, mono, noir, chrome, fade, instant
    case portra, ektar, gold, fuji400h, cinestill, trix
    case y2kGlow, flashPop, cyber, pastel, hd, clarity, hdr, crisp, digicam, ccd, retro
}
#endif

extension ImageProcessingService {
    /// A few plain-language facts about the photo for the AI (it can't see pixels).
    func photoFacts(for image: CGImage, hasFaces: Bool) -> String {
        let side = 64
        let input = CIImage(cgImage: image)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / input.extent.width,
                                                             y: CGFloat(side) / input.extent.height))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(scaled, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var luma = 0.0, chroma = 0.0, cast = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
            chroma += max(r, g, b) - min(r, g, b)
            cast += r - b
        }
        let n = Double(side * side)
        let brightness = luma / n, colorfulness = chroma / n, warmth = cast / n
        let light = brightness < 0.25 ? "dark (night or low light)" : brightness > 0.6 ? "bright" : "medium brightness"
        let color = colorfulness < 0.12 ? "muted colors" : colorfulness > 0.3 ? "vivid colors" : "moderate colors"
        let tone = warmth > 0.08 ? "warm cast" : warmth < -0.08 ? "cool cast" : "neutral color"
        return "\(light), \(color), \(tone), \(image.width > image.height ? "landscape" : "portrait") orientation"
            + (hasFaces ? ", has people" : "")
    }
}
