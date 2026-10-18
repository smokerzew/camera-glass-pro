import Photos
import ReplayKit
import UIKit

/// "Save Screen with UI": snapshots the app window exactly as shown (photo + camera controls)
/// and adds it to the photo library with add-only permission.
enum ScreenCapture {
    enum CaptureError: LocalizedError {
        case noWindow, notAllowed, recordingUnavailable

        var errorDescription: String? {
            switch self {
            case .noWindow: "The screen couldn't be captured."
            case .notAllowed: "Allow “Add Photos Only” access for Camera Glass in Settings › Privacy & Security › Photos."
            case .recordingUnavailable: "Screen recording isn't available right now (it may be in use or restricted)."
            }
        }
    }

    @MainActor
    static func captureKeyWindow() throws -> UIImage {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else {
            throw CaptureError.noWindow
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    static func saveToPhotos(_ image: UIImage) async throws {
        try await requestAddAccess()
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    /// Saves encoded image data as-is (PNG keeps transparency, e.g. stickers; HEIF/JPEG for frames).
    static func saveImageDataToPhotos(_ data: Data) async throws {
        try await requestAddAccess()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }

    @MainActor
    static func copyPNG(_ data: Data) {
        UIPasteboard.general.setData(data, forPasteboardType: "public.png")
    }

    static func saveVideoToPhotos(_ url: URL) async throws {
        try await requestAddAccess()
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    private static func requestAddAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CaptureError.notAllowed }
    }

    // MARK: "Save Video with UI" (ReplayKit in-app recording: app screen + app audio, no microphone)

    @MainActor
    static func startRecording() async throws {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { throw CaptureError.recordingUnavailable }
        recorder.isMicrophoneEnabled = false
        try await recorder.startRecording()
    }

    @MainActor
    static func stopRecording() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraGlass-Screen-\(UUID().uuidString).mov")
        try await RPScreenRecorder.shared().stopRecording(withOutput: url)
        return url
    }
}
