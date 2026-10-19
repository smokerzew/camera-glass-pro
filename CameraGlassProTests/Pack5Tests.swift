import AVFoundation
import CoreImage
import Photos
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

    /// A soft, non-repeating blotchy scene, 256 px (a repeating pattern can't be lined up unambiguously).
    private var scene: CIImage {
        let e = CGRect(x: 0, y: 0, width: 256, height: 256)
        let big = e.insetBy(dx: -40, dy: -40)
        return (CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage.empty())
            // Stretched 3×: the generator repeats every 256 px, and unstretched it would be a shifted copy of the grain.
            .transformed(by: CGAffineTransform(scaleX: 3, y: 3))
            .cropped(to: big)
            .settingAlphaOne(in: big)
            .applyingGaussianBlur(sigma: 5)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 3, kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: [ // squeeze into 0.2...0.6 so noise never clips
                "inputRVector": CIVector(x: 0.4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.4, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.4, w: 0), "inputBiasVector": CIVector(x: 0.2, y: 0.2, z: 0.2, w: 0),
            ])
            .cropped(to: e)
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
        for index in [0, 3, 11] {
            let offset = NightStacker.offset(of: frames[index], to: frames[5], context: processor.context)
            XCTAssertEqual(offset?.x ?? 99, 0, accuracy: 1.5, "frame \(index) is already lined up")
            XCTAssertEqual(offset?.y ?? 99, 0, accuracy: 1.5, "frame \(index) is already lined up")
        }
        // Compare before the shadow lift: undo it by comparing against the scene lifted the same way.
        let stacked = NightStacker.stack(frames, reference: 5, context: processor.context)
        let lifted = scene.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.35, "inputHighlightAmount": 1])
            .cropped(to: scene.extent)
        XCTAssertEqual(stacked.extent, scene.extent)
        XCTAssertLessThan(error(stacked, against: lifted), single * 0.6, "averaging 12 frames removes most of the noise")
    }

    func testStackOfIdenticalCleanFramesIsTheLiftedScene() {
        let lifted = scene.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.35, "inputHighlightAmount": 1])
            .cropped(to: scene.extent)
        let stacked = NightStacker.stack([scene, scene, scene], reference: 1, context: processor.context)
        XCTAssertLessThan(error(stacked, against: lifted), 3, "nothing to average: only the shadow lift changes it")
        XCTAssertLessThan(error(NightStacker.deghosted(noisy(1), reference: noisy(2), extent: scene.extent), against: noisy(1)), 3,
                          "grain alone never counts as movement")
    }

    func testRegistrationFindsAPanoramaSizedShift() throws {
        let shift = try XCTUnwrap(Registration.translation(of: window(200), to: window(0), maxShift: CGSize(width: 0.95, height: 0.15),
                                                           context: processor.context))
        XCTAssertEqual(shift.x, 200, accuracy: 4)
        XCTAssertEqual(shift.y, 0, accuracy: 4)
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
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4)) // repeats every 1024 px now, wider than the scene
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

    // MARK: Cinematic

    func testCinematicFocusStateRacksBetweenPoints() throws {
        let keys = [CinematicFocus(time: 2, x: 0.8, y: 0.5), CinematicFocus(time: 0, x: 0.2, y: 0.5)]
        let start = try XCTUnwrap(CinematicFocus.state(keys, at: 1))
        XCTAssertEqual(start.current.x, 0.2)
        XCTAssertNil(start.previous)
        XCTAssertEqual(start.progress, 1)
        let racking = try XCTUnwrap(CinematicFocus.state(keys, at: 2.2))
        XCTAssertEqual(racking.current.x, 0.8)
        XCTAssertEqual(racking.previous?.x, 0.2)
        XCTAssertEqual(racking.progress, 0.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(CinematicFocus.state(keys, at: 5)).progress, 1)
        XCTAssertNil(CinematicFocus.state([], at: 1))
        let before = try XCTUnwrap(CinematicFocus.state([CinematicFocus(time: 3, x: 0.1, y: 0.1)], at: 0))
        XCTAssertEqual(before.current.time, 3, "before the first point, the first point holds")
    }

    func testCinematicFocusDecodesTolerantlyAndResets() throws {
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(
            #"{"cinematicFocus":[{"time":-3,"x":9,"y":"bad"},{"time":1,"x":0.3,"y":0.4,"background":true}]}"#.utf8))
        XCTAssertEqual(decoded.cinematicFocus.count, 2)
        XCTAssertEqual(decoded.cinematicFocus[0].time, 0)
        XCTAssertEqual(decoded.cinematicFocus[0].x, 1)
        XCTAssertEqual(decoded.cinematicFocus[0].y, 0.5)
        XCTAssertTrue(decoded.cinematicFocus[1].background)
        XCTAssertTrue(decoded.resetting(.subjectStyle).cinematicFocus.isEmpty)
    }

    func testCompositionTimeMapsToTheOriginalVideo() {
        let box = AdjustmentBox()
        XCTAssertEqual(box.sourceTime(2), 2)
        box.timeMapping = (start: 3, speed: 0.25) // trimmed from 3 s, SLO-MO
        XCTAssertEqual(box.sourceTime(4), 4, "4 s into a quarter-speed export is 1 s past the trim start")
    }

    @MainActor
    func testCinematicModeTurnsOnDepthForVideosOnly() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Cine-\(UUID().uuidString)") ?? .standard)
        vm.mode = .cinematic
        vm.modeChanged()
        XCTAssertFalse(vm.adjustments.portrait, "no video loaded: nothing to blur")
        vm.addCinematicFocus(at: CGPoint(x: 0.5, y: 0.5), viewPoint: .zero)
        XCTAssertTrue(vm.adjustments.cinematicFocus.isEmpty)
        XCTAssertTrue(CameraMode.cinematic.explanation.contains("tap"))
    }

    // MARK: Smooth slow motion

    private func squareFrame(at x: CGFloat) -> CIImage {
        let e = CGRect(x: 0, y: 0, width: 256, height: 192)
        return CIImage(color: .white).cropped(to: CGRect(x: x, y: 76, width: 40, height: 40))
            .composited(over: solid(0.3, 0.3, 0.3, 256, 192)).cropped(to: e)
    }

    func testInBetweenFrameMovesTheSquareHalfway() throws {
        XCTAssertNotNil(ImageProcessingService.interpolateKernel)
        let a = squareFrame(at: 100), b = squareFrame(at: 124) // moves 24 px right
        guard let flow = FrameInterpolator.flow(from: a, to: b) else {
            #if targetEnvironment(simulator)
            throw XCTSkip("Vision optical flow isn't available in this simulator; the effect then holds frames")
            #else
            return XCTFail("no optical flow")
            #endif
        }
        let direction = FrameInterpolator.calibrate(a: a, b: b, flow: flow, context: processor.context)
        let middle = FrameInterpolator.frame(between: a, and: b, flow: flow, t: 0.5, direction: direction)
        XCTAssertEqual(middle.extent, a.extent)
        XCTAssertGreaterThan(pixel(middle, 115, 96).g, 220, "the square's left edge has moved to ~112")
        XCTAssertGreaterThan(pixel(middle, 150, 96).g, 220, "and its right edge to ~152")
        XCTAssertLessThan(pixel(middle, 104, 96).g, 170, "not left where it started")
        // A plain cross-fade would leave both squares half bright instead.
    }

    func testSmoothSlowMotionWritesFourTimesTheFrames() async throws {
        let source = try await VideoPipelineTests.makeTestMovie(frames: 10)
        let url = try LiveEffectsService.newURL("mov")
        try await LiveEffectsService.smoothSlowMotion(
            from: AVURLAsset(url: source), range: CMTimeRange(start: .zero, duration: CMTime(value: 10, timescale: 30)),
            adjustments: PhotoAdjustmentState(), processor: .shared, to: url)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertEqual(duration, Double(9 * 4 + 1) / 30, accuracy: 0.1, "9 gaps × 4 + the last frame")
        XCTAssertTrue(LiveEffect.allCases.contains(.smoothSlowMo))
    }

    // MARK: Remove brush

    /// One dot stroke at (x, y) normalized top-left, `width` of the short side.
    private func dot(_ x: CGFloat, _ y: CGFloat, width: Double) -> MaskStroke {
        MaskStroke(add: true, width: width, points: [CGPoint(x: x, y: y)])
    }

    func testRemoveFillsASpotOnAPlainWall() {
        // Mid-gray wall with a black spot in the middle (CI: bottom-left origin).
        let wall = solid(0.55, 0.5, 0.45, 300, 200)
        let spot = solid(0.02, 0.02, 0.02, 30, 30).transformed(by: CGAffineTransform(translationX: 135, y: 85))
        let photo = spot.composited(over: wall).cropped(to: wall.extent)
        var state = PhotoAdjustmentState()
        state.removeStrokes = [dot(0.5, 0.5, width: 0.25)]
        let output = processor.apply(state, to: photo)
        XCTAssertEqual(output.extent, photo.extent)
        let center = pixel(output, 150, 100), wallColor = pixel(wall, 150, 100)
        XCTAssertEqual(center.r, wallColor.r, accuracy: 8, "the spot is gone, filled with the wall's color")
        XCTAssertEqual(center.b, wallColor.b, accuracy: 8)
        XCTAssertEqual(pixel(output, 20, 20).g, pixel(photo, 20, 20).g, accuracy: 1, "away from the stroke nothing changes")
    }

    func testRemoveKeepsTextureOnStripes() {
        // Vertical stripes with a gray blob: the fill should carry stripes, not a flat smear.
        let stripes = (CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0.8, green: 0.8, blue: 0.8), "inputColor1": CIColor(red: 0.2, green: 0.2, blue: 0.2),
            "inputWidth": 6, "inputSharpness": 0.5,
        ])?.outputImage ?? CIImage(color: .gray)).cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
        let blob = solid(0.5, 0.5, 0.5, 30, 30).transformed(by: CGAffineTransform(translationX: 113, y: 113))
        let photo = blob.composited(over: stripes).cropped(to: stripes.extent)
        var state = PhotoAdjustmentState()
        state.removeStrokes = [dot(0.5, 0.5, width: 0.16)]
        let output = processor.apply(state, to: photo)
        var values: [Double] = []
        for x in stride(from: CGFloat(118), to: 140, by: 1) { values.append(pixel(output, x, 128).g) }
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        XCTAssertGreaterThan(spread, 60, "stripes continue through the filled area")
    }

    func testBestOffsetPicksAnUnpaintedMatchingArea() throws {
        let w = 64, h = 64
        var photo = [UInt8](repeating: 100, count: w * h), hole = [UInt8](repeating: 0, count: w * h)
        for y in 28..<36 { for x in 28..<36 { hole[y * w + x] = 255; photo[y * w + x] = 0 } }
        let offset = try XCTUnwrap(ImageProcessingService.bestOffset(photo: photo, hole: hole, allHoles: hole, width: w, height: h))
        XCTAssertNotEqual(offset.x == 0 && offset.y == 0, true)
        XCTAssertNil(ImageProcessingService.bestOffset(photo: photo, hole: [UInt8](repeating: 0, count: w * h),
                                                       allHoles: hole, width: w, height: h))
    }

    func testRemoveIsAPhotoControlAndDecodes() throws {
        XCTAssertEqual(CameraControl.remove.group, .tools)
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(#"{"removeStrokes":"junk"}"#.utf8))
        XCTAssertTrue(decoded.removeStrokes.isEmpty)
        var state = PhotoAdjustmentState()
        state.removeStrokes = [dot(0.5, 0.5, width: 0.1)]
        XCTAssertTrue(state.isHeavy)
        XCTAssertEqual(try JSONDecoder().decode(PhotoAdjustmentState.self, from: JSONEncoder().encode(state)), state)
    }

    // MARK: Photos editing extension

    func testPhotosEditRecipeRoundTripsAndIgnoresOtherApps() throws {
        var state = PhotoAdjustmentState()
        state.filter = .portra
        state.exposure = 0.4
        state.style = .amber
        let data = try PhotosEditFormat.encode(state)
        XCTAssertEqual(data.formatIdentifier, "com.cameraglass.edit")
        XCTAssertTrue(PhotosEditFormat.canHandle(data))
        XCTAssertEqual(PhotosEditFormat.decode(data), state.clamped())
        let other = PHAdjustmentData(formatIdentifier: "com.other.app", formatVersion: "1", data: Data("{}".utf8))
        XCTAssertFalse(PhotosEditFormat.canHandle(other))
        XCTAssertNil(PhotosEditFormat.decode(other))
        let broken = PHAdjustmentData(formatIdentifier: "com.cameraglass.edit", formatVersion: "1", data: Data("nope".utf8))
        XCTAssertNil(PhotosEditFormat.decode(broken), "a damaged recipe starts fresh instead of crashing")
    }

    func testNightIsAnEffect() {
        XCTAssertTrue(LiveEffect.allCases.contains(.night))
        XCTAssertEqual(LiveEffect.night.title, "NIGHT")
    }
}
