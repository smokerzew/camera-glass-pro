import CoreImage
import XCTest
@testable import CameraGlassPro

final class HalationTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func rgb(_ image: CIImage, at rect: CGRect) -> [Double] {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return [-1, -1, -1] }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return [Double(pixel[0]), Double(pixel[1]), Double(pixel[2])]
    }

    /// Black 400 x 400 frame with a white 40 x 40 light in the middle.
    private var nightLight: CIImage {
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 400))
        let light = CIImage(color: .white).cropped(to: CGRect(x: 180, y: 180, width: 40, height: 40))
        return light.composited(over: black)
    }

    func testHalationKernelCompiles() {
        XCTAssertNotNil(ImageProcessingService.halationKernels)
    }

    func testLightsGlowRedOrange() {
        var state = PhotoAdjustmentState()
        state.halation = 1
        let output = processor.apply(state, to: nightLight)
        XCTAssertEqual(output.extent, nightLight.extent)
        let ring = rgb(output, at: CGRect(x: 221, y: 195, width: 4, height: 10)) // just beside the light
        XCTAssertGreaterThan(ring[0], 25, "glow spills around the light")
        XCTAssertGreaterThan(ring[0], ring[2] + 15, "the glow is red, not white")
        let corner = rgb(output, at: CGRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertLessThan(corner[0], 8, "far shadows stay black")
    }

    func testNoHighlightsNoGlow() {
        var state = PhotoAdjustmentState()
        state.halation = 1
        let gray = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let before = rgb(gray, at: CGRect(x: 50, y: 50, width: 100, height: 100))
        let after = rgb(processor.apply(state, to: gray), at: CGRect(x: 50, y: 50, width: 100, height: 100))
        XCTAssertEqual(after[0], before[0], accuracy: 2)
    }
}

final class RegionEditTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func green(_ image: CIImage, at rect: CGRect) -> Double {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[1])
    }

    func testSubjectAndBackgroundAreEditedSeparately() {
        let photo = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 200))
        // Subject = left half.
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
            .composited(over: CIImage(color: .black).cropped(to: photo.extent))
        var state = PhotoAdjustmentState()
        state.subjectEdit.exposure = 0.6
        state.backgroundEdit.exposure = -0.6
        XCTAssertTrue(state.needsSubject)
        let output = processor.apply(state, to: photo, subjectMask: mask)
        let original = green(photo, at: CGRect(x: 60, y: 60, width: 80, height: 80))
        XCTAssertGreaterThan(green(output, at: CGRect(x: 60, y: 60, width: 80, height: 80)), original + 20, "subject brighter")
        XCTAssertLessThan(green(output, at: CGRect(x: 260, y: 60, width: 80, height: 80)), original - 20, "background darker")
    }

    func testNoSubjectRendersWithoutSubjectEdits() {
        var state = PhotoAdjustmentState()
        state.subjectEdit.saturation = 1
        state.portrait = true
        XCTAssertTrue(state.withoutSubjectEdits.isIdentity)
    }

    func testBadSavedRegionEditIsClamped() throws {
        let json = #"{"subjectEdit":{"exposure":7,"warmth":"hot"},"halation":3}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.subjectEdit.exposure, 1)
        XCTAssertEqual(state.subjectEdit.warmth, 0)
        XCTAssertEqual(state.halation, 1)
    }

    @MainActor
    func testRegionEditIsUndoable() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Region-\(UUID().uuidString)") ?? .standard)
        vm.setRegionEdit(.background, .saturation, to: -2)
        XCTAssertEqual(vm.adjustments.backgroundEdit.saturation, -1)
        vm.undo()
        XCTAssertTrue(vm.adjustments.backgroundEdit.isNeutral)
    }
}
