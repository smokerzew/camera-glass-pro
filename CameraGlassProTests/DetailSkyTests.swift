import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import CameraGlassPro

final class DetailSkyTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func stats(_ image: CIImage, in rect: CGRect) -> (mean: Double, spread: Double, chroma: Double) {
        let w = Int(rect.width), h = Int(rect.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let moved = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        processor.context.render(moved, toBitmap: &pixels, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var lumas: [Double] = []
        var chroma = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            chroma += max(r, g, b) - min(r, g, b)
        }
        let mean: Double = lumas.reduce(0, +) / Double(lumas.count)
        let squares: [Double] = lumas.map { (v: Double) -> Double in (v - mean) * (v - mean) }
        return (mean, (squares.reduce(0, +) / Double(lumas.count)).squareRoot(), chroma / Double(lumas.count))
    }

    /// Mid-gray with colored speckle, like a high-ISO night shot.
    private var noisy: CIImage {
        // Random RGB scaled to ±0.06 around 0.3 in one matrix (opaque, no blending of alpha).
        (CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.12, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.12, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.12, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.24, y: 0.24, z: 0.24, w: 1),
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
    }

    func testNoiseReductionRemovesSpeckleAndColorNoise() {
        XCTAssertNotNil(ImageProcessingService.kernel("denoise"))
        var state = PhotoAdjustmentState()
        state.noiseReduction = 1
        let rect = CGRect(x: 64, y: 64, width: 128, height: 128)
        let before = stats(noisy, in: rect)
        let after = stats(processor.apply(state, to: noisy), in: rect)
        XCTAssertLessThan(after.chroma, before.chroma * 0.6, "color speckle mostly gone")
        XCTAssertLessThan(after.spread, before.spread, "smoother")
        XCTAssertEqual(after.mean, before.mean, accuracy: 4, "same brightness")
    }

    func testSharpenAddsDetail() {
        var state = PhotoAdjustmentState()
        state.sharpen = 1
        let soft = noisy.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: noisy.extent)
        let rect = CGRect(x: 64, y: 64, width: 128, height: 128)
        XCTAssertGreaterThan(stats(processor.apply(state, to: soft), in: rect).spread, stats(soft, in: rect).spread)
        XCTAssertEqual(AdjustmentParameter.noise.title, "Noise Reduction")
    }

    /// Blue sky on top, busy green ground below.
    private var landscape: CIImage {
        let extent = CGRect(x: 0, y: 0, width: 300, height: 300)
        let sky = CIImage(color: CIColor(red: 0.25, green: 0.45, blue: 0.85)).cropped(to: CGRect(x: 0, y: 150, width: 300, height: 150))
        let checker = CIFilter.checkerboardGenerator()
        checker.color0 = CIColor(red: 0.15, green: 0.4, blue: 0.1)
        checker.color1 = CIColor(red: 0.35, green: 0.55, blue: 0.2)
        checker.width = 3
        let ground = (checker.outputImage ?? CIImage(color: .green)).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 150))
        return sky.composited(over: ground).cropped(to: extent)
    }

    func testSkyEditChangesOnlyTheSky() {
        XCTAssertNotNil(ImageProcessingService.kernel("skyLikelihood"))
        var state = PhotoAdjustmentState()
        state.skyEdit.exposure = -1
        let output = processor.apply(state, to: landscape)
        XCTAssertEqual(output.extent, landscape.extent)
        let skyRect = CGRect(x: 100, y: 230, width: 100, height: 50) // CI origin is bottom-left: high y = top
        let groundRect = CGRect(x: 100, y: 20, width: 100, height: 60)
        XCTAssertLessThan(stats(output, in: skyRect).mean, stats(landscape, in: skyRect).mean - 25, "sky darker")
        XCTAssertEqual(stats(output, in: groundRect).mean, stats(landscape, in: groundRect).mean, accuracy: 4, "ground untouched")
    }

    @MainActor
    func testSkyEditIsARegion() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Sky-\(UUID().uuidString)") ?? .standard)
        vm.setRegionEdit(.sky, .saturation, to: 0.5)
        XCTAssertEqual(vm.adjustments.skyEdit.saturation, 0.5)
        XCTAssertFalse(vm.adjustments.needsSubject, "sky doesn't need the subject mask")
        vm.resetRegionEdits()
        XCTAssertTrue(vm.adjustments.skyEdit.isNeutral)
    }
}
