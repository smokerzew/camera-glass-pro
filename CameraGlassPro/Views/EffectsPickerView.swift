import SwiftUI

/// Glass Effects pop-up: Loop, Bounce, Long Exposure (from a video or Live Photo), and Live Photo
/// (turns a video into a real Live Photo saved to the library). Same card style as the other pop-ups.
struct EffectsPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private var effects: [LiveEffect] {
        vm.video != nil ? LiveEffect.allCases : LiveEffect.allCases.filter { $0 != .livePhoto }
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            HStack {
                Text("EFFECTS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button("Done") { close() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 6)

            if vm.canMakeEffects {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(effects) { effect in
                        PanelControlButton(systemImage: effect.systemImage, title: effect.title,
                                           hint: hint(for: effect)) {
                            vm.runEffect(effect)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if vm.video != nil {
                    // Live Photo sound: keep the video's audio or save it silent.
                    Toggle(isOn: Binding(get: { vm.livePhotoSound }, set: { vm.setLivePhotoSound($0) })) {
                        Label("Live Photo Sound", systemImage: vm.livePhotoSound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .tint(.yellow)
                    .padding(.horizontal, 6)
                    .accessibilityHint("When on, the Live Photo keeps the video's sound")
                }
                Text(vm.video != nil
                     ? "Effects use the trimmed range and your edits. Loop, Bounce and Long Exposure open as a new item; Live Photo saves to your library."
                     : "Made from this Live Photo's motion, with your edits. The result opens as a new item.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            } else {
                Text("Import a video or a Live Photo to make a Loop, Bounce or Long Exposure.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: 520)
        .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 80 { close() }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
                }
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Effects")
        .accessibilityAction(.escape) { close() }
    }

    private func hint(for effect: LiveEffect) -> String {
        switch effect {
        case .livePhoto: "Saves a Live Photo of the whole video (or the trimmed part); the frame on screen becomes the photo"
        case .loop: "Repeats the clip as a seamless loop"
        case .bounce: "Plays the clip forward and backward"
        case .longExposure: "Blends the frames into one photo, like a slow shutter"
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.showEffectsPicker = false }
    }
}

/// "LIVE" badge for Live Photos: touch and hold to play the motion.
struct LiveBadge: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: vm.isPlayingLive ? "livephoto.play" : "livephoto")
            Text("LIVE")
        }
        .font(.caption.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(vm.isPlayingLive || vm.livePreference ? Color.yellow : .white)
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .cameraGlass(.interactive, in: Capsule())
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
            vm.isPlayingLive = pressing
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live Photo")
        .accessibilityHint("Touch and hold to play the motion")
        .accessibilityAction(named: "Play") {
            vm.isPlayingLive = true
            Task { try? await Task.sleep(for: .seconds(3)); vm.isPlayingLive = false }
        }
    }
}
