import SwiftUI

/// Shared full-screen canvas for the brush editors: the photo fitted on black, a live yellow line while
/// drawing, and normalized (0...1, top-left) points handed back when a stroke ends.
private struct BrushCanvas: View {
    let image: CGImage?
    var overlay: CGImage? = nil
    let brush: Double
    let onStroke: ([CGPoint]) -> Void
    @State private var current: [CGPoint] = []

    var body: some View {
        GeometryReader { proxy in
            if let image {
                let size = proxy.size
                let ratio = CGFloat(image.width) / CGFloat(max(image.height, 1))
                let fit = FramingGeometry.frameSize(ratio: ratio, in: size)
                let origin = CGPoint(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable()
                        .frame(width: fit.width, height: fit.height)
                        .offset(x: origin.x, y: origin.y)
                    if let overlay {
                        Image(decorative: overlay, scale: 1).resizable()
                            .frame(width: fit.width, height: fit.height)
                            .offset(x: origin.x, y: origin.y)
                            .allowsHitTesting(false)
                    }
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
                            if let last = current.last, hypot(last.x - p.x, last.y - p.y) < 0.004 { return }
                            current.append(p)
                        }
                        .onEnded { _ in
                            if !current.isEmpty { onStroke(current) }
                            current = []
                        }
                )
            } else {
                ProgressView().tint(.white).frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// Undo / redo history of a list of strokes (going back never throws work away).
private struct StrokeHistory<Stroke> {
    var past: [[Stroke]] = []
    var future: [[Stroke]] = []

    mutating func record(_ current: [Stroke]) {
        past.append(current)
        future.removeAll()
    }
}

/// Refine Subject: paint to add to or erase from the detected subject (shown in red).
struct MaskRefineEditorView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var add = true
    @State private var brush = 0.05
    @State private var photo: CGImage?
    @State private var overlay: CGImage?
    @State private var history = StrokeHistory<MaskStroke>()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                EditorTopBar(title: "REFINE SUBJECT", canUndo: !history.past.isEmpty, canRedo: !history.future.isEmpty,
                             undo: undo, redo: redo, done: { dismiss() })
                BrushCanvas(image: photo, overlay: overlay, brush: brush) { points in
                    change(to: vm.adjustments.maskStrokes + [MaskStroke(add: add, width: brush, points: points)])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                VStack(spacing: 14) {
                    GlassTabs(tabs: [true, false], selection: $add) { $0 ? "Add" : "Erase" }
                    GlassSliderRow(title: "Brush", value: brush, range: 0.01...0.2,
                                   display: { "\(Int(($0 * 100).rounded()))" }) { brush = $0 }
                    Text("Red shows the subject. Add paints more in, Erase takes it out.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                    Button("Clear All", role: .destructive) { change(to: []) }
                        .font(.subheadline.weight(.semibold))
                        .disabled(vm.adjustments.maskStrokes.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task {
            photo = await vm.editorPreview()
            overlay = await vm.subjectOverlay()
        }
    }

    private func change(to strokes: [MaskStroke]) {
        history.record(vm.adjustments.maskStrokes)
        vm.setMaskStrokes(strokes)
        refresh()
    }

    private func undo() {
        guard let previous = history.past.popLast() else { return }
        history.future.append(vm.adjustments.maskStrokes)
        vm.setMaskStrokes(previous)
        refresh()
    }

    private func redo() {
        guard let next = history.future.popLast() else { return }
        history.past.append(vm.adjustments.maskStrokes)
        vm.setMaskStrokes(next)
        refresh()
    }

    private func refresh() {
        Task { overlay = await vm.subjectOverlay() }
    }
}

/// Liquify: push parts of the photo with a finger; the photo re-renders after each push.
struct LiquifyEditorView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var brush = 0.08
    @State private var strength = 0.7
    @State private var photo: CGImage?
    @State private var history = StrokeHistory<LiquifyStroke>()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                EditorTopBar(title: "LIQUIFY", canUndo: !history.past.isEmpty, canRedo: !history.future.isEmpty,
                             undo: undo, redo: redo, done: { dismiss() })
                BrushCanvas(image: photo, brush: brush) { points in
                    guard points.count > 1 else { return }
                    change(to: vm.adjustments.liquifyStrokes + [LiquifyStroke(points: points, radius: brush, strength: strength)])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                VStack(spacing: 14) {
                    GlassSliderRow(title: "Brush", value: brush, range: 0.02...0.3,
                                   display: { "\(Int(($0 * 100).rounded()))" }) { brush = $0 }
                    GlassSliderRow(title: "Strength", value: strength, range: 0.1...1) { strength = $0 }
                    Text("Drag to push what's under the brush along with your finger.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                    Button("Reset", role: .destructive) { change(to: []) }
                        .font(.subheadline.weight(.semibold))
                        .disabled(vm.adjustments.liquifyStrokes.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { photo = await vm.editorPreview() }
    }

    private func change(to strokes: [LiquifyStroke]) {
        history.record(vm.adjustments.liquifyStrokes)
        vm.setLiquifyStrokes(strokes)
        refresh()
    }

    private func undo() {
        guard let previous = history.past.popLast() else { return }
        history.future.append(vm.adjustments.liquifyStrokes)
        vm.setLiquifyStrokes(previous)
        refresh()
    }

    private func redo() {
        guard let next = history.future.popLast() else { return }
        history.past.append(vm.adjustments.liquifyStrokes)
        vm.setLiquifyStrokes(next)
        refresh()
    }

    private func refresh() {
        Task { photo = await vm.editorPreview() }
    }
}

/// Paint editor for brush tools that only collect strokes (Remove, Focus Brush): the edited photo re-renders
/// after each stroke; undo, redo and Clear All.
struct PaintEditorView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    let title: String
    let strokes: KeyPath<PhotoAdjustmentState, [MaskStroke]>
    let set: ([MaskStroke]) -> Void
    let note: String
    @Environment(\.dismiss) private var dismiss
    @State private var brush = 0.05
    @State private var photo: CGImage?
    @State private var history = StrokeHistory<MaskStroke>()

    private var current: [MaskStroke] { vm.adjustments[keyPath: strokes] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                EditorTopBar(title: title, canUndo: !history.past.isEmpty, canRedo: !history.future.isEmpty,
                             undo: undo, redo: redo, done: { dismiss() })
                BrushCanvas(image: photo, brush: brush) { points in
                    change(to: current + [MaskStroke(add: true, width: brush, points: points)])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                VStack(spacing: 14) {
                    GlassSliderRow(title: "Brush", value: brush, range: 0.01...0.2,
                                   display: { "\(Int(($0 * 100).rounded()))" }) { brush = $0 }
                    Text(note)
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                    Button("Clear All", role: .destructive) { change(to: []) }
                        .font(.subheadline.weight(.semibold))
                        .disabled(current.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { photo = await vm.editorPreview() }
    }

    private func change(to next: [MaskStroke]) {
        history.record(current)
        set(next)
        refresh()
    }

    private func undo() {
        guard let previous = history.past.popLast() else { return }
        history.future.append(current)
        set(previous)
        refresh()
    }

    private func redo() {
        guard let next = history.future.popLast() else { return }
        history.past.append(current)
        set(next)
        refresh()
    }

    private func refresh() {
        Task { photo = await vm.editorPreview() }
    }
}

/// Undo, title, redo and Done for the brush editors.
private struct EditorTopBar: View {
    let title: String
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    let done: () -> Void

    var body: some View {
        HStack {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }
                .foregroundStyle(canUndo ? .white : .white.opacity(0.4))
                .disabled(!canUndo)
                .accessibilityLabel("Undo stroke")
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }
                .foregroundStyle(canRedo ? .white : .white.opacity(0.4))
                .disabled(!canRedo)
                .accessibilityLabel("Redo stroke")
                .padding(.leading, 18)
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button("Done", action: done)
                .font(.body.weight(.semibold))
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(minHeight: 44)
    }
}
