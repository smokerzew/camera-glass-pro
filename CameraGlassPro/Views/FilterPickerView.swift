import SwiftUI

/// Glass filter pop-up (opened by FILTER): category tabs and a row of live preview tiles with names.
/// Same look as the ⠿ panel: grabber, glass card, uppercase captions, yellow for the current choice.
struct FilterPickerView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @Environment(\.cameraLargeLabels) private var largeLabels
    @State private var category: FilterCategory = .classic
    @State private var dragOffset: CGFloat = 0
    @Namespace private var tabSelection

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            HStack {
                Text("FILTERS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button("Done") { close() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 6)

            tabs

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        tile(.none)
                        ForEach(category.filters, id: \.self) { tile($0) }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(vm.adjustments.filter, anchor: .center) }
            }

            // Grain is independent of the filter: 0 means no grain at all.
            HStack(spacing: 10) {
                Text("GRAIN")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: Binding(get: { vm.adjustments.grain }, set: { vm.setAdjustment(.grain, to: $0) }), in: 0...1)
                    .tint(.yellow)
                    .accessibilityLabel("Film grain")
                    .accessibilityValue(vm.adjustments.grain == 0 ? "Off" : "\(Int(vm.adjustments.grain * 100)) percent")
                Text(vm.adjustments.grain == 0 ? "OFF" : "\(Int(vm.adjustments.grain * 100))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(vm.adjustments.grain == 0 ? Color.white.opacity(0.6) : Color.yellow)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 6)

            HStack {
                // Hold to see the untouched original.
                Text("HOLD FOR ORIGINAL")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(vm.showOriginal ? Color.yellow : .white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .cameraGlass(vm.showOriginal ? .selected : .interactive, in: Capsule())
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                        vm.setShowOriginal(pressing)
                    })
                    .opacity(vm.hasEdits ? 1 : 0.4)
                    .allowsHitTesting(vm.hasEdits)
                    .accessibilityRepresentation {
                        Toggle("Show original", isOn: Binding(get: { vm.showOriginal }, set: { vm.setShowOriginal($0) }))
                    }
                Spacer()
                Button("Reset All") {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { vm.resetAllAdjustments() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(vm.hasEdits ? Color.yellow : .white.opacity(0.4))
                .disabled(!vm.hasEdits)
                .accessibilityHint("Removes every adjustment, filter, style and grain")
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: 520)
        .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 80 { close() }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
                }
        )
        .padding(.horizontal, 12)
        .onAppear { category = vm.adjustments.filter.category }
        .onDisappear { vm.setShowOriginal(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filters")
        .accessibilityAction(.escape) { close() }
    }

    /// Category tabs styled like the mode selector: a glass pill behind the selected name.
    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(FilterCategory.allCases) { tab in
                let isSelected = tab == category
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.12)) { category = tab }
                } label: {
                    Text(tab.title.uppercased())
                        .font(.system(size: largeLabels ? 14 : 12, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? Color.yellow : .white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.black.opacity(0.35))
                                    .cameraGlass(.selected, in: Capsule())
                                    .matchedGeometryEffect(id: "tab", in: tabSelection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(.black.opacity(0.25)))
    }

    private func tile(_ filter: PhotoFilter) -> some View {
        let isSelected = vm.adjustments.filter == filter
        return Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { vm.setFilter(filter) }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    if let preview = vm.filterThumbnails[filter] {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.yellow : .white.opacity(0.18), lineWidth: isSelected ? 2 : 0.8)
                }
                .rotatesWithDevice()

                Text(filter == .none ? "ORIGINAL" : filter.label.uppercased())
                    .font(largeLabels ? .footnote.weight(.semibold) : .caption2.weight(.semibold))
                    .tracking(0.9)
                    .foregroundStyle(isSelected ? Color.yellow : .white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 74)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .id(filter)
        .accessibilityLabel(filter == .none ? "Original, no filter" : "\(filter.label) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.showFilterPicker = false }
    }
}
