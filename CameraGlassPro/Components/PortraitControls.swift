import SwiftUI

/// ƒ-number slider for Portrait depth (ƒ1.4 strongest blur … ƒ16 none), in a glass capsule.
struct ApertureSlider: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("ƒ")
                .font(.system(size: 17, weight: .semibold, design: .serif).italic())
                .foregroundStyle(.white)
                .rotatesWithDevice()
            Slider(value: Binding(get: { vm.adjustments.aperture }, set: { vm.setAperture($0) }), in: 1.4...16)
                .tint(.yellow)
                .accessibilityLabel("Depth, f-number")
                .accessibilityValue(String(format: "f %.1f", vm.adjustments.aperture))
            Text(String(format: "%.1f", vm.adjustments.aperture))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(.yellow)
                .frame(width: 38, alignment: .trailing)
                .rotatesWithDevice()
        }
        .padding(.horizontal, 16)
        .frame(width: 280, height: 44)
        .cameraGlass(.regular, in: Capsule())
    }
}

/// Portrait Lighting choices as glass chips (Natural, Studio, Contour, Stage, Stage Mono, High-Key).
struct LightingPicker: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(PortraitLighting.allCases) { lighting in
                        let isSelected = vm.adjustments.lighting == lighting
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.12)) { vm.setLighting(lighting) }
                        } label: {
                            Label(lighting.label.replacingOccurrences(of: " LIGHT", with: ""), systemImage: lighting.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(isSelected ? Color.yellow : .white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(.black.opacity(0.35))
                                            .cameraGlass(.selected, in: Capsule())
                                            .matchedGeometryEffect(id: "lighting", in: selection)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .id(lighting)
                        .accessibilityLabel(lighting.label.capitalized)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            .frame(maxWidth: 340)
            .cameraGlass(.regular, in: Capsule())
            .clipShape(Capsule())
            .onAppear { proxy.scrollTo(vm.adjustments.lighting, anchor: .center) }
        }
    }
}

/// The cube button beside the zoom row that opens Portrait Lighting.
struct LightingButton: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { vm.isLightingPickerVisible.toggle() }
        } label: {
            Image(systemName: "cube.transparent")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.yellow)
                .rotatesWithDevice()
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .shadow(color: .black.opacity(0.4), radius: 2)
        .accessibilityLabel("Portrait Lighting")
        .accessibilityValue(vm.adjustments.lighting.label.capitalized)
    }
}
