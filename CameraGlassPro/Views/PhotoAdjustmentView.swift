import SwiftUI

/// Non-destructive adjustments sheet. Partial-height detents keep the photo visible and interactive.
struct PhotoAdjustmentView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isNamingPreset = false
    @State private var presetName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusRow
                    presetsRow

                    ForEach(AdjustmentParameter.allCases) { parameter in
                        AdjustmentSliderRow(
                            parameter: parameter,
                            value: Binding(
                                get: { vm.adjustments[parameter] },
                                set: { vm.setAdjustment(parameter, to: $0) }
                            ),
                            isModified: vm.adjustments.isModified(parameter),
                            onReset: { vm.resetAdjustment(parameter) }
                        )
                    }

                    Toggle(isOn: Binding(get: { vm.adjustments.nightLook }, set: { vm.setNightLook($0) })) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Night Look")
                                Text("Lifts shadows and reduces noise. A filter, not a capture mode.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "moon.stars")
                        }
                    }
                    .tint(.yellow)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset All", role: .destructive) { vm.resetAllAdjustments() }
                        .disabled(!vm.hasEdits)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!vm.canUndo)
                        .accessibilityLabel("Undo")
                    Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!vm.canRedo)
                        .accessibilityLabel("Redo")
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Style", isPresented: $isNamingPreset) {
                TextField("Name", text: $presetName)
                Button("Save") { vm.savePreset(named: presetName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves the current adjustments so you can apply them to other photos and videos.")
            }
        }
        .presentationDetents([.height(380), .medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(380)))
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
        .appAlert(vm)
        .onDisappear { vm.setShowOriginal(false) }
    }

    /// Saved styles: tap to apply, long-press to delete, + to save the current adjustments.
    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    presetName = ""
                    isNamingPreset = true
                } label: {
                    Label("Save Style", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .cameraGlass(.interactive, in: Capsule())
                }
                .disabled(!vm.hasEdits)

                ForEach(vm.presets) { preset in
                    Button { vm.applyPreset(preset) } label: {
                        Text(preset.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(vm.adjustments == preset.adjustments ? Color.yellow : .primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .cameraGlass(vm.adjustments == preset.adjustments ? .selected : .regular, in: Capsule())
                    }
                    .contextMenu {
                        Button("Delete Style", systemImage: "trash", role: .destructive) { vm.deletePreset(preset) }
                    }
                    .accessibilityHint("Applies this saved style. Touch and hold to delete.")
                }
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Label(vm.hasEdits ? "Edited" : "No edits", systemImage: vm.hasEdits ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(vm.hasEdits ? Color.yellow : .secondary)
            Spacer()
            Text("Hold to Compare")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .cameraGlass(vm.showOriginal ? .selected : .interactive, in: Capsule())
                .onLongPressGesture(minimumDuration: 0, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                    vm.setShowOriginal(pressing)
                })
                .opacity(vm.hasEdits ? 1 : 0.4)
                .allowsHitTesting(vm.hasEdits)
                .accessibilityRepresentation {
                    Toggle("Show original", isOn: Binding(get: { vm.showOriginal }, set: { vm.setShowOriginal($0) }))
                }
        }
    }
}

struct AdjustmentSliderRow: View {
    let parameter: AdjustmentParameter
    @Binding var value: Double
    let isModified: Bool
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label(parameter.title, systemImage: parameter.systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(parameter.format(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isModified ? Color.yellow : .secondary)
                    .accessibilityHidden(true)
                Button(action: onReset) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.body)
                        .frame(width: 44, height: 32)
                }
                .disabled(!isModified)
                .accessibilityLabel("Reset \(parameter.title)")
            }
            Slider(value: $value, in: parameter.range)
                .tint(.yellow)
                .accessibilityLabel(parameter.title)
                .accessibilityValue(parameter.format(value))
        }
        // One tick when leaving or returning to neutral; never per slider frame.
        .sensoryFeedback(.selection, trigger: isModified)
    }
}
