import Foundation

/// Every control in the ⠿ panel. Any of them can also be pinned to the top bar via Edit.
enum CameraControl: String, CaseIterable, Identifiable {
    case flash, live, aspect, timer, exposure, styles, filter, depth, nightMode, grid, level, scopes, peaking, format

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nightMode: "NIGHT MODE"
        default: rawValue.uppercased()
        }
    }

    /// Controls that act on the imported photo or video and are disabled until there is one.
    var requiresMedia: Bool {
        switch self {
        case .exposure, .styles, .filter, .depth, .nightMode, .scopes, .peaking: true
        default: false
        }
    }

    /// What iOS shows in the top bar out of the box (matches the reference recording).
    static let defaultTopBar: [CameraControl] = [.flash, .live, .exposure, .styles]

    static func decode(_ stored: String?) -> [CameraControl] {
        guard let stored else { return defaultTopBar }
        let ids = stored.split(separator: ",").map(String.init)
        // Keep panel order and drop unknown or duplicate ids from older versions.
        return allCases.filter { ids.contains($0.rawValue) }
    }

    static func encode(_ controls: [CameraControl]) -> String {
        controls.map(\.rawValue).joined(separator: ",")
    }
}

extension CameraWorkspaceViewModel {
    func symbol(for control: CameraControl) -> String {
        switch control {
        case .flash: flash == .off ? "bolt.slash" : flash.systemImage
        case .live: livePreference ? "livephoto" : "livephoto.slash"
        case .aspect: "aspectratio"
        case .timer: "timer"
        case .exposure: "plusminus"
        case .styles: "square.3.layers.3d"
        case .filter: "camera.filters"
        case .depth: "f.cursive"
        case .nightMode: adjustments.nightLook ? "moon.fill" : "moon"
        case .grid: "squareshape.split.3x3"
        case .level: "level"
        case .scopes: "chart.bar.xaxis"
        case .peaking: "scope"
        case .format: "photo"
        }
    }

    func isActive(_ control: CameraControl) -> Bool {
        switch control {
        case .flash: flash != .off
        case .live: livePreference
        case .aspect: aspect != .original
        case .timer: timer != .off
        case .exposure: isExposureDialVisible || adjustments.exposure != 0
        case .styles: hasEdits
        case .filter: adjustments.filter != .none
        case .depth: depthEffect
        case .nightMode: adjustments.nightLook
        case .grid: gridStyle != .off
        case .level: showLevel
        case .scopes: scopeMode != .off
        case .peaking: focusPeaking
        case .format: false
        }
    }

    /// Short text drawn instead of the icon (e.g. "3s", "16:9", "HEIF"), or nil for the icon.
    func valueText(for control: CameraControl) -> String? {
        switch control {
        case .aspect: aspect == .original ? nil : aspect.rawValue
        case .timer: timer == .off ? nil : timer.label
        case .depth: depthEffect ? "4.5" : nil
        case .scopes: scopeMode.shortLabel
        case .format: exportFormat == .heic ? "HEIF" : exportFormat.label
        default: nil
        }
    }

    func stateDescription(for control: CameraControl) -> String {
        switch control {
        case .flash: flash.label
        case .live: livePreference ? "On" : "Off"
        case .aspect: aspect.label
        case .timer: timer.label
        case .exposure: AdjustmentParameter.exposure.format(adjustments.exposure)
        case .styles: hasEdits ? "Edited" : "No edits"
        case .filter: adjustments.filter.label
        case .depth: depthEffect ? "On, f 4.5" : "Off"
        case .nightMode: adjustments.nightLook ? "On" : "Off"
        case .grid: gridStyle.label
        case .level: showLevel ? "On" : "Off"
        case .scopes: scopeMode.label
        case .peaking: focusPeaking ? "On" : "Off"
        case .format: exportFormat.label
        }
    }

    func hint(for control: CameraControl) -> String {
        switch control {
        case .flash: "Visual flash effect only"
        case .live: "Shows Live as on; imported photos stay still images"
        case .aspect: "Cycles full screen, 4:3, 16:9 and 1:1 framing"
        case .timer: "Delays opening the photo picker"
        case .exposure: "Shows the exposure slider"
        case .styles: "Opens light and color adjustments"
        case .filter: "Cycles Vivid, Mono, Noir, Chrome, Fade and Instant"
        case .depth: "Preview-only depth look with a soft vignette"
        case .nightMode: "Lifts shadows and reduces noise"
        case .grid: "Cycles off, rule of thirds and fine grid"
        case .level: "Shows a level that follows your phone's tilt"
        case .scopes: "Cycles Luminance, RGB and RGB Parade exposure scopes"
        case .peaking: "Highlights the sharpest edges in red"
        case .format: "Cycles the export format: JPEG, HEIF, PNG"
        }
    }

    /// Runs a control. Exposure opens the panel's slider when used from the top bar.
    func perform(_ control: CameraControl, fromTopBar: Bool = false) {
        switch control {
        case .flash: flash = flash.next
        case .live: livePreference.toggle()
        case .aspect: aspect = aspect.next
        case .timer: timer = timer.next
        case .exposure:
            if fromTopBar {
                isExposureDialVisible = true
                isControlPanelOpen = true
            } else {
                isExposureDialVisible.toggle()
            }
        case .styles: showAdjustments = true
        case .filter: cycleFilter()
        case .depth: setDepth(!depthEffect)
        case .nightMode: setNightLook(!adjustments.nightLook)
        case .grid: setGridStyle(gridStyle.next)
        case .level: setShowLevel(!showLevel)
        case .scopes: setScopeMode(scopeMode.next)
        case .peaking: setFocusPeaking(!focusPeaking)
        case .format: cycleExportFormat()
        }
    }
}
