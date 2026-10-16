import AVFoundation
import SwiftUI

/// Picture-in-picture shown at high zoom (as in the iOS Camera app): a small rounded view of the
/// wider scene with a yellow rectangle marking where the viewfinder is zoomed in.
struct ZoomMiniMap: View {
    @Bindable var vm: CameraWorkspaceViewModel

    static let size = CGSize(width: 104, height: 139) // 3:4

    var body: some View {
        if let mediaSize = vm.mediaSize, vm.zoom >= FramingGeometry.miniMapThreshold {
            let map = FramingGeometry.miniMap(image: mediaSize, frameRatio: vm.previewRatio,
                                              zoom: vm.zoom, pan: vm.pan,
                                              miniRatio: Self.size.width / Self.size.height)
            let scale = Self.size.width / max(map.region.width, 1)

            ZStack(alignment: .topLeading) {
                media
                    .frame(width: mediaSize.width * scale, height: mediaSize.height * scale)
                    .offset(x: -map.region.minX * scale, y: -map.region.minY * scale)

                Rectangle()
                    .strokeBorder(.yellow, lineWidth: 1.5)
                    .frame(width: max(6, map.highlight.width * Self.size.width),
                           height: max(6, map.highlight.height * Self.size.height))
                    .offset(x: map.highlight.minX * Self.size.width, y: map.highlight.minY * Self.size.height)
            }
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zoom overview")
            .accessibilityValue("Showing the zoomed area within the wider view")
        }
    }

    /// Same media as the viewfinder: the photo, or a second layer on the same video player.
    @ViewBuilder
    private var media: some View {
        if let player = vm.player {
            PlayerLayerView(player: player)
        } else if let image = vm.displayedImage {
            Image(decorative: image, scale: 1).resizable()
        }
    }
}
