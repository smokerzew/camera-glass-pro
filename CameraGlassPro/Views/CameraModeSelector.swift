import SwiftUI

/// Horizontally scrolling mode capsule. Only PHOTO is functional; the others are labeled preview looks.
struct CameraModeSelector: View {
    @Binding var selection: CameraMode
    /// Tapping the already-selected mode opens Camera Controls, as in iOS 27.
    var onReselect: () -> Void = {}
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @Environment(\.cameraLargeLabels) private var largeLabels
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(CameraMode.allCases) { mode in
                        let isSelected = mode == selection
                        Button { if isSelected { onReselect() } else { selection = mode } } label: {
                            Text(mode.title)
                                .font(.system(size: largeLabels ? 16 : 14, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? Color.yellow : .white.opacity(0.9))
                                .padding(.horizontal, 16)
                                .frame(minHeight: 40)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(.black.opacity(0.45))
                                            .matchedGeometryEffect(id: "mode", in: namespace)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .id(mode)
                        .accessibilityLabel(mode.rawValue.capitalized)
                        .accessibilityValue(mode.isPreviewOnly ? "Preview only" : "")
                        .accessibilityHint(isSelected ? "Opens camera controls" : mode.explanation)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            .onChange(of: selection, initial: true) { _, mode in
                withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(mode, anchor: .center) }
            }
        }
        .frame(height: 48)
        .clipShape(Capsule())
        .cameraGlass(.regular, in: Capsule())
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }
}
