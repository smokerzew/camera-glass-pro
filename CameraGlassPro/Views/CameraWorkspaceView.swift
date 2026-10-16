import PhotosUI
import SwiftUI

/// Full-screen workspace laid out like the iOS 27 Camera app: the photo fills the viewfinder,
/// status icons float over its top, zoom/shutter controls over its bottom, and a black bar holds
/// the thumbnail, the mode capsule and a round action button.
struct CameraWorkspaceView: View {
    @State private var vm = CameraWorkspaceViewModel(sessionStore: .standard)
    @State private var pickerItems: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var scenePhase
    @State private var flashOpacity = 0.0
    @State private var motion = MotionLevel()

    @AppStorage(SettingsKey.reduceMotion) private var appReduceMotion = false
    @AppStorage(SettingsKey.highContrast) private var appHighContrast = false
    @AppStorage(SettingsKey.largeLabels) private var largeLabels = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        workspace
            .environment(\.colorScheme, .dark) // the viewfinder is always dark; sheets follow the system
            .photosPicker(isPresented: $vm.showPhotosPicker, selection: $pickerItems,
                          maxSelectionCount: 20, selectionBehavior: .ordered,
                          matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                vm.importFromLibrary(items)
                pickerItems = []
            }
            .fileImporter(isPresented: $vm.showFileImporter, allowedContentTypes: [.image, .movie],
                          allowsMultipleSelection: true) { result in
                vm.importFromFiles(result)
            }
            .task { vm.restoreLastSession() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { vm.saveSessionState() }
            }
            .sheet(isPresented: $vm.showAdjustments) { PhotoAdjustmentView(vm: vm) }
            .sheet(isPresented: $vm.showExport) { PhotoExportView(vm: vm) }
            .sheet(isPresented: $vm.showTrim) { VideoTrimView(vm: vm) }
            .sheet(isPresented: $vm.showTextSheet) { LiveTextSheet(vm: vm) }
            .appAlert(vm)
            .sensoryFeedback(.success, trigger: vm.importSuccessCount)
            .sensoryFeedback(.selection, trigger: vm.mode)
            .sensoryFeedback(.selection, trigger: vm.aspect)
            .sensoryFeedback(.selection, trigger: vm.adjustments.filter)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.flashPulse)
            .sensoryFeedback(.error, trigger: vm.alert?.id) { _, new in new != nil }
            .onChange(of: vm.flashPulse) { playFlash() }
            .onChange(of: vm.mode) { vm.modeChanged() }
            .onChange(of: vm.isControlPanelOpen) { _, open in
                if !open { vm.isEditingTopBar = false }
            }
            .environment(\.cameraReduceMotion, reduceMotion)
            .environment(\.cameraHighContrast, appHighContrast || systemContrast == .increased)
            .environment(\.cameraLargeLabels, largeLabels)
            .environment(\.cameraIconRotation, motion.iconRotation)
            .onAppear { motion.start() }
            .onDisappear { motion.stop() }
            .statusBarHidden()
    }

    private var workspace: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PhotoPreviewView(vm: vm, motion: motion)
                    VStack(spacing: 0) {
                        CameraStatusRow(vm: vm)
                        Spacer(minLength: 0)
                        CameraShutterControls(vm: vm)
                    }

                    if vm.photo?.livePhoto != nil {
                        LiveBadge(vm: vm)
                            .padding(.top, 58)
                            .padding(.leading, 12)
                            .transition(.opacity)
                    }

                    if vm.scopeMode != .off, let data = vm.scopeData {
                        ScopeView(mode: vm.scopeMode, data: data)
                            .padding(.top, vm.photo?.livePhoto != nil ? 98 : 58)
                            .padding(.leading, 12)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    // Picture-in-picture overview past 6x, top-right like the Camera app.
                    HStack {
                        Spacer()
                        ZoomMiniMap(vm: vm)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                    }
                    .padding(.top, 72)
                    .padding(.trailing, 14)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25),
                               value: vm.zoom >= FramingGeometry.miniMapThreshold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped() // keeps the zoom dial's dark disc inside the viewfinder

                CameraBottomBar(vm: vm)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1) // camera chrome has fixed geometry

            if vm.showEffectsPicker {
                EffectsPickerView(vm: vm)
                    .padding(.bottom, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            if vm.showStylesPad {
                StylesPadView(vm: vm)
                    .padding(.bottom, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            if vm.showFilterPicker {
                FilterPickerView(vm: vm)
                    .padding(.bottom, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            if vm.isControlPanelOpen {
                CameraControlPanel(vm: vm)
                    .padding(.bottom, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)

                // "Edit" sits top-left beside the Dynamic Island, as in the Camera app.
                VStack {
                    HStack {
                        TopBarEditButton(vm: vm)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 24)
                .padding(.top, 14)
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
                .zIndex(1)
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let seconds = vm.countdown {
                CountdownOverlay(seconds: seconds) { vm.cancelCountdown() }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if let toast = vm.toast {
                VStack {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .cameraGlass(.regular, in: Capsule())
                        .padding(.top, 12)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(4)
            }

            if vm.isRenderingEffect {
                LoadingOverlay(message: vm.effectMessage) { vm.cancelEffect() }
                    .transition(.opacity)
                    .zIndex(3)
            }

            if vm.isImporting {
                LoadingOverlay(message: vm.importMessage) { vm.cancelImport() }
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.isImporting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.countdown)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: vm.toast)
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
