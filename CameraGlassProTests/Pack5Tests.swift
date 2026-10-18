import CoreImage
import XCTest
@testable import CameraGlassPro

/// Pack 5: 9:16 story fill, Sky Replace, Night stacking, Pano, Cinematic, smooth slow-mo, Remove brush.
final class Pack5Tests: XCTestCase {
    private let processor = ImageProcessingService.shared

    /// sRGB 0...255 of one pixel (bottom-left origin, like Core Image).
    private func pixel(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> (r: Double, g: Double, b: Double) {
        var p = [UInt8](repeating: 0, count: 4)
        processor.context.render(image, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(p[0]), Double(p[1]), Double(p[2]))
    }

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    // MARK: 9:16 story fill

    func testStoryFillMakesNineBySixteenWithPhotoCentered() {
        let photo = solid(0.9, 0.2, 0.1, 400, 300)
        let story = PhotoExportService.storyFill(photo)
        XCTAssertEqual(story.extent.origin, .zero)
        XCTAssertEqual(story.extent.width, 400)
        XCTAssertEqual(story.extent.height, 711)
        let center = pixel(story, 200, 355)
        XCTAssertGreaterThan(center.r, 200, "the photo itself sits in the middle, untouched")
        let corner = pixel(story, 5, 5)
        XCTAssertLessThan(corner.r, center.r - 20, "the fill is a darker blurred copy")
        XCTAssertGreaterThan(corner.r, corner.b, "the fill keeps the photo's colors (no plain bars)")
    }

    func testStoryFillTallPhotoWidensAndExactRatioUnchanged() {
        let tall = PhotoExportService.storyFill(solid(0.5, 0.5, 0.5, 100, 400))
        XCTAssertEqual(tall.extent.size, CGSize(width: 225, height: 400))
        let exact = solid(0.5, 0.5, 0.5, 90, 160)
        XCTAssertTrue(PhotoExportService.storyFill(exact) === exact)
    }

    // MARK: Sky Replace

    /// Blue sky on top, busy green ground below (same scene as DetailSkyTests).
    private var landscape: CIImage {
        let extent = CGRect(x: 0, y: 0, width: 300, height: 300)
        let sky = solid(0.25, 0.45, 0.85, 300, 150).transformed(by: CGAffineTransform(translationX: 0, y: 150))
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 0.15, green: 0.4, blue: 0.1), "inputColor1": CIColor(red: 0.35, green: 0.55, blue: 0.2),
            "inputWidth": 3,
        ])?.outputImage ?? CIImage(color: .green)
        return sky.composited(over: checker.cropped(to: CGRect(x: 0, y: 0, width: 300, height: 150))).cropped(to: extent)
    }

    func testSunsetSkyReplacesTheSkyAndWarmsTheLand() {
        var state = PhotoAdjustmentState()
        state.skyReplace = .sunset
        let output = processor.apply(state, to: landscape)
        XCTAssertEqual(output.extent, landscape.extent)
        let before = pixel(landscape, 150, 200), after = pixel(output, 150, 200) // low in the sky, near the horizon
        XCTAssertGreaterThan(after.r, before.r + 40, "the sky turns sunset orange")
        XCTAssertLessThan(after.b, before.b - 20)
        let groundBefore = pixel(landscape.clampedToExtent().applyingGaussianBlur(sigma: 4), 150, 60)
        let groundAfter = pixel(output.clampedToExtent().applyingGaussianBlur(sigma: 4), 150, 60)
        XCTAssertGreaterThan(groundAfter.r - groundAfter.b, groundBefore.r - groundBefore.b, "the land gets warmer light")
        XCTAssertGreaterThan(groundAfter.g, groundAfter.r, "the ground is still green, not replaced")
    }

    func testSkyReplaceAmountZeroAndPhotoWithoutPhotoAreNoOps() {
        var off = PhotoAdjustmentState()
        off.skyReplace = .blue
        off.skyReplaceAmount = 0
        let a = pixel(processor.apply(off, to: landscape), 150, 250), b = pixel(landscape, 150, 250)
        XCTAssertEqual(a.b, b.b, accuracy: 2)
        var photo = PhotoAdjustmentState()
        photo.skyReplace = .photo // no second photo chosen
        XCTAssertEqual(pixel(processor.apply(photo, to: landscape), 150, 250).b, b.b, accuracy: 2)
    }

    func testSkyReplaceResetsWithSubjectStyleAndDecodesTolerantly() throws {
        var state = PhotoAdjustmentState()
        state.skyReplace = .golden
        state.skyReplaceAmount = 0.6
        XCTAssertTrue(state.canReset(.subjectStyle))
        XCTAssertEqual(state.resetting(.subjectStyle).skyReplace, .none)
        let old = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data("{}".utf8))
        XCTAssertEqual(old.skyReplace, .none)
        XCTAssertEqual(old.skyReplaceAmount, 1)
        let bad = try JSONDecoder().decode(PhotoAdjustmentState.self,
                                           from: Data(#"{"skyReplace":"aurora","skyReplaceAmount":7}"#.utf8))
        XCTAssertEqual(bad.skyReplace, .none)
        XCTAssertEqual(bad.skyReplaceAmount, 1)
        let round = try JSONDecoder().decode(PhotoAdjustmentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round, state)
    }
}
