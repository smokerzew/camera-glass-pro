import SwiftUI

/// iOS-style Photographic Styles pop-up: style names, the 2D Tone × Color touch pad, and the Palette
/// slider. Same glass card, grabber and type as the ⠿ panel and the filter picker.
struct StylesPadView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @Environment(\.cameraLargeLabels) private var largeLabels
    @State private var dragOffset: CGFloat = 0
    @Namespace private var chipSelection

    private let padSize: CGFloat = 176

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            HStack(spacing: 14) {
                Text("PHOTOGRAPHIC STYLES")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button("Adjust") {
                    close()
                    vm.showAdjustments = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                Button("Done") { close() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 6)

            styleChips

            HStack(alignment: .center, spacing: 16) {
                pad
                VStack(alignment: .leading, spacing: 10) {
                    readout("TONE", vm.adjustments.styleTone)
                    readout("COLOR", vm.adjustments.styleColor)
                    Button("Reset") { vm.resetStylePad() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .disabled(vm.adjustments.styleTone == 0 && vm.adjustments.styleColor == 0 && vm.adjustments.stylePalette == 1)
                }
            }

            HStack(spacing: 10) {
                Text("PALETTE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: Binding(get: { vm.adjustments.stylePalette }, set: { vm.setStylePalette($0) }), in: 0...1)
                    .tint(.yellow)
                    .accessibilityLabel("Palette")
                    .accessibilityValue("\(Int(vm.adjustments.stylePalette * 100)) percent")
                Text("\(Int(vm.adjustments.stylePalette * 100))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: 520)
        .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .offset(y: max(0, dragOffset))
        .simultaneousGesture(
            DragGesture()
                .onChanged { if $0.startLocation.y < 44 { dragOffset = $0.translation.height } }
                .onEnded { value in
                    if value.startLocation.y < 44, value.translation.height > 80 { close() }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
                }
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photographic Styles")
        .accessibilityAction(.escape) { close() }
    }

    private var styleChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(PhotographicStyle.allCases) { style in
                        let isSelected = vm.adjustments.style == style
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.12)) { vm.setStyle(style) }
                        } label: {
                            Text(style.label.uppercased())
                                .font(.system(size: largeLabels ? 14 : 12, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? Color.yellow : .white.opacity(0.85))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(.black.opacity(0.35))
                                            .cameraGlass(.selected, in: Capsule())
                                            .matchedGeometryEffect(id: "chip", in: chipSelection)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .id(style)
                        .accessibilityLabel(style.label)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            .background(Capsule().fill(.black.opacity(0.25)))
            .clipShape(Capsule())
            .onAppear { proxy.scrollTo(vm.adjustments.style, anchor: .center) }
        }
    }

    /// The Tone × Color touch pad: a dot grid with a puck you drag; double-tap to center it.
    private var pad: some View {
        let tone = vm.adjustments.styleTone
        let color = vm.adjustments.styleColor
        let isCentered = abs(tone) < 0.04 && abs(color) < 0.04
        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.35))
                .cameraGlass(.subtle, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Canvas { context, size in
                let steps = 9
                for row in 0..<steps {
                    for column in 0..<steps {
                        let x = size.width * (CGFloat(column) + 0.5) / CGFloat(steps)
                        let y = size.height * (CGFloat(row) + 0.5) / CGFloat(steps)
                        let onAxis = row == steps / 2 || column == steps / 2
                        let r: CGFloat = onAxis ? 1.8 : 1.3
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .color(.white.opacity(onAxis ? 0.45 : 0.22)))
                    }
                }
            }
            .padding(10)

            Text("TONE")
                .font(.system(size: 8, weight: .bold)).tracking(1)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
            Text("COLOR")
                .font(.system(size: 8, weight: .bold)).tracking(1)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(6)

            Circle()
                .fill(Color.yellow.opacity(0.25))
                .overlay { Circle().strokeBorder(Color.yellow, lineWidth: 2) }
                .frame(width: 26, height: 26)
                .position(x: padSize * CGFloat(color + 1) / 2, y: padSize * CGFloat(1 - tone) / 2)
        }
        .frame(width: padSize, height: padSize)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let x = min(max(value.location.x / padSize, 0), 1)
                    let y = min(max(value.location.y / padSize, 0), 1)
                    vm.setStylePad(tone: Double(1 - y * 2), color: Double(x * 2 - 1))
                }
        )
        .onTapGesture(count: 2) { vm.resetStylePad() }
        .sensoryFeedback(.selection, trigger: isCentered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tone and color pad")
        .accessibilityValue("Tone \(Int(tone * 100)), color \(Int(color * 100))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: vm.setStylePad(tone: tone + 0.1, color: color)
            case .decrement: vm.setStylePad(tone: tone - 0.1, color: color)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "More color") { vm.setStylePad(tone: tone, color: color + 0.1) }
        .accessibilityAction(named: "Less color") { vm.setStylePad(tone: tone, color: color - 0.1) }
        .accessibilityAction(named: "Reset") { vm.resetStylePad() }
    }

    private func readout(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value == 0 ? "0" : String(format: "%+ld", Int((value * 100).rounded())))
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(value == 0 ? .white : .yellow)
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.showStylesPad = false }
    }
}
