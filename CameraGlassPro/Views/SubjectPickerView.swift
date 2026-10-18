import SwiftUI

/// SUBJECT pop-up: Color Splash and Background Swap, using the same on-device subject detection as
/// Portrait. Same glass card, grabber and captions as the other pop-ups.
struct SubjectPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var region: PhotoRegion = .subject

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            HStack {
                Text("SUBJECT")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if vm.isFindingSubject {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Button("Done") { close() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 6)

            Toggle(isOn: Binding(get: { vm.adjustments.colorSplash }, set: { vm.setColorSplash($0) })) {
                Label("Color Splash", systemImage: "paintpalette")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(.yellow)
            .padding(.horizontal, 6)
            .accessibilityHint("Keeps the subject in color and turns the background black and white")

            VStack(alignment: .leading, spacing: 8) {
                Text("BACKGROUND")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(BackgroundStyle.allCases) { style in
                            PanelControlButton(
                                systemImage: style.systemImage, title: style.label,
                                isActive: vm.adjustments.background == style,
                                hint: style == .photo ? "Choose a photo to put behind the subject" : "Puts this behind the subject"
                            ) {
                                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { vm.setBackground(style) }
                            }
                            .frame(width: 76)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            regionEdits

            Text("Sky is found on-device from color, smoothness and position, so a plain bright wall near the top can count as sky. "
                 + "Subject works with people, pets and objects, using on-device subject detection. Combine with Portrait for depth blur and lighting.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: 520)
        .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .offset(y: max(0, dragOffset))
        .simultaneousGesture(
            DragGesture()
                .onChanged { if $0.startLocation.y < 44 { dragOffset = $0.translation.height } }
                .onEnded { value in
                    if value.startLocation.y < 44, value.translation.height > 80 { close() }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
                }
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Subject")
        .accessibilityAction(.escape) { close() }
    }

    /// Brightness, saturation and warmth for just the subject or just the background.
    private var regionEdits: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("ADJUST")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.7))
                ForEach(PhotoRegion.allCases) { item in
                    let selected = region == item
                    Button { region = item } label: {
                        Text(item.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? Color.yellow : .white)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .cameraGlass(selected ? .selected : .interactive, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adjust \(item.label.lowercased())")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button("Reset") { vm.resetRegionEdits() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasRegionEdits ? Color.yellow : .white.opacity(0.4))
                    .disabled(!hasRegionEdits)
            }
            ForEach(RegionEdit.Control.allCases) { control in
                let value = vm.adjustments[region][keyPath: control.keyPath]
                HStack(spacing: 10) {
                    Text(control.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 84, alignment: .leading)
                    Slider(value: Binding(get: { vm.adjustments[region][keyPath: control.keyPath] },
                                          set: { vm.setRegionEdit(region, control, to: $0) }), in: -1...1)
                        .tint(.yellow)
                        .accessibilityLabel("\(region.label) \(control.label)")
                        .accessibilityValue(String(Int((value * 100).rounded())))
                    Text(value == 0 ? "0" : String(format: "%+d", Int((value * 100).rounded())))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(value == 0 ? Color.white.opacity(0.6) : Color.yellow)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var hasRegionEdits: Bool {
        !vm.adjustments.subjectEdit.isNeutral || !vm.adjustments.backgroundEdit.isNeutral || !vm.adjustments.skyEdit.isNeutral
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.showSubjectPicker = false }
    }
}
