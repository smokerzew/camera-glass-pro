import PhotosUI
import SwiftUI

/// Full-screen camera-inspired workspace: top toolbar, viewfinder, floating zoom/panel, bottom controls.
struct CameraWorkspaceView: View {
    @State private var vm = CameraWorkspaceViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var flashOpacity = 0.0

    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.dark
    @AppStorage(SettingsKey.controlOpacity) private var controlOpacity = 1.0
    @AppStorage(SettingsKey.previewBackground) private var previewBackground = PreviewBackground.black
    @AppStorage(SettingsKey.reduceMotion) private var appReduceMotion = false
    @AppStorage(SettingsKey.highContrast) private var appHighContrast = false
    @AppStorage(SettingsKey.largeLabels) private var largeLabels = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        workspace
            .environment(\.colorScheme, .dark) // the viewfinder is always dark; sheets follow the appearance setting
            .photosPicker(isPresented: $vm.showPhotosPicker, selection: $pickerItem,
                          matching: .images, preferredItemEncoding: .current)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                vm.importFromLibrary(item)
                pickerItem = nil
            }
            .fileImporter(isPresented: $vm.showFileImporter, allowedContentTypes: [.image]) { result in
                vm.importFromFile(result)
            }
            .sheet(isPresented: $vm.showAdjustments) { PhotoAdjustmentView(vm: vm) }
            .sheet(isPresented: $vm.showExport) { PhotoExportView(vm: vm) }
            .sheet(isPresented: $vm.showSettings) { CameraSettingsView() }
            .appAlert(vm)
            .sensoryFeedback(.success, trigger: vm.importSuccessCount)
            .sensoryFeedback(.selection, trigger: vm.mode)
            .sensoryFeedback(.selection, trigger: vm.aspect)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.flashPulse)
            .sensoryFeedback(.error, trigger: vm.alert?.id) { _, new in new != nil }
            .onChange(of: vm.flashPulse) { playFlash() }
            .environment(\.cameraReduceMotion, reduceMotion)
            .environment(\.cameraHighContrast, appHighContrast || systemContrast == .increased)
            .environment(\.cameraLargeLabels, largeLabels)
            .preferredColorScheme(appearance.colorScheme)
            .statusBarHidden()
    }

    private var workspace: some View {
        ZStack {
            background

            VStack(spacing: 8) {
                CameraToolbar(vm: vm)
                    .opacity(controlOpacity)

                ZStack(alignment: .bottom) {
                    PhotoPreviewView(vm: vm)
                    floatingControls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CameraBottomControls(vm: vm)
                    .opacity(controlOpacity)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1) // camera chrome has fixed geometry

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let seconds = vm.countdown {
                CountdownOverlay(seconds: seconds) { vm.cancelCountdown() }
                    .transition(.opacity)
            }

            if vm.isImporting {
                LoadingOverlay(message: vm.importMessage) { vm.cancelImport() }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.isImporting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.countdown)
    }

    @ViewBuilder
    private var background: some View {
        switch previewBackground {
        case .black:
            Color.black.ignoresSafeArea()
        case .graphite:
            Color(white: 0.09).ignoresSafeArea()
        case .ambient:
            Color.black
                .overlay {
                    if let image = vm.displayedImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 60)
                            .opacity(0.45)
                    }
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            if vm.isControlPanelOpen {
                CameraControlPanel(vm: vm)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            } else if vm.photo != nil {
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
                .opacity(controlOpacity)
            }
        }
        .padding(.bottom, 12)
    }

    private func playFlash() {
        guard !reduceMotion else { return } // no full-screen flashes with Reduce Motion
        flashOpacity = 0.85
        withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
    }
}

extension View {
    /// Shared alert presentation; applied at the root and inside sheets so errors show wherever the user is.
    func appAlert(_ vm: CameraWorkspaceViewModel) -> some View {
        alert(
            vm.alert?.title ?? "",
            isPresented: Binding(get: { vm.alert != nil }, set: { if !$0 { vm.alert = nil } }),
            presenting: vm.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}
