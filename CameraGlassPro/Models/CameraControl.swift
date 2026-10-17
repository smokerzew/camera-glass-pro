import Foundation

/// Every control in the ⠿ panel. Any of them can also be pinned to the top bar via Edit.
enum CameraControl: String, CaseIterable, Identifiable {
    case flash, live, aspect, timer, exposure, styles, filter, crop, depth, subject, nightMode, grid, level, scopes, peaking, zebras, liveText, effects, trim, format

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nightMode: "NIGHT MODE"
        case .liveText: "TEXT"
        default: rawValue.uppercased()
        }
    }

    /// Controls that act on the imported photo or video and are disabled until there is one.
    var requiresMedia: Bool {
        switch self {
        case .exposure, .styles, .filter, .crop, .depth, .subject, .nightMode, .scopes, .peaking, .zebras, .liveText, .effects, .trim: true
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
    /// Whether a control can be used right now (TRIM needs a video, editing controls need media).
    func isAvailable(_ control: CameraControl) -> Bool {
        if control == .trim { return video != nil }
        if control == .effects { return canMakeEffects }
        if control == .crop { return photo != nil }
        return !control.requiresMedia || hasMedia
    }

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
        case .zebras: "line.diagonal"
        case .trim: "timeline.selection"
        case .liveText: "text.viewfinder"
        case .effects: "livephoto.play"
        case .subject: "person.crop.rectangle.stack"
        case .crop: "crop.rotate"
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
        case .zebras: zebras
        case .trim: isTrimmed
        case .liveText: liveTextEnabled
        case .effects: false
        case .subject: adjustments.colorSplash || adjustments.background != .original
        case .crop: adjustments.hasGeometry
        case .format: false
        }
    }

    /// Short text drawn instead of the icon (e.g. "3s", "16:9", "HEIF"), or nil for the icon.
    func valueText(for control: CameraControl) -> String? {
        switch control {
        case .aspect: aspect == .original ? nil : aspect.rawValue
        case .timer: timer == .off ? nil : timer.label
        case .depth: depthEffect ? String(format: "ƒ%.1f", adjustments.aperture) : nil
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
        case .depth: depthEffect ? String(format: "On, f %.1f, %@", adjustments.aperture, adjustments.lighting.label.capitalized) : "Off"
        case .nightMode: adjustments.nightLook ? "On" : "Off"
        case .grid: gridStyle.label
        case .level: showLevel ? "On" : "Off"
        case .scopes: scopeMode.label
        case .peaking: focusPeaking ? "On" : "Off"
        case .zebras: zebras ? "On" : "Off"
        case .trim: isTrimmed ? String(format: "%.1f s to %.1f s", trimStart, trimEnd) : "Full length"
        case .liveText: liveTextEnabled ? "\(recognizedText.count) lines found" : "Off"
        case .effects: canMakeEffects ? "Loop, Bounce, Long Exposure, Live Photo" : "Needs a video or Live Photo"
        case .crop: adjustments.hasGeometry ? "Edited" : "Original framing"
        case .subject: [adjustments.colorSplash ? "Color Splash" : nil,
                        adjustments.background != .original ? "Background \(adjustments.background.label.capitalized)" : nil]
            .compactMap { $0 }.joined(separator: ", ").ifEmpty("Off")
        case .format: exportFormat.label
        }
    }

    func hint(for control: CameraControl) -> String {
        switch control {
        case .flash: "Visual flash effect only"
        case .live: "Plays a Live Photo's motion when it opens; touch and hold LIVE to play it again"
        case .aspect: "Cycles full screen, 4:3, 16:9 and 1:1 framing"
        case .timer: "Delays opening the photo picker"
        case .exposure: "Shows the exposure slider"
        case .styles: "Opens Photographic Styles: style, tone and color pad, palette"
        case .filter: "Opens the filter picker: Classic, Y2K, Quality and DigiCam FX"
        case .depth: "Blurs the background behind the subject; tap the f-number to change depth"
        case .nightMode: "Lifts shadows and reduces noise"
        case .grid: "Cycles off, rule of thirds and fine grid"
        case .level: "Shows a level that follows your phone's tilt"
        case .scopes: "Cycles Luminance, RGB and RGB Parade exposure scopes"
        case .peaking: "Highlights the sharpest edges in red"
        case .zebras: "Stripes the brightest areas that are close to clipping"
        case .trim: "Choose where the video starts and ends"
        case .liveText: "Finds text you can copy or translate (pauses videos)"
        case .effects: "Makes a Loop, Bounce or Long Exposure, or turns a video into a Live Photo"
        case .subject: "Color Splash and Background Swap for people, pets and objects"
        case .crop: "Crop, rotate, flip and straighten the photo"
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
        case .styles: openStylesPad()
        case .filter: openFilterPicker()
        case .depth:
            // From the top bar, the f-number readout opens the aperture slider (as in the Camera app).
            if fromTopBar && depthEffect { isApertureDialVisible.toggle() } else { setDepth(!depthEffect) }
        case .nightMode: setNightLook(!adjustments.nightLook)
        case .grid: setGridStyle(gridStyle.next)
        case .level: setShowLevel(!showLevel)
        case .scopes: setScopeMode(scopeMode.next)
        case .peaking: setFocusPeaking(!focusPeaking)
        case .zebras: setZebras(!zebras)
        case .trim: showTrim = true
        case .liveText: setLiveText(!liveTextEnabled)
        case .effects: openEffectsPicker()
        case .subject: openSubjectPicker()
        case .crop: openCropEditor()
        case .format: cycleExportFormat()
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
