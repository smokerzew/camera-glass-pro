import SwiftUI

/// Small capsule tabs used inside the glass pop-ups and the controls panel to split long content into pages.
struct GlassTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.self) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    Text(title(tab).uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Color.yellow : .white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .cameraGlass(selected ? .selected : .interactive, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(tab))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A labeled slider row in the pop-ups' style (caption, yellow slider, value).
struct GlassSliderRow: View {
    let title: String
    let value: Double
    var range: ClosedRange<Double> = 0...1
    var display: (Double) -> String = { "\(Int(($0 * 100).rounded()))" }
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 92, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .tint(.yellow)
                .accessibilityLabel(title)
                .accessibilityValue(display(value))
            Text(display(value))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(value == range.lowerBound ? Color.white.opacity(0.6) : Color.yellow)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
