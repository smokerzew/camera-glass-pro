import Foundation

/// Kinds of background blur behind the subject (SUBJECT > Style > Blur).
enum BackgroundBlurKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case soft, lens, zoom, spin, motion

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
    case blinds, spot, glow, sparkle

    var id: String { rawValue }
    var label: String {
        switch self {
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

/// Pages inside FX > Art.
enum ArtEffect: String, CaseIterable, Identifiable, Sendable {
    case hologram, vision, sort, orbit, melt, planet, depth

    var id: String { rawValue }
    var label: String {
        switch self {
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
