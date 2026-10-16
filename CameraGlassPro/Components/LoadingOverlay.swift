import SwiftUI

struct LoadingOverlay: View {
    let message: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(.white)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .cameraGlass(.interactive, in: Capsule())
            }
            .padding(24)
            .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// Timer countdown before the import picker opens. Tap anywhere to cancel.
struct CountdownOverlay: View {
    let seconds: Int
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("\(seconds)")
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                Text("Opening photo picker. Tap to cancel.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCancel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer: \(seconds) seconds until the photo picker opens")
        .accessibilityHint("Double tap to cancel")
        .accessibilityAddTraits(.isButton)
    }
}
