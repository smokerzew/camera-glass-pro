import Foundation
import Photos

/// How Camera Glass edits made inside the Photos app are stored with the photo. Photos keeps the original and
/// this recipe, so the edit can be reopened and changed later in Camera Glass, or reverted in Photos.
enum PhotosEditFormat {
    static let identifier = "com.cameraglass.edit"
    static let version = "1"

    static func encode(_ state: PhotoAdjustmentState) throws -> PHAdjustmentData {
        PHAdjustmentData(formatIdentifier: identifier, formatVersion: version, data: try JSONEncoder().encode(state))
    }

    /// Our own recipes only; anything else (another app's edit) starts from the rendered photo instead.
    static func canHandle(_ data: PHAdjustmentData) -> Bool {
        data.formatIdentifier == identifier
    }

    /// The saved recipe (tolerant: unknown or missing values fall back to defaults), or nil if it isn't ours.
    static func decode(_ data: PHAdjustmentData) -> PhotoAdjustmentState? {
        guard canHandle(data) else { return nil }
        return (try? JSONDecoder().decode(PhotoAdjustmentState.self, from: data.data))?.clamped()
    }
}
