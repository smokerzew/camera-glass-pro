import SwiftUI

/// The ⠿ controls sheet, laid out like the iOS 27 Camera app: grabber and a 3-column grid of every
/// `CameraControl` (including GRID and LEVEL). In Edit mode each control shows +/− and tapping it
/// pins or unpins it in the top bar instead of running it.
struct CameraControlPanel: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var group: PanelGroup = .edit

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .accessibilityHidden(true)

            if vm.isEditingTopBar {
                Text("Tap + to add a control to the top bar, − to remove it.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

            GlassTabs(tabs: PanelGroup.allCases, selection: $group) { $0.rawValue.capitalized }
                .padding(.bottom, 14)

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
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: vm.isEditingTopBar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(vm.isEditingTopBar ? "Edit top bar" : "More controls")
        .accessibilityAction(.escape) { vm.isControlPanelOpen = false }
    }

    private var content: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(CameraControl.allCases.filter { $0.group == group }) { control in
                    let unavailable = !vm.isEditingTopBar && !vm.isAvailable(control)
                    PanelControlButton(
                        systemImage: vm.symbol(for: control),
                        title: control.title,
                        value: vm.valueText(for: control),
                        isActive: vm.isActive(control),
                        stateDescription: vm.stateDescription(for: control),
                        hint: vm.hint(for: control),
                        pinnedInTopBar: vm.isEditingTopBar ? vm.isInTopBar(control) : nil
                    ) {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                            if vm.isEditingTopBar { vm.toggleTopBar(control) } else { vm.perform(control) }
                        }
                    }
                    .disabled(unavailable)
                    .opacity(unavailable ? 0.45 : 1)
                }
            }

            if vm.isExposureDialVisible, vm.hasMedia, !vm.isEditingTopBar {
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

/// "Edit" / "Done" capsule shown top-left while the panel is open (as in the Camera app).
struct TopBarEditButton: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { vm.isEditingTopBar.toggle() }
        } label: {
            Text(vm.isEditingTopBar ? "Done" : "Edit")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(vm.isEditingTopBar ? Color.yellow : .white)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .cameraGlass(.interactive, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(vm.isEditingTopBar ? "Done editing top bar" : "Edit top bar")
        .accessibilityHint("Choose which controls appear in the top bar")
    }
}
