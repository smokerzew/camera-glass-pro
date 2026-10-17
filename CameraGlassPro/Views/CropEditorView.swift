import SwiftUI

/// Photos-style crop editor: crop box with corner handles, straighten slider, rotate 90°, flip,
/// auto-straighten (Vision horizon) and aspect presets. Commits as one undoable edit on Done.
struct CropEditorView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cameraReduceMotion) private var reduceMotion

    @State private var rotation = 0
    @State private var flipped = false
    @State private var straighten: Double = 0
    @State private var crop = PhotoAdjustmentState.fullCrop
    @State private var aspect: CropAspect = .freeform
    @State private var preview: CGImage?
    @State private var dragStart: CGRect?
    @State private var note: String?

    private struct Params: Equatable { let rotation: Int; let flipped: Bool; let straighten: Double }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                GeometryReader { proxy in canvas(in: proxy.size) }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                controls
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            rotation = vm.adjustments.rotation
            flipped = vm.adjustments.flipped
            straighten = vm.adjustments.straighten
            crop = vm.adjustments.cropRect
        }
        .task(id: Params(rotation: rotation, flipped: flipped, straighten: straighten)) {
            try? await Task.sleep(for: .milliseconds(40)) // coalesce slider ticks
            guard !Task.isCancelled else { return }
            if let image = await vm.geometryPreview(rotation: rotation, flipped: flipped, straighten: straighten) {
                preview = image
            }
        }
        .sensoryFeedback(.selection, trigger: abs(straighten) < 0.05)
        .statusBarHidden()
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
            Spacer()
            Text("CROP")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button("Done") {
                vm.setGeometry(crop: crop, rotation: rotation, flipped: flipped, straighten: straighten)
                dismiss()
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func canvas(in size: CGSize) -> some View {
        if let preview {
            let imageSize = CGSize(width: preview.width, height: preview.height)
            let fit = FramingGeometry.frameSize(ratio: imageSize.width / max(imageSize.height, 1), in: size)
            let origin = CGPoint(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2)
            let box = CGRect(x: origin.x + crop.minX * fit.width, y: origin.y + crop.minY * fit.height,
                             width: crop.width * fit.width, height: crop.height * fit.height)

            ZStack(alignment: .topLeading) {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: size.width / 2, y: size.height / 2)
                    .accessibilityLabel("Photo being cropped")

                // Dim outside the crop, thirds grid inside, white border and L-shaped corner handles.
                Path { path in
                    path.addRect(CGRect(origin: origin, size: fit))
                    path.addRect(box)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                GridShape(divisions: 3)
                    .stroke(.white.opacity(dragStart == nil ? 0.25 : 0.55), lineWidth: 0.6)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(.white, lineWidth: 1)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(fit: fit))
                    .accessibilityElement()
                    .accessibilityLabel("Crop box")
                    .accessibilityHint("Drag to move the crop")

                ForEach(CropCorner.allCases, id: \.self) { corner in
                    cornerHandle(corner)
                        .position(corner.point(in: box))
                        .gesture(cornerGesture(corner, fit: fit, imageSize: imageSize))
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            ProgressView().tint(.white).frame(width: size.width, height: size.height)
        }
    }

    private func cornerHandle(_ corner: CropCorner) -> some View {
        Path { path in
            let arm: CGFloat = 18
            path.move(to: CGPoint(x: 22 + corner.sx * arm, y: 22))
            path.addLine(to: CGPoint(x: 22, y: 22))
            path.addLine(to: CGPoint(x: 22, y: 22 + corner.sy * arm))
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .square))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("\(corner.name) crop handle")
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(String(format: "%+.1f°", straighten))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(abs(straighten) < 0.05 ? .white : Color.yellow)
                    .frame(width: 52, alignment: .leading)
                Slider(value: $straighten, in: -45...45)
                    .tint(.yellow)
                    .accessibilityLabel("Straighten")
                    .accessibilityValue(String(format: "%.1f degrees", straighten))
                Button("0°") { straighten = 0 }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)

            if let note {
                Text(note).font(.footnote).foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 6) {
                PanelControlButton(systemImage: "rotate.right", title: "ROTATE", hint: "Rotates 90 degrees clockwise") {
                    rotation = (rotation + 1) % 4
                    resetCropForShapeChange()
                }
                PanelControlButton(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: "FLIP",
                                   isActive: flipped, hint: "Mirrors the photo left to right") {
                    flipped.toggle()
                }
                PanelControlButton(systemImage: "level", title: "AUTO", hint: "Levels the horizon automatically") {
                    Task {
                        if let value = await vm.autoStraightenValue() {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { straighten = value }
                            note = nil
                        } else {
                            note = "No horizon found to level."
                        }
                    }
                }
                Menu {
                    ForEach(CropAspect.allCases) { option in
                        Button(option.label) { applyAspect(option) }
                    }
                } label: {
                    PanelControlButton(systemImage: "aspectratio", title: aspect == .freeform ? "ASPECT" : aspect.label.uppercased(),
                                       isActive: aspect != .freeform, hint: "Locks the crop to a shape") {}
                        .allowsHitTesting(false)
                }
                PanelControlButton(systemImage: "arrow.counterclockwise", title: "RESET", hint: "Back to the original framing") {
                    rotation = 0
                    flipped = false
                    straighten = 0
                    aspect = .freeform
                    crop = PhotoAdjustmentState.fullCrop
                    note = nil
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 16)
    }

    // MARK: Interaction

    private func moveGesture(fit: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                crop = CropMath.moved(start, dx: value.translation.width / fit.width, dy: value.translation.height / fit.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: CropCorner, fit: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                let lock = aspect.ratio(imageSize: imageSize).map { $0 * imageSize.height / imageSize.width }
                crop = CropMath.resized(start, corner: corner, dx: value.translation.width / fit.width,
                                        dy: value.translation.height / fit.height, normalizedRatio: lock)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func applyAspect(_ option: CropAspect) {
        aspect = option
        guard let preview, let ratio = option.ratio(imageSize: CGSize(width: preview.width, height: preview.height)) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            crop = CropAspect.centeredCrop(ratio: ratio, imageSize: CGSize(width: preview.width, height: preview.height))
        }
    }

    /// Rotating 90° swaps width and height, so the old crop no longer fits.
    private func resetCropForShapeChange() {
        crop = PhotoAdjustmentState.fullCrop
        if aspect != .freeform { aspect = .freeform }
    }
}

enum CropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var name: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    /// Direction the L-handle's arms point (into the box).
    var sx: CGFloat { self == .topLeft || self == .bottomLeft ? 1 : -1 }
    var sy: CGFloat { self == .topLeft || self == .topRight ? 1 : -1 }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

/// Crop box math in normalized (0...1, top-left origin) coordinates.
enum CropMath {
    static let minimumSide: CGFloat = 0.08

    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: min(max(rect.minX + dx, 0), 1 - rect.width),
               y: min(max(rect.minY + dy, 0), 1 - rect.height),
               width: rect.width, height: rect.height)
    }

    /// Drags one corner; the opposite corner stays put. `normalizedRatio` (width/height in normalized
    /// units) locks the shape when an aspect preset is chosen.
    static func resized(_ rect: CGRect, corner: CropCorner, dx: CGFloat, dy: CGFloat, normalizedRatio: CGFloat?) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch corner {
        case .topLeft: minX += dx; minY += dy
        case .topRight: maxX += dx; minY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        }
        minX = min(max(minX, 0), rect.maxX - minimumSide)
        maxX = max(min(maxX, 1), rect.minX + minimumSide)
        minY = min(max(minY, 0), rect.maxY - minimumSide)
        maxY = max(min(maxY, 1), rect.minY + minimumSide)
        var result = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        if let ratio = normalizedRatio, ratio > 0 {
            // Keep the width, derive the height; shrink both if that would leave the image.
            var width = result.width
            var height = width / ratio
            let anchorY = corner == .topLeft || corner == .topRight ? rect.maxY : rect.minY
            let room = corner == .topLeft || corner == .topRight ? anchorY : 1 - anchorY
            if height > room { height = room; width = height * ratio }
            let anchorX = corner == .topLeft || corner == .bottomLeft ? rect.maxX : rect.minX
            let x = corner == .topLeft || corner == .bottomLeft ? anchorX - width : anchorX
            let y = corner == .topLeft || corner == .topRight ? anchorY - height : anchorY
            result = CGRect(x: max(0, x), y: max(0, y), width: width, height: height)
        }
        return result
    }
}
