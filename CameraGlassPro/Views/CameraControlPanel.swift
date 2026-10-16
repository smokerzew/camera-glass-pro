import SwiftUI

/// Expanded glass panel (the "more" button), modeled on the iOS 26 Camera controls sheet.
/// Scrolls only when it doesn't fit, so small iPhones keep part of the photo visible.
struct CameraControlPanel: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @AppStorage(SettingsKey.gridStyle) private var gridStyle = GridStyle.off
    @AppStorage(SettingsKey.showLevel) private var showLevel = false
    @AppStorage(SettingsKey.showCenter) private var showCenter = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(showsIndicators: false) { content }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: 520)
        .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("More controls")
    }

    private var content: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: columns, spacing: 16) {
                PanelControlButton(systemImage: vm.flash.systemImage, title: "FLASH",
                                   isActive: vm.flash != .off, stateDescription: vm.flash.label,
                                   hint: "Visual flash effect only") { vm.flash = vm.flash.next }

                PanelControlButton(systemImage: vm.livePreference ? "livephoto" : "livephoto.slash", title: "LIVE",
                                   isActive: vm.livePreference,
                                   hint: "Shows a LIVE badge only") { vm.livePreference.toggle() }

                PanelControlButton(systemImage: "timer", title: "TIMER",
                                   value: vm.timer == .off ? nil : vm.timer.label,
                                   isActive: vm.timer != .off, stateDescription: vm.timer.label,
                                   hint: "Delays opening the photo picker") { vm.timer = vm.timer.next }

                PanelControlButton(systemImage: vm.adjustments.nightLook ? "moon.fill" : "moon", title: "NIGHT",
                                   isActive: vm.adjustments.nightLook,
                                   hint: "Lifts shadows and reduces noise") { vm.setNightLook(!vm.adjustments.nightLook) }
                    .disabled(vm.photo == nil)

                PanelControlButton(systemImage: "squareshape.split.3x3", title: "GRID",
                                   isActive: gridStyle != .off, stateDescription: gridStyle.label,
                                   hint: "Cycles off, rule of thirds and fine grid") { gridStyle = gridStyle.next }

                PanelControlButton(systemImage: "level", title: "LEVEL", isActive: showLevel,
                                   hint: "Shows a composition level guide") { showLevel.toggle() }

                PanelControlButton(systemImage: "plus.viewfinder", title: "CENTER", isActive: showCenter,
                                   hint: "Shows a center crosshair") { showCenter.toggle() }

                PanelControlButton(systemImage: "aspectratio", title: "ASPECT",
                                   value: vm.aspect == .original ? nil : vm.aspect.rawValue,
                                   isActive: vm.aspect != .original, stateDescription: vm.aspect.label,
                                   hint: "Cycles original, 4:3, 16:9 and 1:1 preview framing") { vm.aspect = vm.aspect.next }
            }

            if vm.photo != nil {
                PanelSlider(
                    title: "Exposure", systemImage: "plusminus.circle",
                    value: Binding(get: { vm.adjustments.exposure }, set: { vm.setAdjustment(.exposure, to: $0) }),
                    range: AdjustmentParameter.exposure.range,
                    valueText: AdjustmentParameter.exposure.format(vm.adjustments.exposure)
                )
                PanelSlider(
                    title: "Zoom", systemImage: "plus.magnifyingglass",
                    value: Binding(get: { Double(vm.zoom) }, set: { vm.setZoom(CGFloat($0)) }),
                    range: Double(ZoomLimits.minimum)...Double(ZoomLimits.maximum),
                    valueText: ZoomLimits.label(for: vm.zoom) + "×"
                )
            }

            HStack(spacing: 10) {
                PanelActionButton(title: "Adjust", systemImage: "slider.horizontal.3") { vm.showAdjustments = true }
                    .disabled(vm.photo == nil)
                PanelActionButton(title: "Files", systemImage: "folder") { vm.showFileImporter = true }
                PanelActionButton(title: "Reset", systemImage: "arrow.counterclockwise") {
                    withAnimation(.spring(duration: 0.35)) { vm.resetFraming() }
                }
                .disabled(vm.photo == nil)
                .accessibilityHint("Restores default zoom and aspect. The photo and edits are kept.")
            }
        }
    }
}

private struct PanelSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 22)
                .accessibilityHidden(true)
            Slider(value: $value, in: range)
                .tint(.yellow)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 54, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct PanelActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.black.opacity(0.3), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
