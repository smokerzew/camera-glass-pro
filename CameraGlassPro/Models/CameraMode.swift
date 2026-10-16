import Foundation

/// Modes in the camera-style selector. PHOTO edits photos; VIDEO, SLO-MO and TIME-LAPSE play
/// imported videos (at 1×, ¼× and 8×) and export at that speed. The rest are preview looks and say so.
enum CameraMode: String, CaseIterable, Identifiable {
    case timeLapse, sloMo, cinematic, video, photo, portrait, pano

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeLapse: "TIME-LAPSE"
        case .sloMo: "SLO-MO"
        default: rawValue.uppercased()
        }
    }

    var isPreviewOnly: Bool { self == .cinematic || self == .portrait || self == .pano }

    var explanation: String {
        switch self {
        case .photo: "Import, frame, adjust and export a photo."
        case .portrait: "Preview only: adds a soft vignette. No depth capture."
        case .video: "Plays imported videos. This app does not record video."
        case .sloMo: "Plays imported videos at ¼ speed; the edited copy exports slowed down."
        case .timeLapse: "Plays imported videos 8× faster; the edited copy exports sped up."
        case .cinematic: "Preview only: plays imported videos. No video or depth capture."
        case .pano: "Preview only. No panorama capture."
        }
    }

    /// Red center control echoes the video look; with a video loaded it plays/pauses.
    var usesRecordStyle: Bool { self == .video || self == .cinematic || self == .sloMo || self == .timeLapse }

    /// Playback and export speed for imported videos in this mode.
    var playbackRate: Float {
        switch self {
        case .sloMo: 0.25
        case .timeLapse: 8
        default: 1
        }
    }
}
