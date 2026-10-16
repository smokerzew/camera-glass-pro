import CoreGraphics
import XCTest
@testable import CameraGlassPro

final class PanTests: XCTestCase {
    private let image = CGSize(width: 4000, height: 3000)

    func testMaxOffsetIsZeroWhenMediaJustFills() {
        let frame = CGSize(width: 400, height: 300) // same aspect, fill at 1x
        XCTAssertEqual(FramingGeometry.maxOffset(image: image, frame: frame, zoom: 1, fill: true), .zero)
        let zoomed = FramingGeometry.maxOffset(image: image, frame: frame, zoom: 2, fill: true)
        XCTAssertEqual(zoomed.width, 200, accuracy: 0.001)
        XCTAssertEqual(zoomed.height, 150, accuracy: 0.001)
    }

    func testPanMovesVisibleRegionOppositeToDrag() {
        let centered = FramingGeometry.visibleRect(image: image, ratio: 4.0 / 3.0, zoom: 2, fill: true)
        XCTAssertEqual(centered.minX, 1000, accuracy: 0.5)
        // Media dragged fully right shows the left edge of the image.
        let right = FramingGeometry.visibleRect(image: image, ratio: 4.0 / 3.0, zoom: 2, fill: true, pan: CGPoint(x: 1, y: 0))
        XCTAssertEqual(right.minX, 0, accuracy: 0.5)
        let left = FramingGeometry.visibleRect(image: image, ratio: 4.0 / 3.0, zoom: 2, fill: true, pan: CGPoint(x: -1, y: 0))
        XCTAssertEqual(left.maxX, 4000, accuracy: 0.5)
    }

    func testPanIsClamped() {
        XCTAssertEqual(FramingGeometry.clampPan(CGPoint(x: 3, y: -7)), CGPoint(x: 1, y: -1))
        let rect = FramingGeometry.visibleRect(image: image, ratio: 4.0 / 3.0, zoom: 2, fill: true, pan: CGPoint(x: 9, y: 9))
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
    }

    @MainActor
    func testResetFramingClearsPan() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Pan-\(UUID().uuidString)") ?? .standard)
        vm.setPan(CGPoint(x: 0.5, y: -0.5))
        XCTAssertEqual(vm.pan, CGPoint(x: 0.5, y: -0.5))
        vm.resetFraming()
        XCTAssertEqual(vm.pan, .zero)
    }
}

final class VideoOrientationTests: XCTestCase {
    func testExifOrientationFromTransform() {
        XCTAssertEqual(VideoService.exifOrientation(for: .identity), 1)
        XCTAssertEqual(VideoService.exifOrientation(for: CGAffineTransform(rotationAngle: .pi / 2)), 6)
        XCTAssertEqual(VideoService.exifOrientation(for: CGAffineTransform(rotationAngle: -.pi / 2)), 8)
        XCTAssertEqual(VideoService.exifOrientation(for: CGAffineTransform(rotationAngle: .pi)), 3)
    }
}

final class IconRotationTests: XCTestCase {
    func testHysteresis() {
        XCTAssertEqual(MotionLevel.nextIconRotation(current: 0, rollDegrees: 10), 0)
        XCTAssertEqual(MotionLevel.nextIconRotation(current: 0, rollDegrees: -80), 90)
        XCTAssertEqual(MotionLevel.nextIconRotation(current: 0, rollDegrees: 80), -90)
        // Between 35° and 55° the current state is kept (no flicker).
        XCTAssertEqual(MotionLevel.nextIconRotation(current: 90, rollDegrees: -45), 90)
        XCTAssertEqual(MotionLevel.nextIconRotation(current: 0, rollDegrees: -45), 0)
        XCTAssertEqual(MotionLevel.nextIconRotation(current: 90, rollDegrees: -20), 0)
        // Upside down keeps the current rotation.
        XCTAssertEqual(MotionLevel.nextIconRotation(current: -90, rollDegrees: 175), -90)
    }
}

final class ZoomDialTests: XCTestCase {
    func testPositionRoundTrips() {
        XCTAssertEqual(ZoomDial.position(for: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(ZoomDial.position(for: 5), 1, accuracy: 1e-9)
        for zoom: CGFloat in [0.5, 1, 2, 3.3, 5] {
            XCTAssertEqual(ZoomDial.zoom(at: ZoomDial.position(for: zoom)), zoom, accuracy: 0.0001)
        }
    }

    func testDragLeftZoomsIn() {
        let zoomedIn = ZoomDial.zoom(from: 1, dragDistance: -100, radius: 300)
        XCTAssertGreaterThan(zoomedIn, 1)
        let zoomedOut = ZoomDial.zoom(from: 1, dragDistance: 100, radius: 300)
        XCTAssertLessThan(zoomedOut, 1)
        XCTAssertEqual(ZoomDial.zoom(from: 5, dragDistance: -10_000, radius: 300), ZoomLimits.maximum)
    }
}
