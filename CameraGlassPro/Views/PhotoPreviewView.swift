import AVFoundation
import SwiftUI

/// The viewfinder: the photo fills the available area (iOS Camera style), with composition guides on top.
/// Overlays share the viewfinder frame with the image so they stay aligned at every zoom.
struct PhotoPreviewView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    /// Shared with the workspace (also drives icon rotation).
    let motion: MotionLevel

    @AppStorage(SettingsKey.gridOpacity) private var gridOpacity = 0.45
    @AppStorage(SettingsKey.showCenter) private var showCenter = false
    @Environment(\.cameraReduceMotion) private var reduceMotion
    @State private var pinchStartZoom: CGFloat?
    @State private var panStart: CGPoint?
    /// Decided on a drag's first move: sliding the ☀︎ exposure, or panning/swiping.
    @State private var dragIsExposure: Bool?
    /// Where the current touch started (used for the long-press AE/AF lock position).
    @State private var touchStart: CGPoint?

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
                if vm.focusPeaking || vm.zebras, let overlay = vm.overlayImage {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .transition(.opacity)
                }
            }
        }
    }

    /// Yellow boxes over recognized text; tap one to copy that line.
    private var liveTextBoxes: some View {
        GeometryReader { geometry in
            ForEach(vm.recognizedText) { line in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.yellow.opacity(0.18))
                    .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.yellow, lineWidth: 1.5) }
                    .frame(width: line.box.width * geometry.size.width + 6,
                           height: line.box.height * geometry.size.height + 4)
                    .position(x: line.box.midX * geometry.size.width, y: line.box.midY * geometry.size.height)
                    .onTapGesture { vm.copyText(line) }
            }
        }
    }

    private func viewfinder(mediaSize: CGSize, frame: CGSize) -> some View {
        let scale = FramingGeometry.baseScale(image: mediaSize, frame: frame, fill: true)
        let maxOffset = FramingGeometry.maxOffset(image: mediaSize, frame: frame, zoom: vm.zoom, fill: true)
        return ZStack {
            mediaContent
                .overlay { if vm.liveTextEnabled && !vm.isPlaying { liveTextBoxes } }
                .frame(width: mediaSize.width * scale, height: mediaSize.height * scale)
                .scaleEffect(vm.zoom)
                .offset(x: vm.pan.x * maxOffset.width, y: vm.pan.y * maxOffset.height)
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

            if let point = vm.focusPoint {
                FocusBox(exposure: vm.adjustments.exposure, isDimmed: vm.isFocusDimmed,
                         isDragging: vm.isDraggingExposure, pulse: vm.focusPulse)
                    .position(point)
                    .transition(.opacity)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(magnification)
        .simultaneousGesture(panGesture(maxOffset: maxOffset))
        .onTapGesture(count: 2) {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                vm.setZoom(1)
                vm.setPan(.zero)
            }
        }
        .accessibilityAction(named: "Pan left") { vm.setPan(CGPoint(x: vm.pan.x + 0.25, y: vm.pan.y)) }
        .accessibilityAction(named: "Pan right") { vm.setPan(CGPoint(x: vm.pan.x - 0.25, y: vm.pan.y)) }
        .accessibilityAction(named: "Pan up") { vm.setPan(CGPoint(x: vm.pan.x, y: vm.pan.y + 0.25)) }
        .accessibilityAction(named: "Pan down") { vm.setPan(CGPoint(x: vm.pan.x, y: vm.pan.y - 0.25)) }
        .onTapGesture(coordinateSpace: .local) { location in
            if vm.isControlPanelOpen || vm.showFilterPicker || vm.showStylesPad {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                    vm.isControlPanelOpen = false
                    vm.showFilterPicker = false
                    vm.showStylesPad = false
                }
                return
            }
            // Tap to focus/expose.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                vm.focus(atView: location, mediaPoint: FramingGeometry.mediaPoint(
                    tap: location, frame: frame, media: mediaSize, zoom: vm.zoom, pan: vm.pan), lock: false)
            }
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            // Touch and hold: AE/AF LOCK at the touch point.
            guard let location = touchStart else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                vm.focus(atView: location, mediaPoint: FramingGeometry.mediaPoint(
                    tap: location, frame: frame, media: mediaSize, zoom: vm.zoom, pan: vm.pan), lock: true)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
            if touchStart != value.startLocation { touchStart = value.startLocation }
        })
        .accessibilityAction(named: "Focus and expose here") {
            vm.focus(atView: CGPoint(x: frame.width / 2, y: frame.height / 2),
                     mediaPoint: CGPoint(x: 0.5, y: 0.5), lock: false)
        }
    }

    /// Guides sit above the image and below the controls; none of them touch image data.
    private var overlayLayer: some View {
        ZStack {
            if vm.mode == .portrait || vm.depthEffect { PortraitVignette() }
            CameraGridOverlay(style: vm.gridStyle, opacity: gridOpacity)
            if vm.showLevel { CameraLevelGuide(angle: motion.levelAngle, isUpright: motion.isUpright).rotatesWithDevice() }
            if showCenter { CenterGuide() }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.gridStyle)
    }

    /// Drag to move around zoomed media; stops at the edges so no background shows.
    private func panGesture(maxOffset: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // With the focus box up, a mostly vertical drag slides the ☀︎ exposure instead.
                if dragIsExposure == nil {
                    dragIsExposure = vm.focusPoint != nil
                        && abs(value.translation.height) > abs(value.translation.width)
                    if dragIsExposure == true { vm.beginExposureDrag() }
                }
                if dragIsExposure == true {
                    vm.updateExposureDrag(by: value.translation.height)
                    return
                }
                guard maxOffset.width > 0 || maxOffset.height > 0 else { return }
                let start = panStart ?? vm.pan
                panStart = start
                let dx = maxOffset.width > 0 ? value.translation.width / maxOffset.width : 0
                let dy = maxOffset.height > 0 ? value.translation.height / maxOffset.height : 0
                vm.setPan(CGPoint(x: start.x + dx, y: start.y + dy))
            }
            .onEnded { value in
                panStart = nil
                if dragIsExposure == true {
                    dragIsExposure = nil
                    vm.endExposureDrag()
                    return
                }
                dragIsExposure = nil
                // Not zoomed in: a sideways swipe moves through a multi-selection.
                guard maxOffset.width <= 0, vm.library.count > 1,
                      abs(value.translation.width) > 60,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { vm.showNext() } else { vm.showPrevious() }
            }
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
