import SwiftUI

/// The viewfinder: photo, composition overlays and the empty state.
/// Overlays share the viewfinder frame with the image so they stay aligned at every zoom.
struct PhotoPreviewView: View {
    @Bindable var vm: CameraWorkspaceViewModel

    @AppStorage(SettingsKey.gridStyle) private var gridStyle = GridStyle.off
    @AppStorage(SettingsKey.gridOpacity) private var gridOpacity = 0.45
    @AppStorage(SettingsKey.showLevel) private var showLevel = false
    @AppStorage(SettingsKey.showCenter) private var showCenter = false
    @AppStorage(SettingsKey.showModeGuides) private var showModeGuides = true
    @AppStorage(SettingsKey.showImportedBadge) private var showImportedBadge = true
    @AppStorage(SettingsKey.imageFit) private var imageFit = ImageFit.fill
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var pinchStartZoom: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = vm.displayedImage, let photo = vm.photo {
                    let frame = FramingGeometry.frameSize(ratio: vm.previewRatio, in: proxy.size)
                    viewfinder(image: image, imageSize: photo.previewSize, frame: frame)
                        .frame(width: frame.width, height: frame.height)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                        .id(photo.id)
                } else {
                    EmptyStateView(vm: vm)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15), value: vm.previewRatio)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: vm.photo?.id)
        }
    }

    private func viewfinder(image: CGImage, imageSize: CGSize, frame: CGSize) -> some View {
        let scale = FramingGeometry.baseScale(image: imageSize, frame: frame, fill: imageFit == .fill)
        return ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                .scaleEffect(vm.zoom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(vm.showOriginal ? "Imported photo, original" : "Imported photo preview")
                .accessibilityValue("\(ZoomLimits.label(for: vm.zoom)) times zoom, \(vm.aspect.label) framing")
                .accessibilityHint("Swipe up or down to change preview zoom")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: vm.setZoom(vm.zoom + 0.5)
                    case .decrement: vm.setZoom(vm.zoom - 0.5)
                    @unknown default: break
                    }
                }

            overlayLayer
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(magnification)
        .onTapGesture(count: 2) {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.setZoom(1) }
        }
        .onTapGesture {
            if vm.isControlPanelOpen {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { vm.isControlPanelOpen = false }
            }
        }
    }

    /// Guides sit above the image and below the controls; none of them touch image data.
    private var overlayLayer: some View {
        ZStack {
            if vm.mode == .portrait { PortraitVignette() }
            if showModeGuides, let ratio = vm.mode.framingGuideRatio { ModeFramingGuide(ratio: ratio) }
            CameraGridOverlay(style: gridStyle, opacity: gridOpacity)
            if showLevel { CameraLevelGuide() }
            if showCenter { CenterGuide() }

            VStack {
                HStack(alignment: .top) {
                    if vm.livePreference {
                        GlassPill(text: "LIVE", systemImage: "livephoto")
                            .accessibilityLabel("Live preference on. Imported photos are still images.")
                    }
                    Spacer()
                    if vm.showOriginal {
                        GlassPill(text: "ORIGINAL")
                    } else if showImportedBadge {
                        GlassPill(text: "IMPORTED PHOTO", systemImage: "square.and.arrow.down")
                    }
                }
                Spacer()
            }
            .padding(10)
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: gridStyle)
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartZoom ?? vm.zoom
                pinchStartZoom = start
                vm.setZoom(start * value.magnification)
            }
            .onEnded { _ in pinchStartZoom = nil }
    }
}

struct EmptyStateView: View {
    @Bindable var vm: CameraWorkspaceViewModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 112, height: 112)
                .cameraGlass(.subtle, in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Import a photo to begin")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Frame, adjust and export your existing photos with camera-style controls. Nothing is captured or uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            GlassGroup(spacing: 10) {
                VStack(spacing: 10) {
                    Button { vm.showPhotosPicker = true } label: {
                        Label("Import Photo", systemImage: "photo.badge.plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 26)
                            .frame(minHeight: 50)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityHint("Opens the system photo picker")

                    Button { vm.showFileImporter = true } label: {
                        Label("Browse Files", systemImage: "folder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 44)
                            .cameraGlass(.interactive, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityHint("Imports an image from the Files app")
                }
            }
        }
        .frame(maxWidth: 420)
    }
}
