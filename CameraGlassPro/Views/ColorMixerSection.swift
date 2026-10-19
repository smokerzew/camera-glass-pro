import SwiftUI

/// Color Mixer: pick one of eight colors, then shift its hue, saturation and luminance.
struct ColorMixerSection: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @State private var band: ColorBand = .red

    private func swatch(_ band: ColorBand) -> Color {
        Color(hue: band.hue / 360, saturation: 0.85, brightness: 0.95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Color Mixer", systemImage: "paintpalette")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Reset") { vm.resetMixer() }
                    .font(.subheadline)
                    .disabled(vm.adjustments.colorMixer.isNeutral)
            }

            HStack(spacing: 0) {
                ForEach(ColorBand.allCases) { item in
                    Button { band = item } label: {
                        Circle()
                            .fill(swatch(item))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white, lineWidth: band == item ? 2.5 : 0).padding(-4))
                            .overlay(alignment: .topTrailing) {
                                if vm.adjustments.colorMixer.isModified(item) {
                                    Circle().fill(Color.yellow).frame(width: 7, height: 7).offset(x: 3, y: -3)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(band == item ? .isSelected : [])
                    .accessibilityValue(vm.adjustments.colorMixer.isModified(item) ? "Edited" : "")
                }
            }

            ForEach(MixerChannel.allCases) { channel in
                let value = vm.adjustments.colorMixer[band, channel]
                VStack(spacing: 4) {
                    HStack {
                        Text(channel.label).font(.subheadline)
                        Spacer()
                        Text(value == 0 ? "0" : String(format: "%+d", Int((value * 100).rounded())))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(value == 0 ? Color.secondary : Color.yellow)
                    }
                    Slider(value: Binding(get: { vm.adjustments.colorMixer[band, channel] },
                                          set: { vm.setMixer(band, channel, to: $0) }), in: -1...1)
                        .tint(swatch(band))
                        .accessibilityLabel("\(band.label) \(channel.label)")
                        .accessibilityValue(String(Int((value * 100).rounded())))
                }
            }
        }
    }
}

/// Color Grade in Adjust > Color: a hue and strength for the shadows and for the highlights, and the balance
/// between them. Each hue track shows its colors.
struct ColorGradeSection: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Color Grade", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal")
                .font(.subheadline.weight(.semibold))
            tone("Shadows", hue: \.gradeShadowHue, amount: \.gradeShadowAmount)
            tone("Highlights", hue: \.gradeHighlightHue, amount: \.gradeHighlightAmount)
            row("Balance", value: \.gradeBalance, range: -1...1)
            Text("Tints shadows and highlights separately. Pure black and white stay neutral.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func tone(_ title: String, hue: WritableKeyPath<PhotoAdjustmentState, Double>,
                      amount: WritableKeyPath<PhotoAdjustmentState, Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row(title, value: amount, range: 0...1)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hue: vm.adjustments[keyPath: hue] / 360, saturation: 0.8, brightness: 0.95))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { vm.adjustments[keyPath: hue] }, set: { vm.setEffect(hue, to: min(max($0, 0), 360)) }),
                       in: 0...360)
                    .tint(Color(hue: vm.adjustments[keyPath: hue] / 360, saturation: 0.8, brightness: 0.95))
                    .accessibilityLabel("\(title) hue")
                    .accessibilityValue("\(Int(vm.adjustments[keyPath: hue])) degrees")
            }
        }
    }

    private func row(_ title: String, value: WritableKeyPath<PhotoAdjustmentState, Double>, range: ClosedRange<Double>) -> some View {
        let current = vm.adjustments[keyPath: value]
        return VStack(spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(current == 0 ? "0" : String(format: range.lowerBound < 0 ? "%+d" : "%d", Int((current * 100).rounded())))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(current == 0 ? .secondary : Color.yellow)
            }
            Slider(value: Binding(get: { vm.adjustments[keyPath: value] }, set: { vm.setEffect(value, to: min(max($0, range.lowerBound), range.upperBound)) }),
                   in: range)
                .tint(.yellow)
                .accessibilityLabel(title)
        }
    }
}
