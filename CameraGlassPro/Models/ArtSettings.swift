import Foundation

/// Kinds of background blur behind the subject (SUBJECT > Style > Blur).
enum BackgroundBlurKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case soft, lens, zoom, spin, motion

    /// Blur slider (0...1) to the share of each kind's maximum blur: squared, so the low end is fine-grained
    /// (10% gives 1% of the maximum, half gives a quarter) and 0 is no blur.
    static func curve(_ amount: Double) -> Double {
        let a = min(max(amount, 0), 1)
        return a * a
    }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .soft: "Soft"
        case .lens: "Lens"
        case .zoom: "Zoom"
        case .spin: "Spin"
        case .motion: "Motion"
        }
    }
}

/// Thermal camera or night-vision goggles look.
enum VisionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, thermal, night

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Off"
        case .thermal: "Thermal"
        case .night: "Night Vision"
        }
    }
}

/// Where a filter applies.
enum FilterTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, subject, background

    var id: String { rawValue }
    var label: String { self == .all ? "Everything" : rawValue.capitalized }
}

/// Pages inside FX > Light.
enum LightEffect: String, CaseIterable, Identifiable, Sendable {
    case blinds, spot, glow, sparkle, flare, prism

    var id: String { rawValue }
    var label: String {
        switch self {
        case .flare: "Flare"
        case .prism: "Prism"
        case .blinds: "Blinds"
        case .spot: "Spotlight"
        case .glow: "Glow"
        case .sparkle: "Sparkle"
        }
    }
}

/// Pages inside FX > Retro.
enum RetroEffect: String, CaseIterable, Identifiable, Sendable {
    case vhs, webcam, halftone, chroma

    var id: String { rawValue }
    var label: String {
        switch self {
        case .vhs: "VHS"
        case .webcam: "Webcam"
        case .halftone: "Halftone"
        case .chroma: "Chroma"
        }
    }
}

/// FX > Pop effects, one at a time. `popOption` is the palette, segment count or pixel size where there is one.
enum PopEffect: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, glitch, lightLeak, duotone, kaleidoscope, fisheye, pixelArt, anaglyph, crt, comic, glitter

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Off"
        case .glitch: "Glitch"
        case .lightLeak: "Light Leak"
        case .duotone: "Duotone"
        case .kaleidoscope: "Kaleido"
        case .fisheye: "Fisheye"
        case .pixelArt: "Pixel Art"
        case .anaglyph: "3D"
        case .crt: "CRT TV"
        case .comic: "Comic"
        case .glitter: "Glitter"
        }
    }

    var note: String {
        switch self {
        case .none: ""
        case .glitch: "Torn, shifted slices with split red and blue, like a broken digital signal."
        case .lightLeak: "Warm orange and pink light bleeding in from the edges, like an old film camera."
        case .duotone: "The photo in two colors: one for the shadows, one for the highlights."
        case .kaleidoscope: "Mirrors the middle of the photo into a kaleidoscope pattern."
        case .fisheye: "A bulging ultra-wide lens with dark round edges."
        case .pixelArt: "Big pixels and few colors, like an 8-bit game."
        case .anaglyph: "Red and cyan 3D, for red-blue glasses."
        case .crt: "An old tube TV: scan lines, soft glow and curved dark corners."
        case .comic: "Ink outlines and dots, like a printed comic book."
        case .glitter: "Scattered sparkles over the photo."
        }
    }

    /// The effect's extra setting, if it has one.
    var optionTitle: String? {
        switch self {
        case .kaleidoscope: "Segments"
        case .pixelArt: "Pixel Size"
        default: nil
        }
    }

    static let duotoneNames = ["Pink Blue", "Teal Orange", "Purple Gold", "Navy Red", "Green Pink"]
    static func duotoneIndex(_ option: Double) -> Int { min(max(Int((option * 4).rounded()), 0), duotoneNames.count - 1) }
    static func kaleidoscopeSegments(_ option: Double) -> Int { 3 + Int((min(max(option, 0), 1) * 9).rounded()) }
}

/// Pages inside FX > Art.
enum ArtEffect: String, CaseIterable, Identifiable, Sendable {
    case hologram, vision, sort, orbit, melt, planet, depth, paint, mirror

    var id: String { rawValue }
    var label: String {
        switch self {
        case .paint: "Paint"
        case .mirror: "Mirror"
        case .hologram: "Holo"
        case .vision: "Vision"
        case .sort: "Sort"
        case .orbit: "Orbit"
        case .melt: "Melt"
        case .planet: "Planet"
        case .depth: "Depth"
        }
    }
}
