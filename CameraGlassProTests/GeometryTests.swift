import CoreImage
import XCTest
@testable import CameraGlassPro

final class GeometryRenderTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    /// Left half red, right half blue, 400 x 300.
    private var scene: CIImage {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 300))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 200, y: 0, width: 200, height: 300))
        return red.composited(over: blue)
    }

    private func averageRed(_ image: CIImage, in rect: CGRect) -> Double {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[0])
    }

    func testRotateQuarterTurnSwapsSides() {
        var state = PhotoAdjustmentState()
        state.rotation = 1
        let output = processor.apply(state, to: scene)
        XCTAssertEqual(output.extent, CGRect(x: 0, y: 0, width: 300, height: 400))
    }

    func testFlipMirrorsLeftAndRight() {
        var state = PhotoAdjustmentState()
        state.flipped = true
        let output = processor.apply(state, to: scene)
        XCTAssertLessThan(averageRed(output, in: CGRect(x: 20, y: 20, width: 100, height: 100)), 30, "left is now blue")
        XCTAssertGreaterThan(averageRed(output, in: CGRect(x: 280, y: 20, width: 100, height: 100)), 220, "right is now red")
    }

    func testCropKeepsTheChosenPart() {
        var state = PhotoAdjustmentState()
        state.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 1) // the red half
        state.grain = 0.3 // grain is applied after the crop, at the cropped size
        let output = processor.apply(state, to: scene)
        XCTAssertEqual(output.extent, CGRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertGreaterThan(averageRed(output, in: CGRect(x: 20, y: 20, width: 160, height: 260)), 200)
    }

    func testStraightenLeavesNoEmptyCorners() {
        XCTAssertEqual(ImageProcessingService.straightenScale(width: 400, height: 300, degrees: 0), 1, accuracy: 1e-9)
        let scale = ImageProcessingService.straightenScale(width: 400, height: 300, degrees: 10)
        XCTAssertLessThan(scale, 1)
        var state = PhotoAdjustmentState()
        state.straighten = 10
        let output = processor.apply(state, to: scene)
        XCTAssertEqual(output.extent.width, (400 * scale).rounded(), accuracy: 2)
        // Corners are image content (red or blue), never transparent/black gaps.
        guard let corner = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: output, kCIInputExtentKey: CIVector(cgRect: CGRect(x: 0, y: 0, width: 6, height: 6)),
        ])?.outputImage else { return XCTFail("no average") }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(corner, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertGreaterThan(Int(pixel[0]) + Int(pixel[2]), 200, "corner is filled with picture")
        XCTAssertGreaterThan(pixel[3], 250)
    }

    func testVideosIgnoreGeometry() {
        var state = PhotoAdjustmentState()
        state.rotation = 1
        state.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        XCTAssertFalse(state.withoutGeometry.hasGeometry)
        XCTAssertEqual(processor.apply(state.withoutGeometry, to: scene).extent, scene.extent)
    }

    func testBadSavedCropFallsBackToFull() throws {
        let json = #"{"cropRect":[[0.5,0.5],[2,2]],"rotation":7}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.cropRect, PhotoAdjustmentState.fullCrop)
        XCTAssertEqual(state.rotation, 3)
    }
}

final class CropMathTests: XCTestCase {
    func testMoveStaysInside() {
        let rect = CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4)
        XCTAssertEqual(CropMath.moved(rect, dx: 0.5, dy: 0.5), CGRect(x: 0.6, y: 0.6, width: 0.4, height: 0.4))
        XCTAssertEqual(CropMath.moved(rect, dx: -1, dy: -1).origin, .zero)
    }

    func testCornerResizeKeepsMinimumAndBounds() {
        let full = PhotoAdjustmentState.fullCrop
        let shrunk = CropMath.resized(full, corner: .topLeft, dx: 0.3, dy: 0.2, normalizedRatio: nil)
        XCTAssertEqual(shrunk.minX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(shrunk.minY, 0.2, accuracy: 1e-9)
        XCTAssertEqual(shrunk.maxX, 1, accuracy: 1e-9)
        let tiny = CropMath.resized(full, corner: .bottomRight, dx: -2, dy: -2, normalizedRatio: nil)
        XCTAssertEqual(tiny.width, CropMath.minimumSide, accuracy: 1e-9)
        let outside = CropMath.resized(full, corner: .bottomRight, dx: 1, dy: 1, normalizedRatio: nil)
        XCTAssertEqual(outside, full)
    }

    func testAspectLockedResize() {
        let rect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let square = CropMath.resized(rect, corner: .bottomRight, dx: 0.2, dy: 0.0, normalizedRatio: 1)
        XCTAssertEqual(square.width, square.height, accuracy: 1e-9)
    }

    func testCenteredAspectCrops() {
        let square = CropAspect.centeredCrop(ratio: 1, imageSize: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(square.width, 0.75, accuracy: 1e-9)
        XCTAssertEqual(square.height, 1, accuracy: 1e-9)
        XCTAssertEqual(square.midX, 0.5, accuracy: 1e-9)
        let wide = CropAspect.centeredCrop(ratio: 16.0 / 9.0, imageSize: CGSize(width: 3000, height: 4000))
        XCTAssertEqual(wide.width, 1, accuracy: 1e-9)
        XCTAssertLessThan(wide.height, 1)
    }

    @MainActor
    func testGeometryIsOneUndoStep() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Crop-\(UUID().uuidString)") ?? .standard)
        vm.setGeometry(crop: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), rotation: 5, flipped: true, straighten: 99)
        XCTAssertEqual(vm.adjustments.rotation, 1)
        XCTAssertEqual(vm.adjustments.straighten, 45)
        XCTAssertTrue(vm.adjustments.hasGeometry)
        vm.undo()
        XCTAssertFalse(vm.adjustments.hasGeometry)
        XCTAssertFalse(vm.isAvailable(.crop), "crop needs a photo")
    }
}
