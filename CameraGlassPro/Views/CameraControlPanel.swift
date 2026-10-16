import SwiftUI

/// The ⠿ controls sheet, laid out like the iOS 27 Camera app: grabber, a 3-column grid of
/// FLASH / LIVE / ASPECT / TIMER / EXPOSURE / STYLES / FILTER / DEPTH / NIGHT MODE, and FORMAT centered below.
/// Every control does something real in this app (see each hint).
struct CameraControlPanel: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @AppStorage(SettingsKey.exportFormat) private var exportFormat = ExportFormat.jpeg
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .accessibilityHidden(true)

            ViewThatFits(in: .vertical) {
                content
                ScrollView(showsIndicators: false) { content }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: 520)
        .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 38, style: .continuous))
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                        if value.translation.height > 80 { vm.isControlPanelOpen = false }
                        dragOffset = 0
                    }
                }
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("More controls")
        .accessibilityAction(.escape) { vm.isControlPanelOpen = false }
    }

    private var content: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: columns, spacing: 18) {
                PanelControlButton(systemImage: vm.flash == .off ? "bolt.slash" : vm.flash.systemImage, title: "FLASH",
                                   isActive: vm.flash != .off, stateDescription: vm.flash.label,
                                   hint: "Visual flash effect only") { vm.flash = vm.flash.next }

                PanelControlButton(systemImage: vm.livePreference ? "livephoto" : "livephoto.slash", title: "LIVE",
                                   isActive: vm.livePreference,
                                   hint: "Shows Live as on; imported photos stay still images") { vm.livePreference.toggle() }

                PanelControlButton(systemImage: "aspectratio", title: "ASPECT",
                                   value: vm.aspect == .original ? nil : vm.aspect.rawValue,
                                   isActive: vm.aspect != .original, stateDescription: vm.aspect.label,
                                   hint: "Cycles full screen, 4:3, 16:9 and 1:1 framing") { vm.aspect = vm.aspect.next }

                PanelControlButton(systemImage: "timer", title: "TIMER",
                                   value: vm.timer == .off ? nil : vm.timer.label,
                                   isActive: vm.timer != .off, stateDescription: vm.timer.label,
                                   hint: "Delays opening the photo picker") { vm.timer = vm.timer.next }

                PanelControlButton(systemImage: "plusminus", title: "EXPOSURE",
                                   isActive: vm.isExposureDialVisible || vm.adjustments.exposure != 0,
                                   stateDescription: AdjustmentParameter.exposure.format(vm.adjustments.exposure),
                                   hint: "Shows the exposure slider") {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { vm.isExposureDialVisible.toggle() }
                }
                .disabled(vm.photo == nil)

                PanelControlButton(systemImage: "square.3.layers.3d", title: "STYLES",
                                   isActive: vm.hasEdits, stateDescription: vm.hasEdits ? "Edited" : "No edits",
                                   hint: "Opens light and color adjustments") { vm.showAdjustments = true }
                    .disabled(vm.photo == nil)

                PanelControlButton(systemImage: "camera.filters", title: "FILTER",
                                   isActive: vm.adjustments.filter != .none,
                                   stateDescription: vm.adjustments.filter.label,
                                   hint: "Cycles Vivid, Mono, Noir, Chrome, Fade and Instant") { vm.cycleFilter() }
                    .disabled(vm.photo == nil)

                PanelControlButton(systemImage: "f.cursive", title: "DEPTH",
                                   isActive: vm.depthEffect,
                                   hint: "Preview-only depth look with a soft vignette") { vm.depthEffect.toggle() }
                    .disabled(vm.photo == nil)

                PanelControlButton(systemImage: vm.adjustments.nightLook ? "moon.fill" : "moon", title: "NIGHT MODE",
                                   isActive: vm.adjustments.nightLook,
                                   hint: "Lifts shadows and reduces noise") { vm.setNightLook(!vm.adjustments.nightLook) }
                    .disabled(vm.photo == nil)
            }

            PanelControlButton(systemImage: "photo", title: "FORMAT",
                               value: exportFormat == .heic ? "HEIF" : exportFormat.label,
                               stateDescription: exportFormat.label,
                               hint: "Cycles the export format: JPEG, HEIF, PNG") {
                let all = ExportFormat.allCases
                exportFormat = all[((all.firstIndex(of: exportFormat) ?? 0) + 1) % all.count]
            }
            .frame(maxWidth: 120)

            if vm.isExposureDialVisible, vm.photo != nil {
                HStack(spacing: 10) {
                    Image(systemName: "plusminus").foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
                    Slider(
                        value: Binding(get: { vm.adjustments.exposure }, set: { vm.setAdjustment(.exposure, to: $0) }),
                        in: AdjustmentParameter.exposure.range, step: 0.1
                    )
                    .tint(.yellow)
                    .accessibilityLabel("Exposure")
                    .accessibilityValue(AdjustmentParameter.exposure.format(vm.adjustments.exposure))
                    Text(String(format: "%+.1f", vm.adjustments.exposure))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.yellow)
                        .frame(minWidth: 40, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 6)
                .transition(.opacity)
            }
        }
    }
}
