import Photos
import PhotosUI
import SwiftUI

/// Live Photo helpers: pulls the paired motion clip out of a picked Live Photo, and shows its playback.
enum LivePhotoSupport {
    static func isLivePhoto(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .livePhoto) }
    }

    /// Writes the Live Photo's paired video to app storage (used for Loop, Bounce and Long Exposure).
    static func extractPairedVideo(from livePhoto: PHLivePhoto) async throws -> URL? {
        guard let resource = PHAssetResource.assetResources(for: livePhoto).first(where: { $0.type == .pairedVideo }) else {
            return nil
        }
        try FileManager.default.createDirectory(at: VideoService.directory, withIntermediateDirectories: true)
        let url = VideoService.directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: nil)
        return url
    }
}

/// PHLivePhotoView host that plays the motion (with sound) while `isPlaying` is true.
struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let isPlaying: Bool

    final class Coordinator {
        var playing = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
        guard context.coordinator.playing != isPlaying else { return }
        context.coordinator.playing = isPlaying
        if isPlaying { view.startPlayback(with: .full) } else { view.stopPlayback() }
    }
}
