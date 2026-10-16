import SwiftUI

/// Large import control, thumbnail (opens adjustments), mode selector and export.
struct CameraBottomControls: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.cameraReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            Text(vm.mode.explanation)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)
                .opacity(vm.mode.isPreviewOnly ? 1 : 0) // reserves space so the layout doesn't jump
                .accessibilityHidden(!vm.mode.isPreviewOnly)

            ImportControl(vm: vm)

            HStack(spacing: 12) {
                thumbnail
                CameraModeSelector(selection: $vm.mode)
                GlassIconButton(
                    systemImage: "square.and.arrow.up",
                    label: "Export photo",
                    hint: "Share or save the original or an edited copy",
                    size: 52
                ) { vm.showExport = true }
                .disabled(vm.photo == nil)
                .opacity(vm.photo == nil ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.mode)
    }

    private var thumbnail: some View {
        Button { vm.showAdjustments = true } label: {
            ZStack(alignment: .bottomTrailing) {
                if let image = vm.displayedImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                } else {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 52, height: 52)
                        .cameraGlass(.regular, in: Circle())
                }
                if vm.hasEdits {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(4)
                        .background(.yellow, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(vm.photo == nil)
        .accessibilityLabel("Adjust photo")
        .accessibilityValue(vm.photo == nil ? "No photo" : (vm.hasEdits ? "Edited" : "No edits"))
        .accessibilityHint("Opens exposure, color and light adjustments")
    }
}

/// The big circular control. It imports or replaces a photo; it never claims to take one.
struct ImportControl: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        Button { vm.primaryAction() } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 80, height: 80)
                Circle()
                    .fill(vm.mode.usesRecordStyle ? Color.red : .white)
                    .frame(width: 66, height: 66)
                Image(systemName: vm.countdown == nil ? "plus" : "xmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(vm.mode.usesRecordStyle ? Color.white : Color.black.opacity(0.55))
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button("Choose from Photos", systemImage: "photo.on.rectangle") { vm.showPhotosPicker = true }
            Button("Browse Files", systemImage: "folder") { vm.showFileImporter = true }
        }
        .accessibilityLabel(vm.countdown != nil ? "Cancel timer" : (vm.photo == nil ? "Import photo" : "Replace photo"))
        .accessibilityHint(vm.timer == .off
            ? "Opens the photo picker. Touch and hold for Files."
            : "Opens the photo picker after \(vm.timer.rawValue) seconds")
    }
}
