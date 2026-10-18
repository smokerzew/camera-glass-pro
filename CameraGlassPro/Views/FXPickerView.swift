import SwiftUI

/// FX pop-up: Blur (speed blur, tilt-shift), Blend (double exposure) and Privacy (blur or pixelate faces,
/// or paint the areas to hide), plus Shuffle. Same glass card, grabber and captions as the other pop-ups.
struct FXPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var page: Page = .blur
    @State private var art: ArtEffect = .hologram
    @State private var light: LightEffect = .blinds
    @State private var retro: RetroEffect = .vhs

    enum Page: String, CaseIterable { case blur, blend, ghost, art, light, retro, privacy }

    /// The Reset button clears only the page that's showing.
    private var resetArea: ResetArea {
        switch page {
        case .blur: .fxBlur
        case .blend: .fxBlend
        case .ghost: .fxGhost
        case .art: .fxArt
        case .light: .fxLight
        case .retro: .fxRetro
        case .privacy: .fxPrivacy
        }
    }

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
                AreaResetButton(vm: vm, area: resetArea)
                    .padding(.trailing, 12)
                // Shuffles only the page that's showing (no shuffle for Privacy).
                if PhotoAdjustmentState.canShuffle(resetArea) {
                    AreaShuffleButton(vm: vm, area: resetArea)
                }
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
                case .ghost: ghostPage
                case .art: artPage
                case .light: lightPage
                case .retro: retroPage
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
            Divider().overlay(Color.white.opacity(0.2))
            // Match Look: copy another photo's colors and tones.
            HStack(spacing: 8) {
                Button { vm.showMatchPhotoPicker = true } label: {
                    Label(vm.adjustments.lookMatch == nil ? "Match Look of a Photo" : "Change Reference",
                          systemImage: "eyedropper.halffull")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .cameraGlass(.interactive, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copies the colors and tones of a photo you choose")
                if vm.adjustments.lookMatch != nil {
                    Button("Remove") { vm.removeLookMatch() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
            if let match = vm.adjustments.lookMatch {
                GlassSliderRow(title: "Match Amount", value: match.amount) { vm.setLookMatchAmount($0) }
            }
            note("The second photo shows through the subject and the background fades to white, like a film poster. Without a subject it blends over the whole picture. It's the same photo Background Swap uses. Match Look copies a reference photo's colors and tones.")
        }
    }

    /// A see-through copy of the subject or the whole photo, moved in any direction.
    private var ghostPage: some View {
        let a = vm.adjustments
        let on = a.ghostOpacity > 0
        return VStack(alignment: .leading, spacing: 12) {
            GlassTabs(tabs: GhostTarget.allCases, selection: Binding(get: { vm.adjustments.ghostTarget },
                                                                   set: { vm.setGhostTarget($0) })) { $0.label }
            GlassSliderRow(title: "Ghost", value: a.ghostOpacity) { vm.setEffect(\.ghostOpacity, to: min(max($0, 0), 1)) }
            Group {
                GlassSliderRow(title: "Distance", value: a.ghostDistance) { vm.setEffect(\.ghostDistance, to: min(max($0, 0), 1)) }
                GlassSliderRow(title: "Direction", value: a.ghostAngle, range: 0...360,
                               display: { "\(Int($0.rounded()))°" }) { vm.setEffect(\.ghostAngle, to: min(max($0, 0), 360)) }
                if a.ghostTarget == .subject {
                    Toggle(isOn: Binding(get: { vm.adjustments.ghostHideOriginal }, set: { vm.setGhostHideOriginal($0) })) {
                        Text("HIDE ORIGINAL")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .tint(.yellow)
                }
            }
            .opacity(on ? 1 : 0.4)
            .disabled(!on)
            note(a.ghostTarget == .subject
                 ? "A see-through copy of the subject, moved the way Direction points (0° right, 90° up). Hide Original leaves only the ghost."
                 : "A see-through copy of the whole photo laid over it, like a double image.")
        }
    }

    /// Hologram, Thermal / Night Vision, Pixel Sort, Orbit clones and Melt, one at a time.
    private var artPage: some View {
        let a = vm.adjustments
        return VStack(alignment: .leading, spacing: 12) {
            GlassTabs(tabs: ArtEffect.allCases, selection: $art) { $0.label }
            PagedStack(pages: ArtEffect.allCases, selection: art) { effect in
                VStack(alignment: .leading, spacing: 12) {
                    switch effect {
                    case .hologram:
                        GlassSliderRow(title: "Hologram", value: a.hologram) { vm.setEffect(\.hologram, to: min(max($0, 0), 1)) }
                        note("The subject turns into a see-through, glowing blue hologram with scan lines.")
                    case .vision:
                        GlassTabs(tabs: VisionMode.allCases, selection: Binding(get: { vm.adjustments.visionMode },
                                                                              set: { vm.setVisionMode($0) })) { $0.label }
                        GlassSliderRow(title: "Strength", value: a.visionAmount) { vm.setEffect(\.visionAmount, to: min(max($0, 0), 1)) }
                            .opacity(a.visionMode == .none ? 0.4 : 1)
                            .disabled(a.visionMode == .none)
                        note("Thermal maps brightness to heat-camera colors; Night Vision is green goggles with grain.")
                    case .sort:
                        GlassSliderRow(title: "Pixel Sort", value: a.pixelSort) { vm.setEffect(\.pixelSort, to: min(max($0, 0), 1)) }
                        HStack(spacing: 8) {
                            GlassTabs(tabs: [false, true], selection: Binding(get: { vm.adjustments.pixelSortVertical },
                                                                             set: { vm.setFlag(\.pixelSortVertical, to: $0) })) {
                                $0 ? "Vertical" : "Horizontal"
                            }
                        }
                        Toggle(isOn: Binding(get: { vm.adjustments.pixelSortSubjectOnly },
                                             set: { vm.setFlag(\.pixelSortSubjectOnly, to: $0) })) {
                            Text("SUBJECT ONLY").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                        }
                        .tint(.yellow)
                    case .orbit:
                        GlassSliderRow(title: "Clones", value: a.orbitCount, range: 0...12,
                                       display: { $0 < 1.5 ? "Off" : "\(Int($0.rounded()))" }) {
                            vm.setEffect(\.orbitCount, to: min(max($0.rounded(), 0), 12))
                        }
                        Group {
                            GlassSliderRow(title: "Size", value: a.orbitSize) { vm.setEffect(\.orbitSize, to: min(max($0, 0), 1)) }
                            GlassSliderRow(title: "Distance", value: a.orbitDistance) { vm.setEffect(\.orbitDistance, to: min(max($0, 0), 1)) }
                        }
                        .opacity(a.orbitClones > 0 ? 1 : 0.4)
                        .disabled(a.orbitClones == 0)
                    case .melt:
                        GlassSliderRow(title: "Melt", value: a.melt) { vm.setEffect(\.melt, to: min(max($0, 0), 1)) }
                        note("The subject sags and drips downward like melting wax.")
                    case .planet:
                        GlassSliderRow(title: "Planet", value: a.littlePlanet) { vm.setEffect(\.littlePlanet, to: min(max($0, 0), 1)) }
                        GlassSliderRow(title: "Spin", value: a.planetSpin, range: 0...360,
                                       display: { "\(Int($0.rounded()))°" }) { vm.setEffect(\.planetSpin, to: min(max($0, 0), 360)) }
                            .opacity(a.littlePlanet > 0 ? 1 : 0.4)
                            .disabled(a.littlePlanet == 0)
                        note("Wraps the photo into a tiny planet: the ground in the middle, the sky around it. Best with wide, level shots.")
                    case .depth:
                        GlassSliderRow(title: "Depth Map", value: a.depthMap) { vm.setEffect(\.depthMap, to: min(max($0, 0), 1)) }
                        GlassTabs(tabs: [false, true], selection: Binding(get: { vm.adjustments.depthHeat },
                                                                         set: { vm.setFlag(\.depthHeat, to: $0) })) { $0 ? "Heat" : "Gray" }
                            .opacity(a.depthMap > 0 ? 1 : 0.4)
                            .disabled(a.depthMap == 0)
                        note("An estimated depth view (near is bright): the subject closest, the far scene darkest. It is a stylized estimate, not measured depth.")
                    }
                }
            }
        }
    }

    /// Window blinds, spotlight, Orton glow and sparkle, one at a time.
    private var lightPage: some View {
        let a = vm.adjustments
        return VStack(alignment: .leading, spacing: 12) {
            GlassTabs(tabs: LightEffect.allCases, selection: $light) { $0.label }
            PagedStack(pages: LightEffect.allCases, selection: light) { effect in
                VStack(alignment: .leading, spacing: 12) {
                    switch effect {
                    case .blinds:
                        GlassSliderRow(title: "Blinds", value: a.blinds) { vm.setEffect(\.blinds, to: min(max($0, 0), 1)) }
                        Group {
                            GlassSliderRow(title: "Angle", value: a.blindsAngle, range: 0...180,
                                           display: { "\(Int($0.rounded()))°" }) { vm.setEffect(\.blindsAngle, to: min(max($0, 0), 180)) }
                            GlassSliderRow(title: "Slat Size", value: a.blindsSize) { vm.setEffect(\.blindsSize, to: min(max($0, 0), 1)) }
                        }
                        .opacity(a.blinds > 0 ? 1 : 0.4)
                        .disabled(a.blinds == 0)
                    case .spot:
                        GlassSliderRow(title: "Spotlight", value: a.spotlight) { vm.setEffect(\.spotlight, to: min(max($0, 0), 1)) }
                        GlassSliderRow(title: "Size", value: a.spotlightSize) { vm.setEffect(\.spotlightSize, to: min(max($0, 0), 1)) }
                            .opacity(a.spotlight > 0 ? 1 : 0.4)
                            .disabled(a.spotlight == 0)
                        note("A pool of light on the subject; everything else falls into shadow.")
                    case .glow:
                        GlassSliderRow(title: "Glow", value: a.glow) { vm.setEffect(\.glow, to: min(max($0, 0), 1)) }
                        note("Orton glow: a luminous, dreamy softness over a sharp photo.")
                    case .sparkle:
                        GlassSliderRow(title: "Sparkle", value: a.sparkle) { vm.setEffect(\.sparkle, to: min(max($0, 0), 1)) }
                        note("Star glints on the brightest highlights, like a Y2K glam or star filter.")
                    }
                }
            }
        }
    }

    /// VHS, halftone and chroma, one at a time.
    private var retroPage: some View {
        let a = vm.adjustments
        return VStack(alignment: .leading, spacing: 12) {
            GlassTabs(tabs: RetroEffect.allCases, selection: $retro) { $0.label }
            PagedStack(pages: RetroEffect.allCases, selection: retro) { effect in
                VStack(alignment: .leading, spacing: 12) {
                    switch effect {
                    case .vhs:
                        GlassSliderRow(title: "VHS", value: a.vhs) { vm.setEffect(\.vhs, to: min(max($0, 0), 1)) }
                        note("Tape color bleed, scan lines, a soft picture and tape noise.")
                    case .halftone:
                        GlassSliderRow(title: "Halftone", value: a.halftone) { vm.setEffect(\.halftone, to: min(max($0, 0), 1)) }
                        Group {
                            GlassSliderRow(title: "Dot Size", value: a.halftoneDot) { vm.setEffect(\.halftoneDot, to: min(max($0, 0), 1)) }
                            // How much black ink versus white paper shows.
                            GlassSliderRow(title: "Black ↔ White", value: a.halftoneBalance, range: -1...1,
                                           display: { $0 == 0 ? "0" : String(format: "%+d", Int(($0 * 100).rounded())) }) {
                                vm.setEffect(\.halftoneBalance, to: min(max($0, -1), 1))
                            }
                            GlassTabs(tabs: [false, true], selection: Binding(get: { vm.adjustments.halftoneColor },
                                                                             set: { vm.setFlag(\.halftoneColor, to: $0) })) {
                                $0 ? "Color" : "Black & White"
                            }
                        }
                        .opacity(a.halftone > 0 ? 1 : 0.4)
                        .disabled(a.halftone == 0)
                    case .chroma:
                        GlassSliderRow(title: "Chroma", value: a.chroma) { vm.setEffect(\.chroma, to: min(max($0, 0), 1)) }
                        note("Red and blue drift apart toward the edges, like a 2000s digicam lens.")
                    }
                }
            }
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
