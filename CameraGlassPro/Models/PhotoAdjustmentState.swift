import Foundation

/// Non-destructive edit recipe. The original image bytes are never touched;
/// this struct is applied to the preview while editing and to the full image on export.
struct PhotoAdjustmentState: Equatable, Codable, Sendable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var warmth: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    /// "Night Look": lifts shadows and reduces noise. A real filter, not a capture mode.
    var nightLook = false

    var isIdentity: Bool { self == PhotoAdjustmentState() }

    subscript(parameter: AdjustmentParameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = parameter.clamp(newValue) }
    }

    mutating func reset(_ parameter: AdjustmentParameter) {
        self[parameter] = parameter.defaultValue
    }

    func isModified(_ parameter: AdjustmentParameter) -> Bool {
        self[parameter] != parameter.defaultValue
    }

    /// Copy with every value inside its valid range (guards decoded or programmatic values).
    func clamped() -> PhotoAdjustmentState {
        var copy = self
        for parameter in AdjustmentParameter.allCases {
            copy[parameter] = self[keyPath: parameter.keyPath]
        }
        return copy
    }
}

enum AdjustmentParameter: String, CaseIterable, Identifiable, Sendable {
    case exposure, brightness, contrast, saturation, warmth, highlights, shadows

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .saturation: "drop"
        case .warmth: "thermometer.medium"
        case .highlights: "circle.righthalf.filled.inverse"
        case .shadows: "circle.bottomhalf.filled"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -2...2          // EV stops
        case .brightness: -0.5...0.5
        case .contrast: 0.5...1.5
        case .saturation: 0...2
        case .warmth: -1...1
        case .highlights: -1...0        // 0 = unchanged, -1 = strongest recovery
        case .shadows: -1...1
        }
    }

    var defaultValue: Double {
        switch self {
        case .contrast, .saturation: 1
        default: 0
        }
    }

    var keyPath: WritableKeyPath<PhotoAdjustmentState, Double> {
        switch self {
        case .exposure: \.exposure
        case .brightness: \.brightness
        case .contrast: \.contrast
        case .saturation: \.saturation
        case .warmth: \.warmth
        case .highlights: \.highlights
        case .shadows: \.shadows
        }
    }

    func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Human-readable value: EV for exposure, signed -100...100 style for the rest.
    func format(_ value: Double) -> String {
        if self == .exposure { return String(format: "%+.1f EV", value) }
        let relative = Int(((value - defaultValue) * 100).rounded())
        return relative == 0 ? "0" : String(format: "%+ld", relative)
    }
}
