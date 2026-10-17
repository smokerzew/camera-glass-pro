import CoreImage
import XCTest
@testable import CameraGlassPro

final class PortraitRenderingTests: XCTestCase {
    private let processor = ImageProcessingService.shared
    private let extent = CGRect(x: 0, y: 0, width: 200, height: 100)

    /// Left half red (the "subject"), right half blue (the "background").
    private var scene: CIImage {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 100, y: 0, width: 100, height: 100))
        return red.composited(over: blue)
    }

    /// White over the left half = subject.
    private var leftMask: CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: extent))
    }

    private func average(_ image: CIImage, in rect: CGRect) -> (Double, Double, Double) {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    func testBlurRadiusFollowsAperture() {
        let wide = ImageProcessingService.portraitBlurRadius(aperture: 1.4, width: 3600)
        let mid = ImageProcessingService.portraitBlurRadius(aperture: 4, width: 3600)
        XCTAssertGreaterThan(wide, mid)
        XCTAssertEqual(ImageProcessingService.portraitBlurRadius(aperture: 16, width: 3600), 0, accuracy: 0.001)
        XCTAssertEqual(wide, 100, accuracy: 0.5)
    }

    func testStageLightBlacksOutTheBackground() {
        var state = PhotoAdjustmentState()
        state.portrait = true
        state.lighting = .stage
        let output = processor.apply(state, to: scene, subjectMask: leftMask)
        XCTAssertEqual(output.extent, extent)
        let background = average(output, in: CGRect(x: 130, y: 20, width: 60, height: 60))
        let subject = average(output, in: CGRect(x: 10, y: 20, width: 60, height: 60))
        XCTAssertLessThan(background.2, 20, "blue background turned black")
        XCTAssertGreaterThan(subject.0, 200, "red subject kept")
    }

    func testHighKeyWhitensTheBackgroundAndMonoSubject() {
        var state = PhotoAdjustmentState()
        state.portrait = true
        state.lighting = .highKey
        let output = processor.apply(state, to: scene, subjectMask: leftMask)
        let background = average(output, in: CGRect(x: 130, y: 20, width: 60, height: 60))
        let subject = average(output, in: CGRect(x: 10, y: 20, width: 60, height: 60))
        XCTAssertGreaterThan(background.0, 235)
        XCTAssertEqual(subject.0, subject.2, accuracy: 4, "subject is monochrome")
    }

    func testNoMaskMeansNoPortraitChange() {
        // A flat image has no subject; Portrait leaves it alone rather than blurring everything.
        var state = PhotoAdjustmentState()
        state.portrait = true
        let flat = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        _ = SubjectMasker.mask(for: flat) // must not crash (may be nil on the Simulator)
        XCTAssertEqual(processor.apply(state, to: flat, subjectMask: nil).extent, extent)
    }

    func testColorSplashKeepsSubjectColorAndGraysBackground() {
        var state = PhotoAdjustmentState()
        state.colorSplash = true
        XCTAssertTrue(state.needsSubject)
        let output = processor.apply(state, to: scene, subjectMask: leftMask)
        let subject = average(output, in: CGRect(x: 10, y: 20, width: 60, height: 60))
        let background = average(output, in: CGRect(x: 130, y: 20, width: 60, height: 60))
        XCTAssertGreaterThan(subject.0, 200, "subject stays red")
        XCTAssertLessThan(subject.2, 40)
        XCTAssertEqual(background.0, background.2, accuracy: 4, "background is black and white")
    }

    func testBackgroundSwapToWhiteAndSky() {
        var white = PhotoAdjustmentState()
        white.background = .white
        let whiteOut = processor.apply(white, to: scene, subjectMask: leftMask)
        XCTAssertGreaterThan(average(whiteOut, in: CGRect(x: 130, y: 20, width: 60, height: 60)).0, 230)
        XCTAssertGreaterThan(average(whiteOut, in: CGRect(x: 10, y: 20, width: 60, height: 60)).0, 200, "subject kept")

        var sky = PhotoAdjustmentState()
        sky.background = .sky
        let skyBG = average(processor.apply(sky, to: scene, subjectMask: leftMask), in: CGRect(x: 130, y: 20, width: 60, height: 60))
        XCTAssertGreaterThan(skyBG.2, skyBG.0, "sky background is blue-leaning")
    }

    func testBackgroundSwapToAPhoto() {
        var state = PhotoAdjustmentState()
        state.background = .photo
        let green = CIImage(color: CIColor(red: 0, green: 0.8, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 80))
        let output = processor.apply(state, to: scene, subjectMask: leftMask, backgroundPhoto: green)
        let background = average(output, in: CGRect(x: 130, y: 20, width: 60, height: 60))
        XCTAssertGreaterThan(background.1, 150, "the chosen photo fills the background")
        XCTAssertLessThan(background.2, 40)
        // Without a chosen photo, PHOTO falls back to the original background.
        let fallback = average(processor.apply(state, to: scene, subjectMask: leftMask), in: CGRect(x: 130, y: 20, width: 60, height: 60))
        XCTAssertGreaterThan(fallback.2, 200)
    }

    func testAspectFillCoversTheFrame() {
        let tall = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 300))
        let target = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertEqual(ImageProcessingService.aspectFill(tall, to: target).extent, target)
    }

    func testOldRecipesHaveNoSubjectEdits() throws {
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(#"{"exposure":0}"#.utf8))
        XCTAssertEqual(state.background, .original)
        XCTAssertFalse(state.colorSplash)
        XCTAssertFalse(state.needsSubject)
    }

    func testLightingNamesMatchTheCameraApp() {
        XCTAssertEqual(PortraitLighting.natural.label, "NATURAL LIGHT")
        XCTAssertEqual(PortraitLighting.stageMono.label, "STAGE LIGHT MONO")
        XCTAssertEqual(PortraitLighting.allCases.count, 6)
    }
}

@MainActor
final class PortraitStateTests: XCTestCase {
    private func makeVM() -> CameraWorkspaceViewModel {
        CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Portrait-\(UUID().uuidString)") ?? .standard)
    }

    func testDepthIsAnUndoableEdit() {
        let vm = makeVM()
        vm.setDepth(true)
        XCTAssertTrue(vm.adjustments.portrait)
        XCTAssertTrue(vm.depthEffect)
        vm.undo()
        XCTAssertFalse(vm.depthEffect)
    }

    func testApertureAndLighting() {
        let vm = makeVM()
        vm.setDepth(true)
        vm.setAperture(0.5)
        XCTAssertEqual(vm.adjustments.aperture, 1.4, "clamped to f/1.4")
        vm.setLighting(.studio)
        XCTAssertEqual(vm.adjustments.lighting, .studio)
        XCTAssertEqual(vm.depthTag, "STUDIO LIGHT")
        XCTAssertEqual(vm.valueText(for: .depth), "ƒ1.4")
    }

    func testTopBarFNumberOpensApertureSlider() {
        let vm = makeVM()
        vm.setDepth(true)
        vm.perform(.depth, fromTopBar: true)
        XCTAssertTrue(vm.isApertureDialVisible)
        XCTAssertTrue(vm.depthEffect, "tapping the f-number does not turn Portrait off")
    }
}
