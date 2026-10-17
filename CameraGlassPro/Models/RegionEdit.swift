import Foundation

/// Which part of the photo a subject-aware edit targets.
enum PhotoRegion: String, CaseIterable, Identifiable, Sendable {
    case subject, background

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Light and color for just the subject or just the background. Values are -1...1; 0 = unchanged.
struct RegionEdit: Equatable, Codable, Sendable {
    /// ±1.5 EV at the ends.
    var exposure: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0

    var isNeutral: Bool { self == RegionEdit() }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) -> Double {
            let v = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? 0
            return v.isFinite ? min(max(v, -1), 1) : 0
        }
        exposure = value(.exposure)
        saturation = value(.saturation)
        warmth = value(.warmth)
    }

    enum Control: String, CaseIterable, Identifiable, Sendable {
        case exposure, saturation, warmth

        var id: String { rawValue }
        var label: String { self == .exposure ? "Brightness" : rawValue.capitalized }

        var keyPath: WritableKeyPath<RegionEdit, Double> {
            switch self {
            case .exposure: \.exposure
            case .saturation: \.saturation
            case .warmth: \.warmth
            }
        }
    }
}
