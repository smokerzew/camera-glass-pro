import PhotosUI
import SwiftUI

/// Full-screen workspace laid out like the iOS 27 Camera app: the photo fills the viewfinder,
/// status icons float over its top, zoom/shutter controls over its bottom, and a black bar holds
/// the thumbnail, the mode capsule and a round action button.
struct CameraWorkspaceView: View {
    @State private var vm = CameraWorkspaceViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var flashOpacity = 0.0

    @AppStorage(SettingsKey.reduceMotion) private var appReduceMotion = false
    @AppStorage(SettingsKey.highContrast) private var appHighContrast = false
    @AppStorage(SettingsKey.largeLabels) private var largeLabels = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        workspace
            .environment(\.colorScheme, .dark) // the viewfinder is always dark; sheets follow the system
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
            .appAlert(vm)
            .sensoryFeedback(.success, trigger: vm.importSuccessCount)
            .sensoryFeedback(.selection, trigger: vm.mode)
            .sensoryFeedback(.selection, trigger: vm.aspect)
            .sensoryFeedback(.selection, trigger: vm.adjustments.filter)
            .sensoryFeedback(.impact(weight: .light), trigger: vm.flashPulse)
            .sensoryFeedback(.error, trigger: vm.alert?.id) { _, new in new != nil }
            .onChange(of: vm.flashPulse) { playFlash() }
            .environment(\.cameraReduceMotion, reduceMotion)
            .environment(\.cameraHighContrast, appHighContrast || systemContrast == .increased)
            .environment(\.cameraLargeLabels, largeLabels)
            .statusBarHidden()
    }

    private var workspace: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    PhotoPreviewView(vm: vm)
                    VStack(spacing: 0) {
                        CameraStatusRow(vm: vm)
                        Spacer(minLength: 0)
                        CameraShutterControls(vm: vm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CameraBottomBar(vm: vm)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1) // camera chrome has fixed geometry

            if vm.isControlPanelOpen {
                CameraControlPanel(vm: vm)
                    .padding(.bottom, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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

            if vm.isImporting {
                LoadingOverlay(message: vm.importMessage) { vm.cancelImport() }
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.isImporting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.countdown)
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
