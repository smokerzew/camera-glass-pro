import UIKit
import XCTest
@testable import CameraGlassPro

@MainActor
final class LibraryAndSessionTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "Library-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func writePNG(_ color: UIColor) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: url)
        return url
    }

    /// Waits (up to 10 s) for an async import to land.
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        var attempts = 0
        while !condition() && attempts < 200 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(condition(), "timed out waiting for import")
    }

    func testSwipingKeepsEachItemsEdits() async throws {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        let first = try writePNG(.red)
        let second = try writePNG(.blue)
        vm.importFromFiles(.success([first, second]))
        try await waitUntil { vm.photo != nil && !vm.isImporting }
        XCTAssertEqual(vm.library.count, 2)
        XCTAssertFalse(vm.hasPrevious)

        vm.setAdjustment(.exposure, to: 1)
        let firstPhoto = vm.photo?.id
        vm.showNext()
        try await waitUntil { vm.photo?.id != firstPhoto && !vm.isImporting }
        XCTAssertEqual(vm.libraryIndex, 1)
        XCTAssertEqual(vm.adjustments.exposure, 0, "the second item starts unedited")

        let secondPhoto = vm.photo?.id
        vm.showPrevious()
        try await waitUntil { vm.photo?.id != secondPhoto && !vm.isImporting }
        XCTAssertEqual(vm.adjustments.exposure, 1, "the first item's edit comes back")
    }

    func testSessionStoreRoundTrip() throws {
        let store = SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertNil(store.loadState())
        try store.saveMedia(photoData: Data([1, 2, 3]), videoURL: nil, fileName: "media.png")
        var state = SessionState(kind: .photo, fileName: "media.png")
        state.adjustments.warmth = 0.4
        state.zoom = 2
        try store.saveState(state)
        XCTAssertEqual(store.loadState(), state)
        store.clear()
        XCTAssertNil(store.loadState())
    }

    func testRelaunchRestoresLastPhotoAndEdits() async throws {
        let store = SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults(), sessionStore: store)
        vm.importFromFiles(.success([try writePNG(.green)]))
        try await waitUntil { vm.photo != nil && !vm.isImporting }
        try await waitUntil { store.loadState() != nil } // the background media copy has finished
        vm.setAdjustment(.contrast, to: 1.3)
        vm.setZoom(2)
        vm.saveSessionState()

        let relaunched = CameraWorkspaceViewModel(defaults: makeDefaults(), sessionStore: store)
        relaunched.restoreLastSession()
        try await waitUntil { relaunched.photo != nil && !relaunched.isImporting }
        XCTAssertEqual(relaunched.adjustments.contrast, 1.3, accuracy: 0.0001)
        XCTAssertEqual(relaunched.zoom, 2)
    }
}
