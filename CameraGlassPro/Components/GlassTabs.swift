import SwiftUI

/// Small capsule tabs used inside the glass pop-ups and the controls panel to split long content into pages.
struct GlassTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        // Many tabs scroll sideways instead of squeezing.
        if tabs.count > 5 {
            ScrollView(.horizontal, showsIndicators: false) { row(minWidth: 70) }
        } else {
            row(minWidth: nil)
        }
    }

    private func row(minWidth: CGFloat?) -> some View {
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
                        .padding(.horizontal, minWidth == nil ? 0 : 10)
                        .frame(minWidth: minWidth, maxWidth: minWidth == nil ? .infinity : nil, minHeight: 32)
                        .cameraGlass(selected ? .selected : .interactive, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(tab))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Shows one page at a time but keeps every page laid out (invisible), so the card keeps the height of its
/// tallest page: switching pages never makes the card, or the photo above it, jump.
struct PagedStack<Page: Hashable, Content: View>: View {
    let pages: [Page]
    let selection: Page
    @ViewBuilder let content: (Page) -> Content

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(pages, id: \.self) { page in
                let shown = page == selection
                content(page)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
        }
    }
}

/// Small "Reset" text button for one area of the edit (yellow when there is something to reset).
struct AreaResetButton: View {
    @Bindable var vm: CameraWorkspaceViewModel
    let area: ResetArea
    var onDark = true

    var body: some View {
        let active = vm.adjustments.canReset(area)
        Button(area.title) { vm.reset(area) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? Color.yellow : (onDark ? Color.white.opacity(0.4) : Color.secondary))
            .disabled(!active)
            .accessibilityHint("Resets only this part of the edit")
    }
}

/// Dice button that shuffles only one area's settings.
struct AreaShuffleButton: View {
    @Bindable var vm: CameraWorkspaceViewModel
    let area: ResetArea
    var category: FilterCategory? = nil
    var onDark = true

    var body: some View {
        Button { vm.shuffle(area, category: category) } label: {
            Image(systemName: "dice")
                .font(.body.weight(.semibold))
                .foregroundStyle(onDark ? Color.white : Color.primary)
                .frame(width: 44, height: 32)
        }
        .disabled(!vm.hasMedia)
        .accessibilityLabel("Shuffle")
        .accessibilityHint("Randomizes only the settings on this tab")
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
