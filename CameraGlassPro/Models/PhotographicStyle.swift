import Foundation

/// iOS-style Photographic Styles. Each has an undertone (color cast) plus a base tone/color character;
/// the 2D pad adds Tone (vertical) and Color (horizontal), and Palette scales how strong the style is.
enum PhotographicStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, amber, gold, roseGold, neutral, coolRose, cool
    case vibrant, natural, luminous, dramatic, quiet, cozy, ethereal
    case mutedBW, starkBW

    var id: String { rawValue }

    var label: String {
        switch self {
        case .roseGold: "Rose Gold"
        case .coolRose: "Cool Rose"
        case .mutedBW: "Muted B&W"
        case .starkBW: "Stark B&W"
        default: rawValue.capitalized
        }
    }

    /// Color cast added at full palette (RGB bias).
    var undertone: (r: Double, g: Double, b: Double) {
        switch self {
        case .standard, .natural, .mutedBW, .starkBW: (0, 0, 0)
        case .amber: (0.035, 0.015, -0.025)
        case .gold: (0.03, 0.025, -0.03)
        case .roseGold: (0.035, 0.0, 0.015)
        case .neutral: (-0.01, 0.0, 0.01)
        case .coolRose: (0.015, -0.01, 0.03)
        case .cool: (-0.02, 0.0, 0.035)
        case .vibrant: (0.0, 0.0, 0.0)
        case .luminous: (0.015, 0.01, 0.0)
        case .dramatic: (0.0, -0.005, 0.01)
        case .quiet: (0.01, 0.01, 0.01)
        case .cozy: (0.03, 0.01, -0.02)
        case .ethereal: (0.01, 0.0, 0.025)
        }
    }

    /// Base character at full palette: (tone, color) offsets in the pad's -1...1 units.
    var character: (tone: Double, color: Double) {
        switch self {
        case .standard, .neutral, .natural: (0, 0)
        case .amber, .gold, .roseGold, .coolRose, .cool: (0, 0.1)
        case .vibrant: (0.1, 0.6)
        case .luminous: (-0.35, 0.2)
        case .dramatic: (0.6, 0.0)
        case .quiet: (-0.4, -0.45)
        case .cozy: (0.2, 0.15)
        case .ethereal: (-0.5, -0.2)
        case .mutedBW: (-0.3, 0)
        case .starkBW: (0.6, 0)
        }
    }

    var isMonochrome: Bool { self == .mutedBW || self == .starkBW }
}
