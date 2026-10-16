import Photos
import UIKit

/// "Save Screen with UI": snapshots the app window exactly as shown (photo + camera controls)
/// and adds it to the photo library with add-only permission.
enum ScreenCapture {
    enum CaptureError: LocalizedError {
        case noWindow, notAllowed

        var errorDescription: String? {
            switch self {
            case .noWindow: "The screen couldn't be captured."
            case .notAllowed: "Allow “Add Photos Only” access for Camera Glass in Settings › Privacy & Security › Photos."
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
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CaptureError.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
