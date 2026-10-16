import Foundation

/// What's needed to reopen the last photo or video exactly as it was left.
struct SessionState: Codable, Equatable {
    enum Kind: String, Codable { case photo, video }

    var kind: Kind
    var fileName: String
    var adjustments = PhotoAdjustmentState()
    var mode = CameraMode.photo.rawValue
    var zoom: Double = 1
    var aspect = AspectRatioOption.original.rawValue
    var panX: Double = 0
    var panY: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0
}

/// Keeps one copy of the last imported media plus its state in Application Support (inside the
/// app's private container; nothing leaves the device). Replaced on every import.
struct SessionStore: Sendable {
    let directory: URL

    static let standard = SessionStore(directory: URL.applicationSupportDirectory
        .appendingPathComponent("LastSession", isDirectory: true))

    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    func mediaURL(for state: SessionState) -> URL {
        directory.appendingPathComponent(state.fileName)
    }

    /// Replaces the stored media with a photo's original bytes or a copy of a video file.
    func saveMedia(photoData: Data?, videoURL: URL?, fileName: String) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        if let photoData {
            try photoData.write(to: destination, options: .atomic)
        } else if let videoURL {
            try fileManager.copyItem(at: videoURL, to: destination)
        }
    }

    func saveState(_ state: SessionState) throws {
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    /// The saved state, if its media file is still there.
    func loadState() -> SessionState? {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SessionState.self, from: data),
              FileManager.default.fileExists(atPath: mediaURL(for: state).path) else { return nil }
        return state
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
