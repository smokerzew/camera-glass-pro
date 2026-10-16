import SwiftUI

/// Non-destructive adjustments sheet. Partial-height detents keep the photo visible and interactive.
struct PhotoAdjustmentView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusRow

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(380), .medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(380)))
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
        .appAlert(vm)
        .onDisappear { vm.showOriginal = false }
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
                    vm.showOriginal = pressing
                })
                .opacity(vm.hasEdits ? 1 : 0.4)
                .allowsHitTesting(vm.hasEdits)
                .accessibilityRepresentation {
                    Toggle("Show original", isOn: $vm.showOriginal)
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
