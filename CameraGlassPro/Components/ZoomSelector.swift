import SwiftUI

/// Camera-style ".5  1×  2  5" pill. Tapping the selected value toggles the fine slider.
struct ZoomSelector: View {
    let zoom: CGFloat
    let onSelect: (CGFloat) -> Void
    let onToggleSlider: () -> Void

    @Environment(\.cameraReduceMotion) private var reduceMotion
    @Namespace private var selection

    private var activePreset: CGFloat {
        ZoomLimits.presets.last { $0 <= zoom + 0.001 } ?? ZoomLimits.minimum
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ZoomLimits.presets, id: \.self) { preset in
                let isActive = preset == activePreset
                Button {
                    isActive ? onToggleSlider() : onSelect(preset)
                } label: {
                    Text(isActive ? ZoomLimits.label(for: zoom) + "×" : ZoomLimits.label(for: preset))
                        .font(.system(size: isActive ? 13 : 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? Color.yellow : .white)
                        .frame(width: isActive ? 40 : 32, height: isActive ? 40 : 32)
                        .background {
                            if isActive {
                                Circle()
                                    .fill(.black.opacity(0.45))
                                    .matchedGeometryEffect(id: "zoom", in: selection)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Preview zoom \(ZoomLimits.label(for: preset)) times")
                .accessibilityHint(isActive ? "Shows the fine zoom slider" : "Zooms the preview")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .cameraGlass(.regular, in: Capsule())
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2), value: activePreset)
    }
}
