import AVFoundation
import SwiftUI

/// The viewfinder: the photo fills the available area (iOS Camera style), with composition guides on top.
/// Overlays share the viewfinder frame with the image so they stay aligned at every zoom.
struct PhotoPreviewView: View {
    @Bindable var vm: CameraWorkspaceViewModel

    @AppStorage(SettingsKey.gridOpacity) private var gridOpacity = 0.45
    @AppStorage(SettingsKey.showCenter) private var showCenter = false
    @AppStorage(SettingsKey.showModeGuides) private var showModeGuides = true
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var pinchStartZoom: CGFloat?
    @State private var motion = MotionLevel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let mediaSize = vm.mediaSize {
                    let frame = FramingGeometry.frameSize(ratio: vm.previewRatio, in: proxy.size)
                    viewfinder(mediaSize: mediaSize, frame: frame)
                        .frame(width: frame.width, height: frame.height)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                        .id(vm.photo?.id ?? vm.video?.id)
                } else {
                    EmptyStateView(vm: vm)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15), value: vm.previewRatio)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: vm.photo?.id ?? vm.video?.id)
            .onAppear { updateViewfinderRatio(proxy.size) }
            .task(id: vm.showLevel) {
                // Motion updates run only while the level is visible.
                if vm.showLevel { motion.start() } else { motion.stop() }
            }
            .onDisappear { motion.stop() }
            .onChange(of: proxy.size) { _, size in updateViewfinderRatio(size) }
        }
    }

    private func updateViewfinderRatio(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        vm.viewfinderRatio = size.width / size.height
    }

    /// The photo, or the playing video, sized with the same framing math so zoom and guides behave alike.
    @ViewBuilder
    private var mediaContent: some View {
        if let player = vm.player {
            ZStack {
                PlayerLayerView(player: player)
                if let frame = vm.snapshotFrame {
                    Image(decorative: frame, scale: 1).resizable()
                }
            }
        } else if let image = vm.displayedImage {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                if vm.focusPeaking, let peaking = vm.peakingImage {
                    Image(decorative: peaking, scale: 1)
                        .resizable()
                        .transition(.opacity)
                }
            }
        }
    }

    private func viewfinder(mediaSize: CGSize, frame: CGSize) -> some View {
        let scale = FramingGeometry.baseScale(image: mediaSize, frame: frame, fill: true)
        return ZStack {
            mediaContent
                .frame(width: mediaSize.width * scale, height: mediaSize.height * scale)
                .scaleEffect(vm.zoom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(vm.video != nil ? "Imported video" : (vm.showOriginal ? "Imported photo, original" : "Imported photo preview"))
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
            if vm.mode == .portrait || vm.depthEffect { PortraitVignette() }
            if showModeGuides, let ratio = vm.mode.framingGuideRatio { ModeFramingGuide(ratio: ratio) }
            CameraGridOverlay(style: vm.gridStyle, opacity: gridOpacity)
            if vm.showLevel { CameraLevelGuide(angle: motion.angle, isUpright: motion.isUpright) }
            if showCenter { CenterGuide() }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.gridStyle)
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

/// Small yellow capsule label, as the Camera app uses for PORTRAIT / NATURAL LIGHT.
struct CameraTag: View {
    let text: String
    /// White tag for "off" states (e.g. PORTRAIT OFF), yellow otherwise.
    var isOff = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOff ? Color.white : Color.yellow, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                Text("Import a photo or video")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Tap the shutter to choose a photo or video. Nothing is captured or uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: 420)
    }
}

/// AVPlayerLayer host. The layer is sized by SwiftUI to the media's own aspect, so `.resize` never distorts.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // layerClass guarantees the type
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resize
        view.playerLayer.player = player
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
