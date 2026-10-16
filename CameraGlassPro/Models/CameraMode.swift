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
        case .video: "Preview only: shows 16:9 framing. This app does not record video."
        case .cinematic: "Preview only: shows 2.39:1 framing. No video or depth capture."
        case .pano: "Preview only: shows a panorama strip guide. No capture."
        }
    }

    /// Landscape band (width / height) drawn as a framing guide in this mode.
    var framingGuideRatio: CGFloat? {
        switch self {
        case .video: 16.0 / 9.0
        case .cinematic: 2.39
        case .pano: 3.0
        case .photo, .portrait: nil
        }
    }

    /// Red center control echoes the video look; the action is still "import".
    var usesRecordStyle: Bool { self == .video || self == .cinematic }
}
