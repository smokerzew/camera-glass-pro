import SwiftUI

/// SUBJECT pop-up: Color Splash and Background Swap, using the same on-device subject detection as
/// Portrait. Same glass card, grabber and captions as the other pop-ups.
struct SubjectPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var region: PhotoRegion = .subject
    @State private var page: Page = .style

    /// Three short pages instead of one long card.
    enum Page: String, CaseIterable { case style, adjust, create }

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
                // The Adjust page has its own Reset next to its region buttons.
                if page == .create {
                    AreaShuffleButton(vm: vm, area: .subjectCreate)
                }
                if page != .adjust {
                    AreaResetButton(vm: vm, area: page == .style ? .subjectStyle : .subjectCreate)
                        .padding(.trailing, 12)
                }
                if vm.isFindingSubject {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Button("Done") { close() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 6)

            GlassTabs(tabs: Page.allCases, selection: $page) { $0.rawValue.capitalized }
                .padding(.horizontal, 6)

            PagedStack(pages: Page.allCases, selection: page) { page in
                switch page {
                case .style: stylePage
                case .adjust: regionEdits
                case .create: createPage
                }
            }
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

    /// Color Splash and Background Swap.
    private var stylePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Fix what counts as the subject (stray hair, a missed arm) with a brush.
            Button { vm.showMaskEditor = true } label: {
                Label(vm.adjustments.maskStrokes.isEmpty ? "Refine Subject" : "Refine Subject (\(vm.adjustments.maskStrokes.count))",
                      systemImage: "paintbrush.pointed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .cameraGlass(.interactive, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.photo == nil)
            .padding(.horizontal, 6)
            Toggle(isOn: Binding(get: { vm.adjustments.colorSplash }, set: { vm.setColorSplash($0) })) {
                Label("Color Splash", systemImage: "paintpalette")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(.yellow)
            .padding(.horizontal, 6)
            .accessibilityHint("Keeps the subject in color and turns the background black and white")

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
            if vm.adjustments.background == .blur {
                // Kinds of background blur, and how strong.
                GlassTabs(tabs: BackgroundBlurKind.allCases, selection: Binding(get: { vm.adjustments.backgroundBlurKind },
                                                                              set: { vm.setBackgroundBlurKind($0) })) { $0.label }
                    .padding(.horizontal, 6)
                GlassSliderRow(title: "Blur", value: vm.adjustments.backgroundBlurAmount) {
                    vm.setEffect(\.backgroundBlurAmount, to: min(max($0, 0), 1))
                }
                .padding(.horizontal, 6)
            }
            skyReplaceRow
        }
    }

    /// Sky Replace: a new sky where the sky is found, with matching light on the land.
    private var skyReplaceRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SKY")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
            GlassTabs(tabs: SkyReplacement.allCases, selection: Binding(get: { vm.adjustments.skyReplace },
                                                                      set: { vm.setSkyReplace($0) })) { $0.label }
            if vm.adjustments.skyReplace != .none {
                GlassSliderRow(title: "Sky Amount", value: vm.adjustments.skyReplaceAmount) {
                    vm.setEffect(\.skyReplaceAmount, to: min(max($0, 0), 1))
                }
                if vm.adjustments.skyReplace == .photo {
                    Button("Change Sky Photo") { vm.chooseSkyPhoto() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    /// Stickers and 3D video made from the subject.
    private var createPage: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                PanelControlButton(systemImage: "face.dashed", title: "STICKER",
                                   hint: "Saves the subject as a transparent sticker to Photos and copies it") {
                    vm.makeSticker()
                }
                .frame(maxWidth: .infinity)
                PanelControlButton(systemImage: "cube.transparent", title: "3D VIDEO",
                                   hint: "Makes a short clip where the subject floats in front of a moving background") {
                    vm.makeParallaxVideo()
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(vm.photo == nil)
            .opacity(vm.photo == nil ? 0.45 : 1)
            GlassSliderRow(title: "Dispersion", value: vm.adjustments.dispersion) {
                vm.setEffect(\.dispersion, to: min(max($0, 0), 1))
            }
            GlassSliderRow(title: "Particle Size", value: vm.adjustments.dispersionSize) {
                vm.setEffect(\.dispersionSize, to: min(max($0, 0), 1))
            }
            .opacity(vm.adjustments.dispersion > 0 ? 1 : 0.4)
            .disabled(vm.adjustments.dispersion == 0)
            GlassSliderRow(title: "Direction", value: vm.adjustments.dispersionAngle, range: 0...360,
                           display: { "\(Int($0.rounded()))°" }) {
                vm.setEffect(\.dispersionAngle, to: min(max($0, 0), 360))
            }
            .opacity(vm.adjustments.dispersion > 0 ? 1 : 0.4)
            .disabled(vm.adjustments.dispersion == 0)
            Text("Sticker saves a see-through PNG to Photos and copies it for Messages. 3D Video opens as a new item you can save. "
                 + "Dispersion breaks the subject into particles that drift the way Direction points (0° is right, 90° is up).")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
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
            if region == .sky {
                Text("Sky is found on-device from color, smoothness and position, so a plain bright wall near the top can count as sky.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
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
