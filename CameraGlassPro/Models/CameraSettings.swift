import SwiftUI

/// UserDefaults keys used with @AppStorage. Preferences only, never photo data.
/// There is no settings screen; these hold defaults and the state of persistent controls (grid, format).
enum SettingsKey {
    static let controlStyle = "settings.controlStyle"
    static let gridStyle = "settings.gridStyle"
    static let gridOpacity = "settings.gridOpacity"
    static let showLevel = "settings.showLevel"
    static let showCenter = "settings.showCenter"
    static let defaultZoom = "settings.defaultZoom"
    static let defaultAspect = "settings.defaultAspect"
    static let keepAdjustmentsOnReplace = "settings.keepAdjustmentsOnReplace"
    static let exportContent = "settings.exportContent"
    static let exportFormat = "settings.exportFormat"
    static let topBarControls = "settings.topBarControls"
    static let reduceMotion = "settings.reduceMotion"
    static let highContrast = "settings.highContrast"
    static let largeLabels = "settings.largeLabels"

}

enum ControlStyle: String, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
    var label: String { self == .glass ? "Liquid Glass" : "Solid" }
}

enum GridStyle: String, CaseIterable, Identifiable {
    case off, thirds, fine
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .thirds: "Rule of Thirds"
        case .fine: "Fine Grid"
        }
    }
    var divisions: Int? {
        switch self {
        case .off: nil
        case .thirds: 3
        case .fine: 6
        }
    }
    var next: GridStyle {
        switch self {
        case .off: .thirds
        case .thirds: .fine
        case .fine: .off
        }
    }
}

/// Visual-only flash preference: "On" plays a flash animation when the import control is used.
enum FlashSetting: String, CaseIterable {
    case off, auto, on
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .off: "bolt.slash.fill"
        case .auto: "bolt.badge.automatic.fill"
        case .on: "bolt.fill"
        }
    }
    var next: FlashSetting {
        switch self {
        case .off: .auto
        case .auto: .on
        case .on: .off
        }
    }
}

/// Delay before the import picker opens.
enum TimerSetting: Int, CaseIterable {
    case off = 0, three = 3, ten = 10
    var label: String { self == .off ? "Off" : "\(rawValue)s" }
    var next: TimerSetting {
        switch self {
        case .off: .three
        case .three: .ten
        case .ten: .off
        }
    }
}

extension EnvironmentValues {
    /// System Reduce Motion OR the in-app preference.
    @Entry var cameraReduceMotion = false
    /// System Increase Contrast OR the in-app preference.
    @Entry var cameraHighContrast = false
    @Entry var cameraLargeLabels = false
    /// Degrees icons turn to stay upright when the phone is held sideways (0, 90 or -90).
    @Entry var cameraIconRotation: Double = 0
}

/// Turns a control's glyph upright in landscape, as the Camera app does (the layout itself stays put).
struct RotatesWithDevice: ViewModifier {
    @Environment(\.cameraIconRotation) private var degrees
    @Environment(\.cameraReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(degrees))
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1), value: degrees)
    }
}

extension View {
    func rotatesWithDevice() -> some View { modifier(RotatesWithDevice()) }
}
