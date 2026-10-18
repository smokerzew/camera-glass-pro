import XCTest
@testable import CameraGlassPro

final class AIEditTests: XCTestCase {
    func testRoundTripKeepsTheCurrentEdit() {
        var state = PhotoAdjustmentState()
        state.exposure = 0.4
        state.filter = .portra
        state.backgroundEdit.saturation = -0.5
        state.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        XCTAssertEqual(AIEditValues(from: state).applied(to: state), state, "unchanged values change nothing")
    }

    func testValuesAreClampedAndUnknownLooksIgnored() {
        var values = AIEditValues()
        values.exposure = 9
        values.highlights = 0.7 // only recovery (<= 0) exists
        values.subjectBrightness = -4
        values.look = "sepia-deluxe"
        let state = values.applied(to: PhotoAdjustmentState())
        XCTAssertEqual(state.exposure, 2)
        XCTAssertEqual(state.highlights, 0)
        XCTAssertEqual(state.subjectEdit.exposure, -1)
        XCTAssertEqual(state.filter, .none)
    }

    func testLooksMapToFilters() {
        var values = AIEditValues()
        values.look = "cinestill"
        XCTAssertEqual(values.applied(to: PhotoAdjustmentState()).filter, .cinestill)
        values.look = "keep"
        var current = PhotoAdjustmentState()
        current.filter = .noir
        XCTAssertEqual(values.applied(to: current).filter, .noir)
    }

    func testEditsOutsideTheAIsReachStayPut() {
        var current = PhotoAdjustmentState()
        current.colorMixer[.blue, .hue] = 0.5
        current.rotation = 1
        let next = AIEditValues().applied(to: current)
        XCTAssertEqual(next.colorMixer, current.colorMixer)
        XCTAssertEqual(next.rotation, 1)
    }

    @MainActor
    func testNoMediaDoesNothing() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "AI-\(UUID().uuidString)") ?? .standard)
        vm.applyAIEdit("make it warmer")
        XCTAssertFalse(vm.isAskingAI)
        XCTAssertFalse(vm.hasEdits)
    }
}
