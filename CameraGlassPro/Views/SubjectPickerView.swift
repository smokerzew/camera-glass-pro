import SwiftUI

/// SUBJECT pop-up: Color Splash and Background Swap, using the same on-device subject detection as
/// Portrait. Same glass card, grabber and captions as the other pop-ups.
struct SubjectPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var region: PhotoRegion = .subject
    @State private var page: Page = .style
    @State private var showMoreDissolve = false

    /// Three short pages instead of one long card.
    enum Page: String, CaseIterable { case style, adjust, effects, create }

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
                if page == .create || page == .effects {
                    AreaShuffleButton(vm: vm, area: page == .create ? .subjectCreate : .subjectEffects)
                }
                if page != .adjust {
                    AreaResetButton(vm: vm, area: page == .style ? .subjectStyle : (page == .create ? .subjectCreate : .subjectEffects))
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
                case .effects: effectsPage
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
            if vm.video != nil { cinematicRow }
        }
    }

    /// Neon outline, aura, silhouette and drop shadow.
    private var effectsPage: some View {
        let a = vm.adjustments
        return VStack(spacing: 10) {
            GlassSliderRow(title: "Neon Outline", value: a.neonOutline) { vm.setEffect(\.neonOutline, to: min(max($0, 0), 1)) }
            hueRow("Neon Color", \.neonHue, enabled: a.neonOutline > 0)
            GlassSliderRow(title: "Aura", value: a.aura) { vm.setEffect(\.aura, to: min(max($0, 0), 1)) }
            hueRow("Aura Color", \.auraHue, enabled: a.aura > 0)
            GlassSliderRow(title: "Silhouette", value: a.silhouette) { vm.setEffect(\.silhouette, to: min(max($0, 0), 1)) }
            GlassSliderRow(title: "Shadow", value: a.subjectShadow) { vm.setEffect(\.subjectShadow, to: min(max($0, 0), 1)) }
            Text("Neon traces a glowing line around the subject; Aura is a colored glow behind it; Silhouette darkens it "
                 + "against the background; Shadow casts a soft shadow behind it.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }

    private func hueRow(_ title: String, _ path: WritableKeyPath<PhotoAdjustmentState, Double>, enabled: Bool) -> some View {
        GlassSliderRow(title: title, value: vm.adjustments[keyPath: path], range: 0...360,
                       display: { "\(Int($0.rounded()))°" }) { vm.setEffect(path, to: min(max($0, 0), 360)) }
            .opacity(enabled ? 1 : 0.4)
            .disabled(!enabled)
    }

    /// CINEMATIC focus points made by tapping the video in CINEMATIC mode.
    private var cinematicRow: some View {
        let count = vm.adjustments.cinematicFocus.count
        return HStack(spacing: 8) {
            Text("CINEMATIC FOCUS")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
            Text(count == 0 ? "Tap the video in CINEMATIC mode" : "\(count) point\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(count == 0 ? .white.opacity(0.6) : .yellow)
            Spacer()
            if count > 0 {
                Button("Clear") { vm.clearCinematicFocus() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 6)
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
            GlassTabs(tabs: DispersionStyle.allCases, selection: Binding(get: { vm.adjustments.dispersionStyle },
                                                                       set: { vm.setDispersionStyle($0) })) { $0.label }
            if vm.adjustments.dispersionStyle == .pieces { piecesControls } else { dissolveControls }
            Text("Sticker saves a see-through PNG to Photos and copies it for Messages. 3D Video opens as a new item you can save. "
                 + (vm.adjustments.dispersionStyle == .pieces
                    ? "Pieces breaks the subject into chunks that drift the way Direction points (0° is right, 90° is up)."
                    : "Particle Dissolve turns the subject into fine particles of its own colors, drifting the way Direction points."))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }

    private var piecesControls: some View {
        let on = vm.adjustments.dispersion > 0
        return VStack(spacing: 10) {
            GlassSliderRow(title: "Dispersion", value: vm.adjustments.dispersion) {
                vm.setEffect(\.dispersion, to: min(max($0, 0), 1))
            }
            Group {
                GlassSliderRow(title: "Particle Size", value: vm.adjustments.dispersionSize) {
                    vm.setEffect(\.dispersionSize, to: min(max($0, 0), 1))
                }
                GlassSliderRow(title: "Direction", value: vm.adjustments.dispersionAngle, range: 0...360,
                               display: { "\(Int($0.rounded()))°" }) {
                    vm.setEffect(\.dispersionAngle, to: min(max($0, 0), 360))
                }
            }
            .opacity(on ? 1 : 0.4)
            .disabled(!on)
        }
    }

    /// Particle Dissolve: how much, direction, spread and size up front; density and softness under More.
    private var dissolveControls: some View {
        let a = vm.adjustments
        let on = a.dissolveAmount > 0
        return VStack(spacing: 10) {
            GlassSliderRow(title: "Dissolve", value: a.dissolveAmount) { vm.setEffect(\.dissolveAmount, to: min(max($0, 0), 1)) }
            Group {
                GlassSliderRow(title: "Direction", value: a.dissolveAngle, range: 0...360,
                               display: { "\(Int($0.rounded()))°" }) { vm.setEffect(\.dissolveAngle, to: min(max($0, 0), 360)) }
                GlassSliderRow(title: "Spread", value: a.dissolveSpread) { vm.setEffect(\.dissolveSpread, to: min(max($0, 0), 1)) }
                GlassSliderRow(title: "Echo", value: a.dissolveEcho) { vm.setEffect(\.dissolveEcho, to: min(max($0, 0), 1)) }
                GlassSliderRow(title: "Particle Size", value: a.dissolveSize) { vm.setEffect(\.dissolveSize, to: min(max($0, 0), 1)) }
                Button(showMoreDissolve ? "Fewer Settings" : "More Settings") {
                    withAnimation(.easeInOut(duration: 0.2)) { showMoreDissolve.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
                if showMoreDissolve {
                    GlassSliderRow(title: "Density", value: a.dissolveDensity) { vm.setEffect(\.dissolveDensity, to: min(max($0, 0), 1)) }
                    GlassSliderRow(title: "Softness", value: a.dissolveSoftness) { vm.setEffect(\.dissolveSoftness, to: min(max($0, 0), 1)) }
                }
            }
            .opacity(on ? 1 : 0.4)
            .disabled(!on)
        }
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
