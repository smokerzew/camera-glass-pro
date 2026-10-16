import CoreImage
import UIKit
import XCTest
@testable import CameraGlassPro

final class FocusMathTests: XCTestCase {
    func testTapMapsToMediaPoint() throws {
        let media = CGSize(width: 3000, height: 4000)
        let frame = CGSize(width: 300, height: 400)
        let center = try XCTUnwrap(FramingGeometry.mediaPoint(tap: CGPoint(x: 150, y: 200), frame: frame, media: media, zoom: 1, pan: .zero))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.001)
        // At 2x the frame shows the middle half, so its left edge is a quarter into the media.
        let edge = try XCTUnwrap(FramingGeometry.mediaPoint(tap: CGPoint(x: 0, y: 200), frame: frame, media: media, zoom: 2, pan: .zero))
        XCTAssertEqual(edge.x, 0.25, accuracy: 0.001)
        // Zoomed out, a tap in the empty border misses the media.
        XCTAssertNil(FramingGeometry.mediaPoint(tap: CGPoint(x: 2, y: 2), frame: frame, media: media, zoom: 0.5, pan: .zero))
    }

    func testMeteringTargetsMidGray() {
        XCTAssertEqual(CameraWorkspaceViewModel.meteredExposure(regionLuma: 0.46), 0, accuracy: 0.1)
        XCTAssertLessThan(CameraWorkspaceViewModel.meteredExposure(regionLuma: 0.9), -0.5, "bright area darkens")
        XCTAssertGreaterThan(CameraWorkspaceViewModel.meteredExposure(regionLuma: 0.15), 0.5, "dark area brightens")
        XCTAssertEqual(CameraWorkspaceViewModel.meteredExposure(regionLuma: 0), 2, "clamped")
    }

    func testAverageLumaReadsTheTappedSide() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.black.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let processor = ImageProcessingService.shared
        let left = try XCTUnwrap(processor.averageLuma(of: cgImage, around: CGPoint(x: 0.2, y: 0.5), radius: 0.1))
        let right = try XCTUnwrap(processor.averageLuma(of: cgImage, around: CGPoint(x: 0.8, y: 0.5), radius: 0.1))
        XCTAssertGreaterThan(left, 0.9)
        XCTAssertLessThan(right, 0.1)
    }
}

@MainActor
final class FocusStateTests: XCTestCase {
    private func makeVM() -> CameraWorkspaceViewModel {
        CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Focus-\(UUID().uuidString)") ?? .standard)
    }

    func testTapAndLock() {
        let vm = makeVM()
        vm.focus(atView: CGPoint(x: 10, y: 20), mediaPoint: nil, lock: false)
        XCTAssertEqual(vm.focusPoint, CGPoint(x: 10, y: 20))
        XCTAssertFalse(vm.isAELocked)
        vm.focus(atView: CGPoint(x: 30, y: 40), mediaPoint: nil, lock: true)
        XCTAssertTrue(vm.isAELocked)
        vm.focus(atView: CGPoint(x: 50, y: 60), mediaPoint: nil, lock: false)
        XCTAssertFalse(vm.isAELocked, "a new tap releases the lock")
    }

    func testSunDragIsOneUndoStep() {
        let vm = makeVM()
        vm.focus(atView: .zero, mediaPoint: nil, lock: false)
        vm.beginExposureDrag()
        vm.updateExposureDrag(by: -60)
        vm.updateExposureDrag(by: -120)
        vm.endExposureDrag()
        XCTAssertEqual(vm.adjustments.exposure, 1, accuracy: 0.0001, "dragging up 120 pt adds 1 EV")
        vm.undo()
        XCTAssertEqual(vm.adjustments.exposure, 0)
    }
}

final class PhotographicStyleTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func averageRGB(_ image: CIImage) -> (Double, Double, Double) {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])?.outputImage else { return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    private let input = CIImage(color: CIColor(red: 0.5, green: 0.45, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))

    func testStandardCenteredIsIdentity() {
        XCTAssertTrue(PhotoAdjustmentState().isIdentity)
        var state = PhotoAdjustmentState()
        state.style = .amber
        XCTAssertFalse(state.isIdentity)
    }

    func testWarmAndCoolUndertones() {
        var amber = PhotoAdjustmentState(); amber.style = .amber
        var cool = PhotoAdjustmentState(); cool.style = .cool
        let warm = averageRGB(processor.apply(amber, to: input))
        let cold = averageRGB(processor.apply(cool, to: input))
        XCTAssertGreaterThan(warm.0 - warm.2, cold.0 - cold.2, "amber is warmer than cool")
    }

    func testPaletteZeroRemovesUndertone() {
        var state = PhotoAdjustmentState(); state.style = .amber; state.stylePalette = 0
        let base = averageRGB(input)
        let styled = averageRGB(processor.apply(state, to: input))
        XCTAssertEqual(styled.0, base.0, accuracy: 2)
        XCTAssertEqual(styled.2, base.2, accuracy: 2)
    }

    func testBlackAndWhiteStyles() {
        var state = PhotoAdjustmentState(); state.style = .starkBW
        let rgb = averageRGB(processor.apply(state, to: input))
        XCTAssertEqual(rgb.0, rgb.2, accuracy: 3)
    }

    func testColorAxisChangesSaturation() {
        var vivid = PhotoAdjustmentState(); vivid.styleColor = 1
        var muted = PhotoAdjustmentState(); muted.styleColor = -1
        let a = averageRGB(processor.apply(vivid, to: input))
        let b = averageRGB(processor.apply(muted, to: input))
        XCTAssertGreaterThan(a.0 - a.2, b.0 - b.2)
    }

    func testOldRecipesDecodeWithStandardStyle() throws {
        let json = #"{"exposure":0,"brightness":0,"contrast":1,"saturation":1,"warmth":0,"highlights":0,"shadows":0}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.style, .standard)
        XCTAssertEqual(state.stylePalette, 1)
    }
}
