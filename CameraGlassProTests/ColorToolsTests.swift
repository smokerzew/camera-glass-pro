import CoreImage
import XCTest
@testable import CameraGlassPro

final class ColorMixerTests: XCTestCase {
    func testWeightsCrossFadeAndSumToOne() {
        for h in stride(from: 0.0, to: 360, by: 7) {
            let total: Double = ColorMixer.weights(hue: h).reduce(0, +)
            XCTAssertEqual(total, 1, accuracy: 1e-9, "hue \(h)")
        }
        XCTAssertEqual(ColorMixer.weights(hue: 225)[ColorBand.blue.rawValue], 1, accuracy: 1e-9)
    }

    func testNeutralMixerChangesNothing() {
        let mixer = ColorMixer()
        let (r, g, b) = mixer.map(0.8, 0.3, 0.1)
        XCTAssertEqual(r, 0.8, accuracy: 1e-6)
        XCTAssertEqual(g, 0.3, accuracy: 1e-6)
        XCTAssertEqual(b, 0.1, accuracy: 1e-6)
    }

    func testRedDesaturateMakesRedGrayButKeepsBlue() {
        var mixer = ColorMixer()
        mixer[.red, .saturation] = -1
        let red = mixer.map(0.9, 0.1, 0.1)
        XCTAssertEqual(red.0, red.1, accuracy: 0.01)
        XCTAssertEqual(red.1, red.2, accuracy: 0.01)
        let blue = mixer.map(0.1, 0.2, 0.9)
        XCTAssertEqual(blue.2, 0.9, accuracy: 0.01, "other colors untouched")
    }

    func testHueAndLuminanceOnlyMoveTheirColor() {
        var mixer = ColorMixer()
        mixer[.blue, .hue] = 1
        mixer[.orange, .luminance] = 1
        let green = mixer.map(0.2, 0.8, 0.2)
        XCTAssertEqual(green.1, 0.8, accuracy: 0.01)
        let blue = mixer.map(0.1, 0.35, 0.9)
        XCTAssertNotEqual(blue.0, 0.1, accuracy: 0.03, "blue hue shifted")
        let orange = mixer.map(0.8, 0.45, 0.1)
        XCTAssertGreaterThan(orange.0 + orange.1 + orange.2, 1.35, "orange brighter")
        let gray = mixer.map(0.5, 0.5, 0.5)
        XCTAssertEqual(gray.0, 0.5, accuracy: 1e-9)
    }

    func testBadSavedMixerLoadsNeutral() throws {
        let json = #"{"colorMixer":{"hue":[1,2],"saturation":[0,0,0,0,0,0,0,9],"luminance":"x"}}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.colorMixer[.red, .hue], 0)
        XCTAssertEqual(state.colorMixer[.magenta, .saturation], 1, "clamped")
        XCTAssertEqual(state.filterStrength, 1)
        XCTAssertEqual(state.vignette, 0)
    }
}

final class ColorToolsRenderTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func averageRGB(_ image: CIImage, in rect: CGRect) -> [Double] {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return [-1, -1, -1] }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return [Double(pixel[0]), Double(pixel[1]), Double(pixel[2])]
    }

    private func patch(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    func testMixerRendersThroughCoreImage() {
        var state = PhotoAdjustmentState()
        state.colorMixer[.red, .saturation] = -1
        let rgb = averageRGB(processor.apply(state, to: patch(0.9, 0.1, 0.1)), in: CGRect(x: 50, y: 50, width: 100, height: 100))
        XCTAssertEqual(rgb[0], rgb[1], accuracy: 6, "red turned gray")
    }

    func testVignetteDarkensOrLightensCorners() {
        var state = PhotoAdjustmentState()
        state.vignette = 1
        let dark = processor.apply(state, to: patch(0.5, 0.5, 0.5))
        let center = averageRGB(dark, in: CGRect(x: 95, y: 95, width: 10, height: 10))[1]
        let corner = averageRGB(dark, in: CGRect(x: 0, y: 0, width: 10, height: 10))[1]
        XCTAssertLessThan(corner, center - 20)
        XCTAssertEqual(dark.extent, CGRect(x: 0, y: 0, width: 200, height: 200))
        state.vignette = -1
        let light = processor.apply(state, to: patch(0.5, 0.5, 0.5))
        XCTAssertGreaterThan(averageRGB(light, in: CGRect(x: 0, y: 0, width: 10, height: 10))[1], center + 20)
    }

    func testFilterStrengthBlendsWithOriginal() {
        let input = patch(0.3, 0.5, 0.7)
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        var state = PhotoAdjustmentState()
        state.filter = .mono
        let full = averageRGB(processor.apply(state, to: input), in: rect)
        state.filterStrength = 0
        let none = averageRGB(processor.apply(state, to: input), in: rect)
        let original = averageRGB(input, in: rect)
        state.filterStrength = 0.5
        let half = averageRGB(processor.apply(state, to: input), in: rect)
        XCTAssertEqual(none[2], original[2], accuracy: 2, "0% = no filter")
        XCTAssertLessThan(abs(full[0] - full[2]), 10, "100% mono is gray")
        XCTAssertTrue(half[2] < none[2] - 5 && half[2] > full[2] + 5, "50% sits between")
    }
}
