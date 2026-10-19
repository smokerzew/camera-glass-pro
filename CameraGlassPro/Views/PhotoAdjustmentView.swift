import SwiftUI

/// Non-destructive adjustments sheet. Partial-height detents keep the photo visible and interactive.
struct PhotoAdjustmentView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    /// Shared with the workspace, which fits the photo into the space above the sheet.
    @Binding var detent: PresentationDetent
    @Environment(\.dismiss) private var dismiss
    @State private var isNamingPreset = false
    @State private var presetName = ""
    @State private var section: AdjustGroup = .light
    @State private var confirmResetEverything = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusRow

                    // Short pages instead of one long list, so the photo above stays the focus.
                    Picker("Section", selection: $section) {
                        ForEach(AdjustGroup.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let area = ResetArea(section) {
                        HStack {
                            Spacer()
                            if PhotoAdjustmentState.canShuffle(area) {
                                AreaShuffleButton(vm: vm, area: area, onDark: false)
                            }
                            AreaResetButton(vm: vm, area: area, onDark: false)
                        }
                    }

                    switch section {
                    case .light:
                        presetsRow
                        sliders(for: .light)
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
                    case .color:
                        sliders(for: .color)
                        ColorMixerSection(vm: vm)
                    case .detail:
                        sliders(for: .detail)
                    case .effects:
                        sliders(for: .effects)
                    case .local:
                        LocalAdjustmentsSection(vm: vm)
                    case .ai:
                        AIEditBox(vm: vm)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationBarTitleDisplayMode(.inline) // no title: the toolbar is full and the tabs say where you are
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Reset") {
                        Button("Reset Adjust Tabs") { vm.reset(.adjust) }
                            .disabled(!vm.adjustments.canReset(.adjust))
                        Button("Reset Everything…", role: .destructive) { confirmResetEverything = true }
                            .disabled(!vm.hasEdits)
                    }
                    .disabled(!vm.hasEdits)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Versions: keep several edits of this photo and switch between them.
                    Menu {
                        Button("Save as New Version", systemImage: "plus") { vm.saveVersion() }
                            .disabled(!vm.hasEdits)
                        ForEach(Array(vm.versions.enumerated()), id: \.offset) { index, version in
                            Button { vm.applyVersion(at: index) } label: {
                                if version == vm.adjustments {
                                    Label("Version \(index + 1)", systemImage: "checkmark")
                                } else {
                                    Text("Version \(index + 1)")
                                }
                            }
                        }
                        if !vm.versions.isEmpty {
                            Menu("Delete a Version") {
                                ForEach(Array(vm.versions.indices), id: \.self) { index in
                                    Button("Version \(index + 1)", role: .destructive) { vm.deleteVersion(at: index) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .accessibilityLabel("Versions")
                    Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!vm.canUndo)
                        .accessibilityLabel("Undo")
                    Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!vm.canRedo)
                        .accessibilityLabel("Redo")
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset everything?", isPresented: $confirmResetEverything, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) { vm.resetAllAdjustments() }
            } message: {
                Text("Removes all adjustments, filters, FX, subject edits and the crop. You can undo it.")
            }
            .alert("Save Style", isPresented: $isNamingPreset) {
                TextField("Name", text: $presetName)
                Button("Save") { vm.savePreset(named: presetName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves the current adjustments so you can apply them to other photos and videos.")
            }
        }
        .presentationDetents([.height(380), .medium], selection: $detent) // never covers the whole photo
        .presentationBackgroundInteraction(.enabled(upThrough: .height(380)))
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
        .preferredColorScheme(.dark) // matches the camera UI; yellow labels were hard to read on light glass
        .appAlert(vm)
        .onDisappear { vm.setShowOriginal(false) }
    }

    @ViewBuilder
    private func sliders(for group: AdjustGroup) -> some View {
        ForEach(AdjustmentParameter.allCases.filter { $0.group == group }) { parameter in
            AdjustmentSliderRow(
                parameter: parameter,
                value: Binding(
                    get: { vm.adjustments[parameter] },
                    set: { vm.setAdjustment(parameter, to: $0) }
                ),
                isModified: vm.adjustments.isModified(parameter),
                changedByAI: vm.aiChangedParameters.contains(parameter),
                onReset: { vm.resetAdjustment(parameter) }
            )
        }
    }

    /// Saved styles: tap to apply, long-press to delete, + to save the current adjustments.
    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { vm.autoEnhance() } label: {
                    Label("Auto", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .cameraGlass(.interactive, in: Capsule())
                }
                .disabled(!vm.hasMedia)
                .accessibilityHint("Sets exposure, contrast, highlights, shadows, saturation and warmth for this photo")

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
    var changedByAI = false
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label(parameter.title, systemImage: parameter.systemImage)
                    .font(.subheadline.weight(.medium))
                if changedByAI {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Changed by AI")
                }
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
