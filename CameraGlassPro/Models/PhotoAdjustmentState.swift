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
    /// Local contrast (iOS 27 "Styles 3" texture): + crisper detail, − softer.
    var texture: Double = 0
    /// Film-like luminance grain.
    var grain: Double = 0
    /// "Night Look": lifts shadows and reduces noise. A real filter, not a capture mode.
    var nightLook = false
    /// Photo look applied after the adjustments (the panel's FILTER control).
    var filter: PhotoFilter = .none
    /// Photographic Style and its 2D pad position (Tone vertical, Color horizontal) and Palette strength.
    var style: PhotographicStyle = .standard
    var styleTone: Double = 0
    var styleColor: Double = 0
    var stylePalette: Double = 1

    var isIdentity: Bool { self == PhotoAdjustmentState() }

    init() {}

    /// Missing keys fall back to defaults, so presets saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        nightLook = try c.decodeIfPresent(Bool.self, forKey: .nightLook) ?? false
        filter = try c.decodeIfPresent(PhotoFilter.self, forKey: .filter) ?? .none
        style = try c.decodeIfPresent(PhotographicStyle.self, forKey: .style) ?? .standard
        styleTone = min(max(try c.decodeIfPresent(Double.self, forKey: .styleTone) ?? 0, -1), 1)
        styleColor = min(max(try c.decodeIfPresent(Double.self, forKey: .styleColor) ?? 0, -1), 1)
        stylePalette = min(max(try c.decodeIfPresent(Double.self, forKey: .stylePalette) ?? 1, 0), 1)
    }

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
    case exposure, brightness, contrast, saturation, warmth, highlights, shadows, texture, grain

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
        case .texture: "circle.hexagongrid"
        case .grain: "circle.dotted"
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
        case .texture: -1...1
        case .grain: 0...1
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
        case .texture: \.texture
        case .grain: \.grain
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

/// Photo looks picked in the FILTER pop-up (grouped by `FilterCategory`).
enum PhotoFilter: String, CaseIterable, Codable, Sendable {
    case none, vivid, mono, noir, chrome, fade, instant
    case y2kGlow, flashPop, cyber, pastel
    case hd, clarity, hdr, crisp
    case digicam, ccd, lofi, dateStamp

    var label: String {
        switch self {
        case .none: "Off"
        case .y2kGlow: "Y2K Glow"
        case .flashPop: "Flash Pop"
        case .pastel: "Pastel"
        case .hd: "HD"
        case .hdr: "HDR"
        case .digicam: "DigiCam"
        case .ccd: "CCD"
        case .lofi: "Lo-Fi"
        case .dateStamp: "Date Stamp"
        default: rawValue.capitalized
        }
    }

    var next: PhotoFilter {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
