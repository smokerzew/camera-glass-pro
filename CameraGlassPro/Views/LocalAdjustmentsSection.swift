import SwiftUI

/// Graduated and radial filters in the Adjust sheet: add up to four, place them with sliders (a small
/// map shows the mask in yellow on the photo), and set brightness, saturation and warmth inside them.
struct LocalAdjustmentsSection: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Graduated & Radial", systemImage: "circle.lefthalf.striped.horizontal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    Button("Graduated", systemImage: LocalAdjustment.Shape.graduated.systemImage) { vm.addLocal(.graduated) }
                    Button("Radial", systemImage: LocalAdjustment.Shape.radial.systemImage) { vm.addLocal(.radial) }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(vm.adjustments.localAdjustments.count >= LocalAdjustment.limit || !vm.hasMedia)
            }

            if vm.adjustments.localAdjustments.isEmpty {
                Text("Darken a sky with a graduated filter, or brighten a face with a radial one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(vm.adjustments.localAdjustments) { local in
                LocalAdjustmentCard(vm: vm, local: local)
            }
        }
    }
}

private struct LocalAdjustmentCard: View {
    @Bindable var vm: CameraWorkspaceViewModel
    let local: LocalAdjustment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(local.shape.label, systemImage: local.shape.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) { vm.removeLocal(local.id) } label: {
                    Image(systemName: "trash").frame(width: 44, height: 32)
                }
                .accessibilityLabel("Remove \(local.shape.label.lowercased()) filter")
            }

            MaskMap(image: vm.displayedImage, local: local)
                .frame(height: 110)
                .frame(maxWidth: .infinity)

            if local.shape == .graduated {
                HStack(spacing: 6) {
                    ForEach(LocalAdjustment.Edge.allCases) { edge in
                        let selected = local.edge == edge
                        Button { vm.updateLocal(local.id) { $0.edge = edge } } label: {
                            Text(edge.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selected ? Color.yellow : .primary)
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .cameraGlass(selected ? .selected : .interactive, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("From \(edge.label.lowercased())")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                slider("Reach", \.position, 0...1)
            } else {
                slider("Across", \.centerX, 0...1)
                slider("Up / Down", \.centerY, 0...1)
                slider("Size", \.size, 0.02...1)
                Toggle("Affect outside", isOn: Binding(get: { local.inverted },
                                                      set: { value in vm.updateLocal(local.id) { $0.inverted = value } }))
                    .font(.subheadline)
                    .tint(.yellow)
            }
            slider("Softness", \.softness, 0...1)

            Divider()
            ForEach(RegionEdit.Control.allCases) { control in
                slider(control.label, (\LocalAdjustment.edit).appending(path: control.keyPath), -1...1, signed: true)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func slider(_ title: String, _ path: WritableKeyPath<LocalAdjustment, Double>,
                        _ range: ClosedRange<Double>, signed: Bool = false) -> some View {
        let value = local[keyPath: path]
        return VStack(spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(signed ? (value == 0 ? "0" : String(format: "%+d", Int((value * 100).rounded())))
                            : "\(Int((value * 100).rounded()))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(signed && value != 0 ? Color.yellow : .secondary)
            }
            Slider(value: Binding(get: { local[keyPath: path] },
                                  set: { newValue in vm.updateLocal(local.id) { $0[keyPath: path] = newValue } }),
                   in: range)
                .tint(.yellow)
                .accessibilityLabel("\(local.shape.label) \(title)")
                .accessibilityValue(String(Int((value * 100).rounded())))
        }
    }
}

/// The photo with the filter's mask drawn in yellow: where the effect is strongest.
private struct MaskMap: View {
    let image: CGImage?
    let local: LocalAdjustment

    var body: some View {
        GeometryReader { proxy in
            let size = fitted(in: proxy.size)
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Color.gray.opacity(0.3)
                }
                mask(in: size).blendMode(.plusLighter)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }

    private func fitted(in box: CGSize) -> CGSize {
        guard let image, image.width > 0, image.height > 0 else { return box }
        let ratio = CGFloat(image.width) / CGFloat(image.height)
        return box.width / box.height > ratio ? CGSize(width: box.height * ratio, height: box.height)
                                               : CGSize(width: box.width, height: box.width / ratio)
    }

    /// From the chosen edge toward the opposite one.
    private static func axis(_ edge: LocalAdjustment.Edge) -> (start: UnitPoint, end: UnitPoint) {
        switch edge {
        case .top: (.top, .bottom)
        case .bottom: (.bottom, .top)
        case .left: (.leading, .trailing)
        case .right: (.trailing, .leading)
        }
    }

    @ViewBuilder
    private func mask(in size: CGSize) -> some View {
        let l = local.clamped
        let tint = Color.yellow.opacity(0.55)
        switch l.shape {
        case .graduated:
            let full = l.position * (1 - l.softness)
            LinearGradient(stops: [.init(color: tint, location: 0), .init(color: tint, location: full),
                                   .init(color: .clear, location: max(full + 0.001, l.position))],
                           startPoint: Self.axis(l.edge).start, endPoint: Self.axis(l.edge).end)
        case .radial:
            let outer = l.size * hypot(size.width, size.height) / 2
            let inside = l.inverted ? Color.clear : tint
            let outside = l.inverted ? tint : Color.clear
            RadialGradient(stops: [.init(color: inside, location: 0), .init(color: inside, location: 1 - l.softness),
                                   .init(color: outside, location: 1)],
                           center: UnitPoint(x: l.centerX, y: l.centerY), startRadius: 0, endRadius: max(outer, 1))
        }
    }
}
