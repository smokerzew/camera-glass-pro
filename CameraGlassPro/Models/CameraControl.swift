import Foundation

/// Every control in the ⠿ panel. Any of them can also be pinned to the top bar via Edit.
enum CameraControl: String, CaseIterable, Identifiable {
    case flash, live, aspect, timer, exposure, collage, styles, filter, adjust, fx, liquify, remove, crop, depth, subject, nightMode, grid, level, scopes, peaking, zebras, liveText, effects, trim, frame, format
    case scan, compose, manual, raw, torch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nightMode: "NIGHT MODE"
        case .liveText: "TEXT"
        case .raw: "RAW"
        default: rawValue.uppercased()
        }
    }

    /// Controls that act on the imported photo or video and are disabled until there is one.
    var requiresMedia: Bool {
        switch self {
        case .exposure, .styles, .filter, .adjust, .fx, .liquify, .remove, .crop, .depth, .subject, .nightMode, .scopes, .peaking, .zebras, .liveText, .effects, .trim, .frame: true
        default: false
        }
    }

    /// Which page of the controls panel it sits on.
    var group: PanelGroup {
        switch self {
        case .flash, .live, .aspect, .timer, .exposure, .collage, .nightMode, .format: .camera
        case .adjust, .styles, .filter, .fx, .liquify, .crop, .depth, .subject, .effects: .edit
        case .remove, .grid, .level, .scopes, .peaking, .zebras, .liveText, .trim, .frame: .tools
        case .scan, .compose, .manual, .raw, .torch: .pro
        }
    }

    /// What iOS shows in the top bar out of the box (matches the reference recording).
    static let defaultTopBar: [CameraControl] = [.flash, .scan, .exposure, .styles]

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
        if showingCamera { return isAvailableLive(control) }
        if control.group == .pro { return false } // capture controls only work while shooting
        if control == .trim || control == .frame { return video != nil }
        if control == .collage { return collageEntries.count >= 2 }
        if control == .effects { return canMakeEffects }
        if control == .crop || control == .liquify || control == .remove { return photo != nil }
        return !control.requiresMedia || hasMedia
    }

    /// What works on the live camera: capture settings, and looks that apply to the photo once it's taken.
    func isAvailableLive(_ control: CameraControl) -> Bool {
        let running = camera.isRunning
        switch control {
        case .flash: return running && camera.capabilities.hasFlash
        case .torch: return running && camera.capabilities.hasTorch
        case .aspect, .timer, .exposure, .scan, .compose: return running
        case .manual: return running && camera.hasManualControls
        case .raw: return running && camera.supportsAnyRAW
        case .styles, .filter, .depth, .nightMode, .grid, .level, .format: return true
        default: return false
        }
    }

    func symbol(for control: CameraControl) -> String {
        switch control {
        case .scan: "viewfinder"
        case .compose: "rectangle.dashed"
        case .manual: "dial.medium"
        case .raw: "r.square"
        case .torch: camera.torch ? "flashlight.on.fill" : "flashlight.off.fill"
        case .flash: flash == .off ? "bolt.slash" : flash.systemImage
        case .live: livePreference ? "livephoto" : "livephoto.slash"
        case .aspect: "aspectratio"
        case .timer: "timer"
        case .collage: "rectangle.split.2x2"
        case .exposure: "plusminus"
        case .styles: "square.3.layers.3d"
        case .filter: "camera.filters"
        case .adjust: "slider.horizontal.3"
        case .fx: "wand.and.stars"
        case .liquify: "hand.draw"
        case .remove: "eraser"
        case .depth: "f.cursive"
        case .nightMode: adjustments.nightLook ? "moon.fill" : "moon"
        case .grid: "squareshape.split.3x3"
        case .level: "level"
        case .scopes: "chart.bar.xaxis"
        case .peaking: "scope"
        case .zebras: "line.diagonal"
        case .trim: "timeline.selection"
        case .frame: "photo.badge.arrow.down"
        case .liveText: "text.viewfinder"
        case .effects: "livephoto.play"
        case .subject: "person.crop.rectangle.stack"
        case .crop: "crop.rotate"
        case .format: "photo"
        }
    }

    func isActive(_ control: CameraControl) -> Bool {
        switch control {
        case .scan: camera.scan != .idle
        case .compose: camera.isComposing || camera.frame != nil
        case .manual: showManualControls || !camera.manual.isAuto
        case .raw: showingCamera && camera.rawMode != .off
        case .torch: camera.torch
        case .flash: flash != .off
        case .live: livePreference
        case .aspect: aspect != .original
        case .timer: timer != .off
        case .exposure: isExposureDialVisible || adjustments.exposure != 0
        case .styles: hasEdits
        case .filter: adjustments.filter != .none
        case .adjust: false
        case .liquify: !adjustments.liquifyStrokes.isEmpty
        case .remove: !adjustments.removeStrokes.isEmpty
        case .fx: adjustments.speedBlur > 0 || adjustments.tiltShift > 0 || adjustments.doubleExposure > 0
            || (!adjustments.focusStrokes.isEmpty && adjustments.focusBlur > 0)
            || adjustments.ghostOpacity > 0 || adjustments.lookMatch != nil
            || adjustments.hologram > 0 || adjustments.melt > 0 || adjustments.orbitClones > 0
            || adjustments.visionMode != .none || adjustments.pixelSort > 0 || adjustments.littlePlanet > 0
            || adjustments.depthMap > 0 || adjustments.blinds > 0 || adjustments.spotlight > 0 || adjustments.glow > 0
            || adjustments.sparkle > 0 || adjustments.vhs > 0 || adjustments.webcam > 0 || adjustments.halftone > 0 || adjustments.chroma > 0
            || (adjustments.pop != .none && adjustments.popAmount > 0)
            || adjustments.flare > 0 || adjustments.prism > 0 || adjustments.paint > 0 || adjustments.mirror != .off
            || (adjustments.weather != .none && adjustments.weatherAmount > 0)
            || (adjustments.redactionTarget == .faces ? adjustments.faceRedaction != .none : !adjustments.redactionStrokes.isEmpty)
        case .depth: depthEffect
        case .nightMode: adjustments.nightLook
        case .grid: gridStyle != .off
        case .level: showLevel
        case .scopes: scopeMode != .off
        case .peaking: focusPeaking
        case .zebras: zebras
        case .trim: isTrimmed
        case .frame: false
        case .collage: false
        case .liveText: liveTextEnabled
        case .effects: false
        case .subject: adjustments.colorSplash || adjustments.background != .original || adjustments.skyReplace != .none
            || adjustments.hasSubjectEffects
        case .crop: adjustments.hasGeometry
        case .format: false
        }
    }

    /// Short text drawn instead of the icon (e.g. "3s", "16:9", "HEIF"), or nil for the icon.
    func valueText(for control: CameraControl) -> String? {
        switch control {
        case .aspect where showingCamera: aspect.portraitLabel
        case .raw: showingCamera && camera.rawMode != .off ? (camera.rawMode == .proRAW ? "PRO" : "RAW") : nil
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
        case .scan: camera.scanResult.map { $0.isConclusive ? "Suggestion ready" : "No clear suggestion" } ?? "Off"
        case .compose: camera.frame == nil ? "No frame" : (camera.alignment?.isAligned == true ? "Aligned" : "Frame set")
        case .manual: camera.manual.isAuto ? "Auto" : "Manual"
        case .raw: camera.rawMode.label
        case .torch: camera.torch ? "On" : "Off"
        case .flash: flash.label
        case .live: livePreference ? "On" : "Off"
        case .aspect: aspect.label
        case .timer: timer.label
        case .exposure: AdjustmentParameter.exposure.format(adjustments.exposure)
        case .styles: hasEdits ? "Edited" : "No edits"
        case .filter: adjustments.filter.label
        case .adjust: hasEdits ? "Edited" : "No edits"
        case .liquify: adjustments.liquifyStrokes.isEmpty ? "Off" : "\(adjustments.liquifyStrokes.count) pushes"
        case .remove: adjustments.removeStrokes.isEmpty ? "Off" : "\(adjustments.removeStrokes.count) areas removed"
        case .fx: isActive(.fx) ? "On" : "Off"
        case .depth: depthEffect ? String(format: "On, f %.1f, %@", adjustments.aperture, adjustments.lighting.label.capitalized) : "Off"
        case .nightMode: adjustments.nightLook ? "On" : "Off"
        case .grid: gridStyle.label
        case .level: showLevel ? "On" : "Off"
        case .scopes: scopeMode.label
        case .peaking: focusPeaking ? "On" : "Off"
        case .zebras: zebras ? "On" : "Off"
        case .trim: isTrimmed ? String(format: "%.1f s to %.1f s", trimStart, trimEnd) : "Full length"
        case .frame: video != nil ? "Pick a frame to save" : "Needs a video"
        case .collage: collageEntries.count >= 2 ? "\(collageEntries.count) photos" : "Needs 2 or more photos"
        case .liveText: liveTextEnabled ? "\(recognizedText.count) lines found" : "Off"
        case .effects: canMakeEffects ? "Loop, Bounce, Reverse, Echo, GIF and more" : "Needs a video or Live Photo"
        case .crop: adjustments.hasGeometry ? "Edited" : "Original framing"
        case .subject: [adjustments.colorSplash ? "Color Splash" : nil,
                        adjustments.background != .original ? "Background \(adjustments.background.label.capitalized)" : nil,
                        adjustments.skyReplace != .none ? "\(adjustments.skyReplace.label) Sky" : nil]
            .compactMap { $0 }.joined(separator: ", ").ifEmpty("Off")
        case .format: exportFormat.label
        }
    }

    func hint(for control: CameraControl) -> String {
        switch control {
        case .scan: "Analyzes the scene and suggests a framing, with measured exposure and level notes"
        case .compose: "Draw your own frame on the viewfinder and tap a subject to track how it lines up"
        case .manual: "ISO, shutter speed, focus and white balance, where this camera supports them"
        case .raw: "Also saves a RAW (or Apple ProRAW) original, where this iPhone supports it"
        case .torch: "Keeps the flashlight on while you frame"
        case .flash: "Visual flash effect only"
        case .live: "Plays a Live Photo's motion when it opens; touch and hold LIVE to play it again"
        case .aspect: "Cycles full screen, 4:3, 16:9 and 1:1 framing"
        case .timer: "Delays opening the photo picker"
        case .exposure: "Shows the exposure slider"
        case .styles: "Opens Photographic Styles: style, tone and color pad, palette"
        case .filter: "Opens the filter picker: 174 filters in 20 tabs"
        case .adjust: "Opens Adjust: light, color, detail, effects, local filters and AI"
        case .liquify: "Push and reshape parts of the photo with your finger"
        case .remove: "Paint over a small object or blemish to fill it in from its surroundings"
        case .fx: "Blur, Blend, Ghost, Art, Light, Retro, Pop and Privacy effects"
        case .depth: "Blurs the background behind the subject; tap the f-number to change depth"
        case .nightMode: "Live Photos: stacks the motion frames into a clean night shot. Others: lifts shadows and reduces noise"
        case .grid: "Cycles off, rule of thirds and fine grid"
        case .level: "Shows a level that follows your phone's tilt"
        case .scopes: "Cycles Luminance, RGB and RGB Parade exposure scopes"
        case .peaking: "Highlights the sharpest edges in red"
        case .zebras: "Stripes the brightest areas that are close to clipping"
        case .trim: "Choose where the video starts and ends"
        case .frame: "Step to the exact frame, then save it as a photo with or without the camera UI"
        case .collage: "Puts 2 to 6 of the photos you picked into one picture"
        case .liveText: "Finds text you can copy or translate (pauses videos)"
        case .effects: "Makes a Loop, Bounce, Reverse, Speed Ramp, Stop Motion, Echo, GIF or Long Exposure, or a Live Photo"
        case .subject: "Color Splash, Background Swap and Sky Replace"
        case .crop: "Crop, rotate, flip and straighten the photo"
        case .format: "Cycles the export format: JPEG, HEIF, PNG"
        }
    }

    /// Runs a control. Exposure opens the panel's slider when used from the top bar.
    func perform(_ control: CameraControl, fromTopBar: Bool = false) {
        switch control {
        case .scan:
            isControlPanelOpen = false
            if camera.scan == .idle { camera.startScan() } else { camera.dismissScan() }
        case .compose:
            isControlPanelOpen = false
            camera.dismissScan()
            camera.isComposing.toggle()
        case .manual:
            isControlPanelOpen = false
            showManualControls = true
            camera.watchReadings(true)
        case .raw: camera.cycleRaw()
        case .torch: camera.setTorch(!camera.torch)
        case .flash: flash = flash.next
        case .live: livePreference.toggle()
        case .aspect:
            aspect = aspect.next
            // The camera's frames are always one of 3:4, 4:5, 9:16 and 1:1 ("Full" is 3:4 there).
            if showingCamera, aspect == .original { aspect = aspect.next }
            if showingCamera { camera.composeAspect = aspect }
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
        case .adjust:
            isControlPanelOpen = false
            showAdjustments = true
        case .fx: openFXPicker()
        case .liquify:
            isControlPanelOpen = false
            showLiquifyEditor = true
        case .remove:
            isControlPanelOpen = false
            showRemoveEditor = true
        case .depth:
            // From the top bar, the f-number readout opens the aperture slider (as in the Camera app).
            if fromTopBar && depthEffect { isApertureDialVisible.toggle() } else { setDepth(!depthEffect) }
        case .nightMode:
            // Live Photos get the real thing: their motion frames stacked into a clean night shot (a new item).
            if photo?.pairedVideoURL != nil, !adjustments.nightLook { runEffect(.night) } else { setNightLook(!adjustments.nightLook) }
        case .grid: setGridStyle(gridStyle.next)
        case .level: setShowLevel(!showLevel)
        case .scopes: setScopeMode(scopeMode.next)
        case .peaking: setFocusPeaking(!focusPeaking)
        case .zebras: setZebras(!zebras)
        case .trim: showTrim = true
        case .frame: openFramePicker()
        case .collage:
            isControlPanelOpen = false
            showCollage = true
        case .liveText: setLiveText(!liveTextEnabled)
        case .effects: openEffectsPicker()
        case .subject: openSubjectPicker()
        case .crop: openCropEditor()
        case .format: cycleExportFormat()
        }
    }
}

/// Pages of the controls panel, so it shows a handful of controls at a time.
enum PanelGroup: String, CaseIterable, Sendable {
    case camera, pro, edit, tools
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
