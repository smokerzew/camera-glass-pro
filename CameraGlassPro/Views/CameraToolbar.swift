import SwiftUI

/// Compact top bar: settings and real file info on the left, camera-style toggles in one glass capsule.
/// Timer, grid and the rest live in the expanded panel to keep this row uncluttered.
struct CameraToolbar: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemImage: "gearshape", label: "Settings") {
                vm.showSettings = true
            }

            if let photo = vm.photo {
                GlassPill(text: "\(photo.formatLabel) \(Int(photo.megapixels.rounded()))MP")
                    .accessibilityLabel("Imported file: \(photo.formatLabel), \(Int(photo.megapixels.rounded())) megapixels")
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            GlassGroup(spacing: 8) {
                HStack(spacing: 0) {
                    CapsuleIconButton(
                        systemImage: vm.flash.systemImage,
                        label: "Flash effect",
                        hint: "Visual effect only. Cycles off, auto and on.",
                        value: vm.flash.label,
                        isActive: vm.flash != .off
                    ) { vm.flash = vm.flash.next }

                    CapsuleIconButton(
                        systemImage: vm.adjustments.nightLook ? "moon.fill" : "moon",
                        label: "Night Look",
                        hint: "Lifts shadows and reduces noise in the preview and edited copy.",
                        value: vm.adjustments.nightLook ? "On" : "Off",
                        isActive: vm.adjustments.nightLook
                    ) { vm.setNightLook(!vm.adjustments.nightLook) }
                    .disabled(vm.photo == nil)

                    CapsuleIconButton(
                        systemImage: vm.livePreference ? "livephoto" : "livephoto.slash",
                        label: "Live preference",
                        hint: "Shows a LIVE badge. Imported photos stay still images.",
                        value: vm.livePreference ? "On" : "Off",
                        isActive: vm.livePreference
                    ) { vm.livePreference.toggle() }

                    CapsuleIconButton(
                        systemImage: "circle.grid.3x3.fill",
                        label: "More controls",
                        hint: "Shows grid, timer, aspect, exposure and zoom controls.",
                        value: vm.isControlPanelOpen ? "Expanded" : "Collapsed",
                        isActive: vm.isControlPanelOpen
                    ) {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.18)) {
                            vm.isControlPanelOpen.toggle()
                        }
                    }
                }
                .padding(.horizontal, 4)
                .cameraGlass(.regular, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}
