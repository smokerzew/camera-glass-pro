import CoreImage
import XCTest
@testable import CameraGlassPro

final class LocalAdjustmentTests: XCTestCase {
    private let processor = ImageProcessingService.shared
    private let photo = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))

    private func green(_ image: CIImage, at rect: CGRect) -> Double {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[1])
    }

    func testGraduatedFromTopDarkensTheSkyOnly() {
        var sky = LocalAdjustment(shape: .graduated)
        sky.edge = .top
        sky.position = 0.5
        sky.edit.exposure = -1
        var state = PhotoAdjustmentState()
        state.localAdjustments = [sky]
        let output = processor.apply(state, to: photo)
        XCTAssertEqual(output.extent, photo.extent)
        let original = green(photo, at: CGRect(x: 150, y: 10, width: 100, height: 40))
        // Core Image is bottom-left origin: the top of the picture is high y.
        XCTAssertLessThan(green(output, at: CGRect(x: 150, y: 270, width: 100, height: 25)), original - 40, "top darker")
        XCTAssertEqual(green(output, at: CGRect(x: 150, y: 10, width: 100, height: 40)), original, accuracy: 2, "bottom untouched")
    }

    func testRadialBrightensInsideOrOutside() {
        var spot = LocalAdjustment(shape: .radial)
        spot.centerX = 0.5
        spot.centerY = 0.5
        spot.size = 0.3
        spot.softness = 0.2
        spot.edit.exposure = 1
        var state = PhotoAdjustmentState()
        state.localAdjustments = [spot]
        let center = CGRect(x: 190, y: 140, width: 20, height: 20)
        let corner = CGRect(x: 0, y: 0, width: 20, height: 20)
        let original = green(photo, at: center)
        let inside = processor.apply(state, to: photo)
        XCTAssertGreaterThan(green(inside, at: center), original + 40)
        XCTAssertEqual(green(inside, at: corner), original, accuracy: 2)

        state.localAdjustments[0].inverted = true
        let outside = processor.apply(state, to: photo)
        XCTAssertEqual(green(outside, at: center), original, accuracy: 2)
        XCTAssertGreaterThan(green(outside, at: corner), original + 40)
    }

    func testSavedFiltersAreLimitedAndClamped() throws {
        var many = PhotoAdjustmentState()
        many.localAdjustments = (0..<6).map { _ in LocalAdjustment(shape: .radial) }
        many.localAdjustments[0].size = 9
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: JSONEncoder().encode(many))
        XCTAssertEqual(decoded.localAdjustments.count, LocalAdjustment.limit)
        XCTAssertEqual(decoded.localAdjustments[0].size, 1)
    }

    @MainActor
    func testAddUpdateRemoveAreUndoable() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Local-\(UUID().uuidString)") ?? .standard)
        vm.addLocal(.graduated)
        XCTAssertEqual(vm.adjustments.localAdjustments.count, 1)
        let id = vm.adjustments.localAdjustments[0].id
        vm.updateLocal(id) { $0.position = 4 }
        XCTAssertEqual(vm.adjustments.localAdjustments[0].position, 1, "clamped")
        vm.removeLocal(id)
        XCTAssertTrue(vm.adjustments.localAdjustments.isEmpty)
        vm.undo()
        XCTAssertEqual(vm.adjustments.localAdjustments.count, 1)
    }

    @MainActor
    func testNoAIEditMeansNothingHighlighted() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "AIReview-\(UUID().uuidString)") ?? .standard)
        XCTAssertTrue(vm.aiChangedParameters.isEmpty)
        XCTAssertNil(vm.aiChangeSummary)
        vm.revertAIEdit() // nothing to revert: no change
        XCTAssertFalse(vm.hasEdits)
    }
}
