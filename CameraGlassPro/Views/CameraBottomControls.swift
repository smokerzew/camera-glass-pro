import SwiftUI

// iOS Camera-style chrome, matched to the reference recording:
// a plain icon row over the top of the photo, zoom + ƒ + shutter + ⠿ over the bottom of the photo,
// and a black bar below with the thumbnail, the mode capsule and a round action button.

/// Centered row of plain status icons over the top of the viewfinder.
struct CameraStatusRow: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            // Pinned controls (choose them with Edit in the ⠿ panel), plus timer/depth while they're on.
            HStack(spacing: 22) {
                ForEach(vm.visibleTopBarControls) { control in
                    topBarItem(control)
                        .disabled(control.requiresMedia && !vm.hasMedia)
                        .opacity(control.requiresMedia && !vm.hasMedia ? 0.4 : 1)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .shadow(color: .black.opacity(0.45), radius: 2)

            if vm.video != nil {
                Text(vm.timecode)
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(vm.isPlaying ? Color.red : Color.black.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel("Playback time \(vm.timecode)")
            }

            // Shown briefly after toggling depth, then faded out (as in the Camera app).
            if let tag = vm.depthTag {
                CameraTag(text: tag, isOff: !vm.depthEffect).transition(.opacity)
            }
        }
        .padding(.top, 10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: vm.depthTag)
    }

    @ViewBuilder
    private func topBarItem(_ control: CameraControl) -> some View {
        let active = vm.isActive(control) && !(control == .exposure && vm.adjustments.exposure == 0)
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.18)) {
                vm.perform(control, fromTopBar: true)
            }
        } label: {
            Group {
                if control == .exposure {
                    // iOS-style "0.0 / EV" readout.
                    VStack(spacing: -1) {
                        Text(String(format: "%.1f", vm.adjustments.exposure))
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        Text("EV").font(.system(size: 8, weight: .semibold))
                    }
                } else if let value = vm.valueText(for: control) {
                    Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit())
                } else {
                    Image(systemName: vm.symbol(for: control))
                        .font(.system(size: 18, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .foregroundStyle(active ? Color.yellow : .white)
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(control.title.capitalized)
        .accessibilityValue(vm.stateDescription(for: control))
        .accessibilityHint(vm.hint(for: control))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Zoom row, ƒ (depth) button, shutter and ⠿ (more controls) button, floating over the photo.
struct CameraShutterControls: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            if vm.depthTag != nil, vm.depthEffect {
                CameraTag(text: "NATURAL LIGHT").transition(.opacity)
            }

            if vm.hasMedia {
                if vm.isZoomSliderVisible {
                    Slider(
                        value: Binding(get: { Double(vm.zoom) }, set: { vm.setZoom(CGFloat($0)) }),
                        in: Double(ZoomLimits.minimum)...Double(ZoomLimits.maximum)
                    )
                    .tint(.yellow)
                    .frame(width: 240)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .cameraGlass(.regular, in: Capsule())
                    .accessibilityLabel("Preview zoom")
                    .accessibilityValue("\(ZoomLimits.label(for: vm.zoom)) times")
                    .transition(.opacity)
                }
                ZoomSelector(
                    zoom: vm.zoom,
                    onSelect: { preset in
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12)) { vm.setZoom(preset) }
                    },
                    onToggleSlider: {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { vm.isZoomSliderVisible.toggle() }
                    }
                )
            }

            HStack {
                RingedCircleButton(isActive: vm.depthEffect, label: "Depth",
                                   value: vm.depthEffect ? "On" : "Off",
                                   hint: "Preview-only depth look with a soft vignette") {
                    vm.setDepth(!vm.depthEffect)
                } content: {
                    Image(systemName: "f.cursive")
                        .font(.system(size: 18, weight: .medium))
                }
                .disabled(!vm.hasMedia)
                .opacity(vm.hasMedia ? 1 : 0.4)

                Spacer()
                ImportControl(vm: vm)
                Spacer()

                RingedCircleButton(isActive: vm.isControlPanelOpen || vm.hasActiveControls,
                                   label: "More controls",
                                   value: vm.isControlPanelOpen ? "Expanded" : "Collapsed",
                                   hint: "Flash, Live, aspect, timer, exposure, styles, filter, depth, night mode and format") {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.18)) {
                        vm.isExposureDialVisible = false
                        vm.isControlPanelOpen.toggle()
                    }
                } content: {
                    SixDotGlyph()
                }
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 14)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: vm.depthTag)
    }
}

/// Black bar under the viewfinder: thumbnail (export), mode capsule, round import button.
struct CameraBottomBar: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button { vm.showExport = true } label: {
                Group {
                    if let image = vm.displayedImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .cameraGlass(.regular, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!vm.hasMedia)
            .accessibilityLabel("Export photo")
            .accessibilityValue(!vm.hasMedia ? "Nothing imported" : (vm.hasEdits ? "Edited" : "No edits"))
            .accessibilityHint("Share or save the original or an edited copy")

            Spacer(minLength: 0)
            CameraModeSelector(selection: $vm.mode)
                .frame(maxWidth: 250)
            Spacer(minLength: 0)

            GlassIconButton(
                systemImage: "arrow.triangle.2.circlepath",
                label: "Import from Files",
                hint: "Choose a photo from the Files app",
                size: 50
            ) { vm.showFileImporter = true }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

/// Dark glass circle that gains a yellow ring and glyph when active (the ƒ and ⠿ buttons).
struct RingedCircleButton<Content: View>: View {
    let isActive: Bool
    let label: String
    var value: String = ""
    var hint: String = ""
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(isActive ? Color.yellow : .white)
                .frame(width: 48, height: 48)
                .overlay { if isActive { Circle().strokeBorder(.yellow, lineWidth: 1.5) } }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .cameraGlass(.interactive, in: Circle())
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// 3×2 dot grid used by the Camera app's "more controls" button.
struct SixDotGlyph: View {
    var body: some View {
        VStack(spacing: 3.5) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 3.5) {
                    ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 4.5, height: 4.5) }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The big shutter-style circle. It imports or replaces a photo; it never claims to take one.
struct ImportControl: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        Button { vm.primaryAction() } label: {
            ZStack {
                Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 5).frame(width: 82, height: 82)
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3).frame(width: 82, height: 82)
                if vm.centerControlPlaysVideo && vm.isPlaying {
                    // Recording-style stop square while the video plays.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(vm.mode.usesRecordStyle ? Color.red : .white)
                        .frame(width: 68, height: 68)
                }
                if vm.countdown != nil {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button("Choose from Photos", systemImage: "photo.on.rectangle") { vm.showPhotosPicker = true }
            Button("Browse Files", systemImage: "folder") { vm.showFileImporter = true }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(vm.centerControlPlaysVideo
            ? "Touch and hold to import something else."
            : "Opens the photo and video picker. Touch and hold for Files.")
        .animation(.spring(duration: 0.3), value: vm.isPlaying)
    }

    private var accessibilityLabel: String {
        if vm.centerControlPlaysVideo { return vm.isPlaying ? "Pause video" : "Play video" }
        if vm.countdown != nil { return "Cancel timer" }
        return vm.hasMedia ? "Replace" : "Import photo or video"
    }
}
