import CoreGraphics

/// Modes shown in the camera-style selector. Only `.photo` is a working workflow;
/// the others are preview looks and say so in `explanation`.
enum CameraMode: String, CaseIterable, Identifiable {
    case cinematic, video, photo, portrait, pano

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var isPreviewOnly: Bool { self != .photo }

    var explanation: String {
        switch self {
        case .photo: "Import, frame, adjust and export a photo."
        case .portrait: "Preview only: adds a soft vignette. No depth capture."
        case .video: "Plays imported videos. This app does not record video."
        case .cinematic: "Preview only: plays imported videos. No video or depth capture."
        case .pano: "Preview only. No panorama capture."
        }
    }

    /// Red center control echoes the video look; the action is still "import".
    var usesRecordStyle: Bool { self == .video || self == .cinematic }
}
