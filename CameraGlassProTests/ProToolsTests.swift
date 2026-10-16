import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import XCTest
@testable import CameraGlassPro

final class ScopeTests: XCTestCase {
    private func solidImage(_ color: UIColor, width: Int = 40, height: Int = 30) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage
    }

    func testPureRedLandsInTopRedAndBottomBlueBins() throws {
        let image = try XCTUnwrap(solidImage(UIColor(red: 1, green: 0, blue: 0, alpha: 1)))
        let data = try XCTUnwrap(ScopeData.compute(from: image))
        XCTAssertEqual(data.red.count, ScopeData.bins)
        XCTAssertEqual(data.red.last, 1, "all pixels are max red")
        XCTAssertEqual(data.blue.first, 1, "no blue at all")
        XCTAssertEqual(data.red.dropLast().reduce(0, +), 0)
    }

    func testWaveformHasOneTracePerColumn() throws {
        let image = try XCTUnwrap(solidImage(.white))
        let data = try XCTUnwrap(ScopeData.compute(from: image, maxWidth: 40, columns: 8))
        XCTAssertEqual(data.redWave.count, 8 * ScopeData.bins)
        for column in 0..<8 {
            XCTAssertEqual(data.redWave[column * ScopeData.bins + ScopeData.bins - 1], 1, accuracy: 0.001)
        }
    }

    func testModeCycle() {
        XCTAssertEqual(ScopeMode.off.next, .luminance)
        XCTAssertEqual(ScopeMode.parade.next, .off)
        XCTAssertNil(ScopeMode.off.shortLabel)
    }
}

final class LevelMathTests: XCTestCase {
    func testRollAngle() {
        XCTAssertEqual(MotionLevel.roll(gx: 0, gy: -1), 0, accuracy: 1e-9)
        XCTAssertEqual(MotionLevel.roll(gx: 1, gy: 0), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(MotionLevel.roll(gx: -0.5, gy: -0.8660254), -.pi / 6, accuracy: 1e-6)
    }

    func testLevelTolerance() {
        XCTAssertTrue(MotionLevel.isLevel(0))
        XCTAssertTrue(MotionLevel.isLevel(0.5 * .pi / 180))
        XCTAssertFalse(MotionLevel.isLevel(3 * .pi / 180))
    }
}

final class PeakingTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func averageAlpha(_ image: CIImage) -> Double {
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4,
                                 bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[3])
    }

    func testFlatImageHasNoPeaking() {
        let flat = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let overlay = processor.peakingOverlay(for: flat)
        XCTAssertEqual(overlay.extent, flat.extent)
        XCTAssertLessThan(averageAlpha(overlay), 2)
    }

    func testHardEdgesAreHighlighted() {
        let checker = CIFilter.checkerboardGenerator()
        checker.width = 8
        checker.color0 = .white
        checker.color1 = .black
        let image = (checker.outputImage ?? CIImage.empty()).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertGreaterThan(averageAlpha(processor.peakingOverlay(for: image)), 5)
    }

    func testVideoBoxCarriesPeakingFlag() {
        let box = AdjustmentBox()
        XCTAssertFalse(box.peaking)
        box.peaking = true
        XCTAssertTrue(box.peaking)
    }
}

@MainActor
final class ProToolsViewModelTests: XCTestCase {
    func testScopesAndPeakingControls() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "ProTools-\(UUID().uuidString)") ?? .standard)
        vm.perform(.scopes)
        XCTAssertEqual(vm.scopeMode, .luminance)
        XCTAssertTrue(vm.isActive(.scopes))
        vm.perform(.peaking)
        XCTAssertTrue(vm.focusPeaking)
        XCTAssertTrue(vm.hasActiveControls)
        vm.setScopeMode(.off)
        XCTAssertNil(vm.scopeData)
    }

    func testCenterControlStopsRecordingInsteadOfImporting() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "ProTools-\(UUID().uuidString)") ?? .standard)
        XCTAssertFalse(vm.isRecordingUI)
        vm.primaryAction()
        XCTAssertTrue(vm.showPhotosPicker, "with no recording, the center control imports")
    }
}
