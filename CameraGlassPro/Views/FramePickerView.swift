import SwiftUI

/// Frame tool: scrub or step one frame at a time to the exact frame, then save it as a photo,
/// either the edited frame alone (full quality) or the whole screen with the camera UI.
struct FramePickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("frameIncludesUI") private var includeUI = false
    @State private var fps: Double = 30

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Text(VideoTrimView.format(vm.playbackTime))
                    Spacer()
                    Text("Frame \(Int((vm.playbackTime * fps).rounded()) + 1)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.monospacedDigit())

                Slider(value: Binding(get: { vm.playbackTime }, set: { vm.scrub(to: $0) }),
                       in: 0...max(vm.videoDuration, 0.1))
                    .tint(.yellow)
                    .accessibilityLabel("Frame position")
                    .accessibilityValue(VideoTrimView.format(vm.playbackTime))

                HStack(spacing: 14) {
                    stepButton(-10, "backward.end.alt", "Back 10 frames")
                    stepButton(-1, "backward.frame", "Previous frame")
                    stepButton(1, "forward.frame", "Next frame")
                    stepButton(10, "forward.end.alt", "Forward 10 frames")
                }

                Toggle(isOn: $includeUI) {
                    Label("Include Camera UI", systemImage: "rectangle.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(.yellow)

                Text(includeUI
                     ? "Saves a screenshot of the app as you see it, with this frame in the viewfinder."
                     : "Saves only this frame, at full quality, with your edits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { vm.saveChosenFrame(withUI: includeUI) }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { fps = await vm.videoFrameRate() }
        .presentationDetents([.height(360), .medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(360)))
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
    }

    private func stepButton(_ count: Int, _ symbol: String, _ label: String) -> some View {
        Button { vm.stepFrame(count, fps: fps) } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .accessibilityLabel(label)
    }
}
