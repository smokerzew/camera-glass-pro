import SwiftUI

/// Trim sheet: start/end handles for the loaded video. Playback loops inside the range, and the
/// edited export and "Save Video with UI" use it. The original export stays untrimmed (byte-for-byte).
struct VideoTrimView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Text(Self.format(vm.trimStart))
                    Spacer()
                    Text("Length \(Self.format(vm.trimEnd - vm.trimStart))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.format(vm.trimEnd))
                }
                .font(.subheadline.monospacedDigit())

                handle(title: "Start", value: Binding(
                    get: { vm.trimStart },
                    set: { vm.setTrim(start: $0, end: vm.trimEnd); vm.scrub(to: vm.trimStart) }
                ))
                handle(title: "End", value: Binding(
                    get: { vm.trimEnd },
                    set: { vm.setTrim(start: vm.trimStart, end: $0); vm.scrub(to: vm.trimEnd) }
                ))

                Text("Playback loops inside this range. The edited export and Save Video with UI use it; the original export stays full length.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Trim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { vm.resetTrim() }
                        .disabled(!vm.isTrimmed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(330), .medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(330)))
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
    }

    private func handle(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: 0...max(vm.videoDuration, 0.1))
                .tint(.yellow)
                .accessibilityLabel("Trim \(title.lowercased())")
                .accessibilityValue(Self.format(value.wrappedValue))
        }
    }

    static func format(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let rest = clamped - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, rest)
    }
}
