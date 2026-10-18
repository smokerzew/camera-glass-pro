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

    // MARK: Night stacking

    /// A soft checkerboard scene, 256 px.
    private var scene: CIImage {
        let e = CGRect(x: 0, y: 0, width: 256, height: 256)
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 0.2, green: 0.2, blue: 0.2), "inputColor1": CIColor(red: 0.6, green: 0.6, blue: 0.6),
            "inputWidth": 24,
        ])?.outputImage ?? CIImage(color: .gray)
        return checker.applyingGaussianBlur(sigma: 2).cropped(to: e)
    }

    /// The scene plus its own monochrome noise (about ±0.1), different for each `seed`.
    private func noisy(_ seed: Int) -> CIImage {
        let e = scene.extent
        let noise = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage.empty())
            .transformed(by: CGAffineTransform(translationX: CGFloat(seed * 97), y: CGFloat(seed * 61)))
            .cropped(to: e)
            .settingAlphaOne(in: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0.2, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.2, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: -0.1, y: -0.1, z: -0.1, w: 0),
            ])
        return noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: scene])
            .settingAlphaOne(in: e).cropped(to: e)
    }

    /// Root-mean-square difference from the clean scene, in 0...255 (green channel, middle 128 px).
    private func error(_ image: CIImage, against clean: CIImage) -> Double {
        let side = 128
        let bounds = CGRect(x: 64, y: 64, width: side, height: side)
        func render(_ i: CIImage) -> [UInt8] {
            var p = [UInt8](repeating: 0, count: side * side * 4)
            processor.context.render(i, toBitmap: &p, rowBytes: side * 4, bounds: bounds, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return p
        }
        let a = render(image), b = render(clean)
        var sum = 0.0
        for i in stride(from: 1, to: a.count, by: 4) { let d = Double(a[i]) - Double(b[i]); sum += d * d }
        return (sum / Double(side * side)).squareRoot()
    }

    func testRegistrationFindsTheShift() throws {
        let shifted = scene.clampedToExtent().transformed(by: CGAffineTransform(translationX: 6, y: 0)).cropped(to: scene.extent)
        let offset = try XCTUnwrap(NightStacker.offset(of: shifted, to: scene, context: processor.context))
        XCTAssertEqual(abs(offset.x), 6, accuracy: 1.5)
        XCTAssertEqual(offset.y, 0, accuracy: 1.5)
        let realigned = shifted.clampedToExtent().transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
            .cropped(to: scene.extent)
        XCTAssertLessThan(error(realigned, against: scene), 6, "applying the offset lines the frame back up")
    }

    func testStackingCutsNoise() {
        let frames = (0..<12).map { noisy($0) }
        let single = error(frames[5], against: scene)
        // Compare before the shadow lift: undo it by comparing against the scene lifted the same way.
        let stacked = NightStacker.stack(frames, reference: 5, context: processor.context)
        let lifted = scene.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.35, "inputHighlightAmount": 1])
            .cropped(to: scene.extent)
        XCTAssertEqual(stacked.extent, scene.extent)
        XCTAssertLessThan(error(stacked, against: lifted), single * 0.6, "averaging 12 frames removes most of the noise")
    }

    func testDeghostKeepsTheReferenceWhereThingsMoved() {
        let e = scene.extent
        let moved = CIImage(color: .white).cropped(to: CGRect(x: 100, y: 100, width: 60, height: 60)).composited(over: scene)
            .cropped(to: e)
        let result = NightStacker.deghosted(moved, reference: scene, extent: e)
        XCTAssertEqual(pixel(result, 130, 130).g, pixel(scene, 130, 130).g, accuracy: 6, "a moved object never ghosts in")
    }

    // MARK: Panorama

    /// A wide scene with blotchy detail everywhere, so neighbors can be lined up.
    private var wideScene: CIImage {
        let e = CGRect(x: 0, y: 0, width: 720, height: 240)
        return (CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage.empty())
            .cropped(to: e.insetBy(dx: -40, dy: -40))
            .settingAlphaOne(in: e.insetBy(dx: -40, dy: -40))
            .applyingGaussianBlur(sigma: 4)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 4])
            .cropped(to: e)
    }

    private func window(_ x: CGFloat) -> CIImage {
        wideScene.cropped(to: CGRect(x: x, y: 0, width: 320, height: 240))
            .transformed(by: CGAffineTransform(translationX: -x, y: 0))
    }

    func testFlatPanoramaRebuildsTheScene() throws {
        let pano = try PanoStitcher.stitch([window(0), window(200), window(400)], focalScale: nil, context: processor.context)
        XCTAssertEqual(pano.extent.origin, .zero)
        XCTAssertEqual(pano.extent.width, 720, accuracy: 8, "three 320 px photos, 200 px apart")
        XCTAssertEqual(pano.extent.height, 240, accuracy: 8)
        // The stitched middle matches the scene there.
        let middle = CGRect(x: 300, y: 60, width: 120, height: 120)
        let scene = wideScene
        var diff = 0.0
        for x in stride(from: middle.minX, to: middle.maxX, by: 10) {
            for y in stride(from: middle.minY, to: middle.maxY, by: 10) {
                diff += abs(pixel(pano, x, y).g - pixel(scene, x, y).g)
            }
        }
        XCTAssertLessThan(diff / 144, 12, "seams line up")
    }

    func testPanoramaOrderCanGoRightToLeft() throws {
        let pano = try PanoStitcher.stitch([window(400), window(200), window(0)], focalScale: nil, context: processor.context)
        XCTAssertEqual(pano.extent.width, 720, accuracy: 8)
    }

    func testPanoramaNeedsTwoOverlappingPhotos() {
        XCTAssertThrowsError(try PanoStitcher.stitch([window(0)], context: processor.context))
        let unrelated = solid(0.5, 0.5, 0.5, 320, 240)
        XCTAssertThrowsError(try PanoStitcher.stitch([window(0), unrelated], focalScale: nil, context: processor.context))
    }

    func testCylinderKeepsHeightAndNarrowsWidth() {
        XCTAssertNotNil(ImageProcessingService.cylinderWarpKernel)
        let warped = PanoStitcher.cylinder(window(0), focal: 0.75 * 320)
        XCTAssertEqual(warped.extent.origin, .zero)
        XCTAssertEqual(warped.extent.height, 240)
        XCTAssertLessThan(warped.extent.width, 320)
        XCTAssertGreaterThan(warped.extent.width, 280)
    }

    @MainActor
    func testPanoModeStitchesOnlyWithTwoOrMore() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Pano-\(UUID().uuidString)") ?? .standard)
        vm.mode = .pano
        XCTAssertFalse(vm.canStitchPanorama)
        vm.primaryAction()
        XCTAssertTrue(vm.showPhotosPicker, "with nothing picked the shutter still opens the picker")
    }

    func testNightIsAnEffect() {
        XCTAssertTrue(LiveEffect.allCases.contains(.night))
        XCTAssertEqual(LiveEffect.night.title, "NIGHT")
    }
}
