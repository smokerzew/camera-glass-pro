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

/// Pages inside FX > Art.
enum ArtEffect: String, CaseIterable, Identifiable, Sendable {
    case hologram, vision, sort, orbit, melt

    var id: String { rawValue }
    var label: String {
        switch self {
        case .hologram: "Holo"
        case .vision: "Vision"
        case .sort: "Sort"
        case .orbit: "Orbit"
        case .melt: "Melt"
        }
    }
}
