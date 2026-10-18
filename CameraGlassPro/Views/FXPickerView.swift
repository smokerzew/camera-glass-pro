import SwiftUI

/// FX pop-up: Blur (speed blur, tilt-shift), Blend (double exposure) and Privacy (blur or pixelate faces,
/// or paint the areas to hide), plus Shuffle. Same glass card, grabber and captions as the other pop-ups.
struct FXPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var page: Page = .blur

    enum Page: String, CaseIterable { case blur, blend, privacy }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            HStack {
                Text("FX")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button { vm.shuffleLook() } label: {
                    Label("Shuffle", systemImage: "dice")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHint("Tries a random filter, grain and vignette")
                Button("Done") { close() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 6)

            GlassTabs(tabs: Page.allCases, selection: $page) { $0.rawValue.capitalized }
                .padding(.horizontal, 6)

            PagedStack(pages: Page.allCases, selection: page) { page in
                switch page {
                case .blur: blurPage
                case .blend: blendPage
                case .privacy: privacyPage
                }
            }
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
        .accessibilityLabel("FX")
        .accessibilityAction(.escape) { close() }
    }

    private var blurPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSliderRow(title: "Speed Blur", value: vm.adjustments.speedBlur) { vm.setEffect(\.speedBlur, to: $0) }
            GlassSliderRow(title: "Direction", value: vm.adjustments.speedAngle, range: 0...180,
                           display: { "\(Int($0.rounded()))°" }) { vm.setEffect(\.speedAngle, to: $0) }
                .opacity(vm.adjustments.speedBlur > 0 ? 1 : 0.4)
                .disabled(vm.adjustments.speedBlur == 0)
            GlassSliderRow(title: "Tilt-Shift", value: vm.adjustments.tiltShift) { vm.setEffect(\.tiltShift, to: $0) }
            GlassSliderRow(title: "Focus Band", value: vm.adjustments.tiltShiftPosition,
                           display: { "\(Int(($0 * 100).rounded()))%" }) { vm.setEffect(\.tiltShiftPosition, to: $0) }
                .opacity(vm.adjustments.tiltShift > 0 ? 1 : 0.4)
                .disabled(vm.adjustments.tiltShift == 0)
            note("Speed Blur streaks the background behind the subject. Tilt-Shift makes scenes look like tiny models; move the sharp band to where it should stay in focus.")
        }
    }

    private var blendPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSliderRow(title: "Double Exposure", value: vm.adjustments.doubleExposure) { vm.setDoubleExposure($0) }
            Button { vm.chooseDoubleExposurePhoto() } label: {
                Label(vm.customBackground == nil ? "Choose Second Photo" : "Change Second Photo", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .cameraGlass(.interactive, in: Capsule())
            }
            .buttonStyle(.plain)
            note("The second photo shows through the subject and the background fades to white, like a film poster. Without a subject it blends over the whole picture. It's the same photo Background Swap uses.")
        }
    }

    private var privacyPage: some View {
        let target = vm.adjustments.redactionTarget
        return VStack(alignment: .leading, spacing: 12) {
            // Hide faces or what you draw, one or the other.
            GlassTabs(tabs: RedactionTarget.allCases, selection: Binding(get: { vm.adjustments.redactionTarget },
                                                                       set: { vm.setRedactionTarget($0) })) { $0.label }
            if target == .faces {
                GlassTabs(tabs: Redaction.allCases, selection: Binding(get: { vm.adjustments.faceRedaction },
                                                                     set: { vm.setFaceRedaction($0) })) { $0.label }
            } else {
                HStack(spacing: 8) {
                    Button { vm.showRedactionEditor = true } label: {
                        Label("Draw to Blur or Pixelate", systemImage: "scribble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .cameraGlass(.interactive, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    if !vm.adjustments.redactionStrokes.isEmpty {
                        Text("\(vm.adjustments.redactionStrokes.count) painted")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            GlassSliderRow(title: "Strength", value: vm.adjustments.redactionStrength) {
                vm.setEffect(\.redactionStrength, to: min(max($0, 0), 1))
            }
            .opacity(vm.isActive(.fx) ? 1 : 0.4)
            note(target == .faces
                 ? "Every face found on-device is covered completely. Switch to Drawing to hide only what you paint instead."
                 : "Only what you paint is hidden; faces are left as they are. Your face setting comes back if you switch to Faces.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.showFXPicker = false }
    }
}
