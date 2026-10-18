import SwiftUI

/// Full-screen Blur & Pixelate editor: paint with a finger over what should be hidden. Each stroke is one
/// undoable edit; the photo updates with the real effect after every stroke.
struct RedactionEditorView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Redaction = .blur
    @State private var brush = 0.08
    @State private var current: [CGPoint] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                GeometryReader { proxy in canvas(in: proxy.size) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                controls
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button("Undo") { vm.removeLastRedactionStroke() }
                .foregroundStyle(vm.adjustments.redactionStrokes.isEmpty ? .white.opacity(0.4) : .white)
                .disabled(vm.adjustments.redactionStrokes.isEmpty)
            Spacer()
            Text("BLUR & PIXELATE")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func canvas(in size: CGSize) -> some View {
        if let image = vm.displayedImage {
            let ratio = CGFloat(image.width) / CGFloat(max(image.height, 1))
            let fit = FramingGeometry.frameSize(ratio: ratio, in: size)
            let origin = CGPoint(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .offset(x: origin.x, y: origin.y)
                    .accessibilityLabel("Photo to blur or pixelate")
                // The stroke being drawn, until it is added and rendered for real.
                Path { path in
                    let points = current.map { CGPoint(x: origin.x + $0.x * fit.width, y: origin.y + $0.y * fit.height) }
                    if let first = points.first { path.move(to: first); path.addLines(points) }
                }
                .stroke(Color.yellow.opacity(0.55),
                        style: StrokeStyle(lineWidth: brush * min(fit.width, fit.height), lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = CGPoint(x: (value.location.x - origin.x) / fit.width, y: (value.location.y - origin.y) / fit.height)
                        guard p.x >= -0.05, p.x <= 1.05, p.y >= -0.05, p.y <= 1.05 else { return }
                        // Skip points closer than ~0.5% apart: smooth lines, small saved edits.
                        if let last = current.last, hypot(last.x - p.x, last.y - p.y) < 0.005 { return }
                        current.append(p)
                    }
                    .onEnded { _ in
                        vm.addRedactionStroke(RedactionStroke(mode: mode, width: brush, points: current))
                        current = []
                    }
            )
            .accessibilityHint("Drag over the areas to hide")
        } else {
            ProgressView().tint(.white).frame(width: size.width, height: size.height)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            GlassTabs(tabs: [Redaction.blur, .pixelate], selection: $mode) { $0.label }
                .padding(.horizontal, 20)
            GlassSliderRow(title: "Brush", value: brush, range: 0.02...0.25,
                           display: { "\(Int(($0 * 100).rounded()))" }) { brush = $0 }
                .padding(.horizontal, 20)
            Button("Clear All", role: .destructive) { vm.clearRedactionStrokes() }
                .font(.subheadline.weight(.semibold))
                .disabled(vm.adjustments.redactionStrokes.isEmpty)
        }
        .padding(.bottom, 16)
    }
}
