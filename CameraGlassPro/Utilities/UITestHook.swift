import Foundation

/// UI tests pass a sample photo as base64 in the launch environment (`UITEST_PHOTO_B64`); the app writes it to a
/// temporary file and opens it. Normal launches never have this variable, so nothing changes for users.
enum UITestHook {
    static func photoURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let encoded = environment["UITEST_PHOTO_B64"], let data = Data(base64Encoded: encoded), !data.isEmpty
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-photo.jpg")
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }
}
