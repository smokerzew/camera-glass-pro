import SwiftUI

/// "Describe your edit": type what you want and the on-device AI moves the sliders for you.
struct AIEditBox: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @State private var request = ""
    @FocusState private var focused: Bool

    private let examples = ["Moody and cinematic", "Warm golden hour", "Brighter face, darker background",
                            "Clean black and white", "Soft film look with grain"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                TextField("Describe your edit", text: $request)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(send)
                    .disabled(vm.isAskingAI)
                if vm.isAskingAI {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || !vm.hasMedia)
                    .accessibilityLabel("Apply AI edit")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .cameraGlass(.interactive, in: Capsule())

            if let message = vm.aiMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let changes = vm.aiChangeSummary {
                        // What moved, so it can be fine-tuned with the sliders below (marked with ✦).
                        Text(changes)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.yellow)
                        HStack(spacing: 8) {
                            Button("Undo AI Edit", systemImage: "arrow.uturn.backward") { vm.revertAIEdit() }
                            Button("Keep") { vm.clearAIEdit() }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.yellow)
                    }
                }
                .transition(.opacity)
            } else if let reason = AIEditService.unavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) {
                                request = example
                                send()
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .cameraGlass(.regular, in: Capsule())
                            .disabled(vm.isAskingAI || !vm.hasMedia)
                        }
                    }
                }
            }
        }
    }

    private func send() {
        focused = false
        vm.applyAIEdit(request)
    }
}
