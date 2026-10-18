import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import CameraGlassPro

final class FXTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    /// Fine black and white checkerboard: lots of detail, so blur shows up as lower spread.
    private func checker(_ size: CGSize = CGSize(width: 300, height: 300)) -> CIImage {
        let f = CIFilter.checkerboardGenerator()
        f.color0 = .black
        f.color1 = .white
        f.width = 4
        return (f.outputImage ?? CIImage(color: .gray)).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func spread(_ image: CIImage, in rect: CGRect) -> Double {
        let w = Int(rect.width), h = Int(rect.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let moved = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        processor.context.render(moved, toBitmap: &pixels, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let values: [Double] = stride(from: 0, to: pixels.count, by: 4).map { (i: Int) -> Double in Double(pixels[i + 1]) }
        let mean: Double = values.reduce(0, +) / Double(values.count)
        let squares: [Double] = values.map { (v: Double) -> Double in (v - mean) * (v - mean) }
        return (squares.reduce(0, +) / Double(values.count)).squareRoot()
    }

    func testTiltShiftKeepsTheBandSharp() {
        var state = PhotoAdjustmentState()
        state.tiltShift = 1
        state.tiltShiftPosition = 0.5
        let input = checker()
        let output = processor.apply(state, to: input)
        XCTAssertEqual(output.extent, input.extent)
        let band = CGRect(x: 100, y: 140, width: 100, height: 20)
        let top = CGRect(x: 100, y: 270, width: 100, height: 20)
        XCTAssertGreaterThan(spread(output, in: band), spread(input, in: band) * 0.85, "focus band stays sharp")
        XCTAssertLessThan(spread(output, in: top), spread(input, in: top) * 0.5, "top is blurred")
    }

    func testSpeedBlurStreaks() {
        let input = checker()
        let blurred = processor.speedBlurred(input, amount: 1, degrees: 0, extent: input.extent)
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        XCTAssertLessThan(spread(blurred, in: rect), spread(input, in: rect) * 0.6)
        var state = PhotoAdjustmentState()
        state.speedBlur = 0.5
        XCTAssertTrue(state.needsSubject)
        XCTAssertEqual(state.withoutSubjectEdits.speedBlur, 0, "nothing to streak behind without a subject")
    }

    func testDoubleExposureBlendsTheSecondPhoto() {
        let input = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let second = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 80))
        var state = PhotoAdjustmentState()
        state.doubleExposure = 1
        let output = processor.apply(state, to: input, subjectMask: nil, backgroundPhoto: second)
        XCTAssertEqual(output.extent, input.extent)
        // Red came in: the red channel average rose well above the gray.
        let averaged = output.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: output.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(averaged, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertGreaterThan(Int(pixel[0]), Int(pixel[2]) + 60)
    }

    func testPaintedStrokeHidesOnlyThatArea() {
        let input = checker()
        for mode in [Redaction.blur, .pixelate] {
            var state = PhotoAdjustmentState()
            state.redactionTarget = .drawing
            // A thick stroke across the top-left quarter (normalized, top-left origin).
            state.redactionStrokes = [RedactionStroke(mode: mode, width: 0.2, points: [CGPoint(x: 0.05, y: 0.15), CGPoint(x: 0.45, y: 0.15)])]
            let output = processor.apply(state, to: input)
            let painted = CGRect(x: 40, y: 245, width: 80, height: 20) // CI y: top of the picture is high
            let untouched = CGRect(x: 180, y: 40, width: 80, height: 60)
            XCTAssertLessThan(spread(output, in: painted), spread(input, in: painted) * 0.5, "\(mode) hides the painted area")
            XCTAssertEqual(spread(output, in: untouched), spread(input, in: untouched), accuracy: 2, "\(mode) leaves the rest")
        }
    }

    func testRedactionStrengthControlsHowMuchIsHidden() {
        let f = CIFilter.checkerboardGenerator()
        f.color0 = .black
        f.color1 = .white
        f.width = 24
        let input = (f.outputImage ?? CIImage(color: .gray)).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
        let whole = [RedactionStroke(mode: .blur, width: 1, points: [CGPoint(x: 0.5, y: 0.5)])]
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let light = processor.redact(input, faces: .none, strokes: whole, strength: 0, extent: input.extent)
        let heavy = processor.redact(input, faces: .none, strokes: whole, strength: 1, extent: input.extent)
        XCTAssertGreaterThan(spread(light, in: rect), spread(heavy, in: rect) + 10)
    }

    func testDispersionBreaksTheSubjectIntoParticles() {
        let extent = CGRect(x: 0, y: 0, width: 300, height: 300)
        let subjectRect = CGRect(x: 80, y: 60, width: 100, height: 180)
        let photo = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: subjectRect)
            .composited(over: CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: extent))
        let mask = CIImage(color: .white).cropped(to: subjectRect).composited(over: CIImage(color: .black).cropped(to: extent))
        var state = PhotoAdjustmentState()
        state.dispersion = 1
        state.dispersionSize = 0.5
        XCTAssertTrue(state.needsSubject)
        let output = processor.apply(state, to: photo, subjectMask: mask)
        XCTAssertEqual(output.extent, extent)
        func redness(_ image: CIImage, _ rect: CGRect) -> Int {
            let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            var pixel = [UInt8](repeating: 0, count: 4)
            processor.context.render(averaged, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return Int(pixel[0]) - Int(pixel[1])
        }
        let beside = CGRect(x: 185, y: 80, width: 100, height: 160) // right of the subject
        XCTAssertGreaterThan(redness(output, beside), redness(photo, beside) + 8, "red particles drift out to the right")
        let rightEdge = CGRect(x: 150, y: 80, width: 28, height: 140)
        XCTAssertLessThan(redness(output, rightEdge), redness(photo, rightEdge) - 8, "the subject's right side breaks up")
        XCTAssertEqual(state.withoutSubjectEdits.dispersion, 0)
    }

    func testFaceRedactionWithoutFacesChangesNothing() {
        let input = checker()
        var state = PhotoAdjustmentState()
        state.faceRedaction = .pixelate
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        XCTAssertEqual(spread(processor.apply(state, to: input), in: rect), spread(input, in: rect), accuracy: 1)
    }

    func testSavedStrokesAreLimited() throws {
        var state = PhotoAdjustmentState()
        state.redactionStrokes = Array(repeating: RedactionStroke(mode: .blur, width: 0.1, points: [.zero]), count: 80)
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.redactionStrokes.count, RedactionStroke.limit)
    }

    @MainActor
    func testShufflePicksAnotherFilter() {
        var state = PhotoAdjustmentState()
        state.filter = .portra
        for _ in 0..<20 {
            let next = CameraWorkspaceViewModel.shuffled(state)
            XCTAssertNotEqual(next.filter, .portra)
            XCTAssertNotEqual(next.filter, .none)
        }
    }

    func testStickerIsTrimmedAndTransparent() throws {
        let photo = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 100, y: 50, width: 100, height: 150))
            .composited(over: CIImage(color: .black).cropped(to: photo.extent))
        let data = try XCTUnwrap(processor.stickerPNG(edited: photo, mask: mask))
        let image = try XCTUnwrap(CIImage(data: data))
        XCTAssertLessThan(image.extent.width, 140, "trimmed to the subject")
        XCTAssertGreaterThan(image.extent.width, 90)
    }

    func testParallaxVideoIsWritten() async throws {
        let photo = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 160))
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 60, y: 30, width: 80, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: photo.extent))
        let url = try LiveEffectsService.newURL("mov")
        try await ParallaxVideo.render(edited: photo, mask: mask, processor: processor, to: url)
        let duration = try await AVURLAsset(url: url).load(.duration)
        XCTAssertEqual(duration.seconds, ParallaxVideo.seconds, accuracy: 0.2)
    }

    func testPanelPagesStaySmall() {
        for group in PanelGroup.allCases {
            let count = CameraControl.allCases.filter { $0.group == group }.count
            XCTAssertTrue((1...8).contains(count), "\(group) has \(count) controls")
        }
        for group in AdjustGroup.allCases where group != .local && group != .ai {
            XCTAssertFalse(AdjustmentParameter.allCases.filter { $0.group == group }.isEmpty)
        }
    }
}

@MainActor
final class PopUpTests: XCTestCase {
    func testClosePopUpsClosesEverything() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "PopUp-\(UUID().uuidString)") ?? .standard)
        XCTAssertFalse(vm.isPopUpOpen)
        vm.openFXPicker()
        XCTAssertTrue(vm.isPopUpOpen)
        vm.closePopUps()
        XCTAssertFalse(vm.isPopUpOpen)
    }
}

final class DispersionDirectionTests: XCTestCase {
    func testParticlesFollowTheDirection() {
        let processor = ImageProcessingService.shared
        let extent = CGRect(x: 0, y: 0, width: 300, height: 300)
        let subjectRect = CGRect(x: 110, y: 110, width: 80, height: 80)
        let photo = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: subjectRect)
            .composited(over: CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: extent))
        let mask = CIImage(color: .white).cropped(to: subjectRect).composited(over: CIImage(color: .black).cropped(to: extent))
        func redness(_ image: CIImage, _ rect: CGRect) -> Int {
            let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            var pixel = [UInt8](repeating: 0, count: 4)
            processor.context.render(averaged, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return Int(pixel[0]) - Int(pixel[1])
        }
        let left = CGRect(x: 10, y: 110, width: 90, height: 80)
        let right = CGRect(x: 200, y: 110, width: 90, height: 80)
        let toLeft = processor.dispersion(photo, mask: mask, amount: 1, size: 0.5, degrees: 180, extent: extent)
        XCTAssertGreaterThan(redness(toLeft, left), redness(toLeft, right) + 8, "180° drifts left")
        let toRight = processor.dispersion(photo, mask: mask, amount: 1, size: 0.5, degrees: 0, extent: extent)
        XCTAssertGreaterThan(redness(toRight, right), redness(toRight, left) + 8, "0° drifts right")
    }
}

final class RedactionTargetTests: XCTestCase {
    private func centerPixels(_ image: CIImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
        ImageProcessingService.shared.context.render(
            image.cropped(to: CGRect(x: 140, y: 140, width: 20, height: 20))
                .transformed(by: CGAffineTransform(translationX: -140, y: -140)),
            toBitmap: &pixels, rowBytes: 80, bounds: CGRect(x: 0, y: 0, width: 20, height: 20),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return pixels
    }

    func testOnlyTheChosenTargetIsHidden() {
        let f = CIFilter.checkerboardGenerator()
        f.color0 = .black
        f.color1 = .white
        f.width = 4
        let input = (f.outputImage ?? CIImage(color: .gray)).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
        var state = PhotoAdjustmentState()
        state.redactionStrokes = [RedactionStroke(mode: .pixelate, width: 1, points: [CGPoint(x: 0.5, y: 0.5)])]
        state.redactionTarget = .faces // strokes kept but not shown
        let processor = ImageProcessingService.shared
        XCTAssertEqual(centerPixels(processor.apply(state, to: input)), centerPixels(input), "Faces mode ignores the drawing")
        state.redactionTarget = .drawing
        XCTAssertNotEqual(centerPixels(processor.apply(state, to: input)), centerPixels(input), "Drawing mode hides it")
    }

    func testOldSavesWithStrokesOpenInDrawingMode() throws {
        let json = #"{"redactionStrokes":[{"mode":"blur","width":0.1,"points":[[0.5,0.5]]}],"faceRedaction":"blur"}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.redactionTarget, .drawing)
    }

    @MainActor
    func testSwitchingKeepsBothSettings() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Target-" + UUID().uuidString) ?? .standard)
        vm.setFaceRedaction(.blur)
        XCTAssertTrue(vm.isActive(.fx))
        let stroke = RedactionStroke(mode: .blur, width: 0.1, points: [CGPoint(x: 0.5, y: 0.5)])
        vm.setRedactionStrokes([stroke])
        XCTAssertEqual(vm.adjustments.redactionTarget, .drawing, "drawing switches the target")
        vm.setRedactionTarget(.faces)
        XCTAssertEqual(vm.adjustments.redactionStrokes, [stroke], "strokes are kept")
        XCTAssertEqual(vm.adjustments.faceRedaction, .blur, "face setting is kept")
    }
}

final class ResetAreaTests: XCTestCase {
    private var busy: PhotoAdjustmentState {
        var s = PhotoAdjustmentState()
        s.exposure = 0.5
        s.nightLook = true
        s.warmth = 0.3
        s.colorMixer[.blue, .hue] = 0.4
        s.sharpen = 0.5
        s.vignette = 0.4
        s.grain = 0.3
        s.localAdjustments = [LocalAdjustment(shape: .radial)]
        s.filter = .portra
        s.filterStrength = 0.6
        s.speedBlur = 0.5
        s.doubleExposure = 0.5
        s.faceRedaction = .blur
        s.colorSplash = true
        s.dispersion = 0.5
        s.rotation = 1
        return s
    }

    func testEachAreaResetsOnlyItself() {
        let light = busy.resetting(.light)
        XCTAssertEqual(light.exposure, 0)
        XCTAssertFalse(light.nightLook)
        XCTAssertEqual(light.filter, .portra, "filters stay")
        XCTAssertEqual(light.warmth, 0.3, "other tabs stay")

        let color = busy.resetting(.color)
        XCTAssertEqual(color.warmth, 0)
        XCTAssertTrue(color.colorMixer.isNeutral)
        XCTAssertEqual(color.exposure, 0.5)

        let adjust = busy.resetting(.adjust)
        XCTAssertEqual(adjust.exposure, 0)
        XCTAssertEqual(adjust.sharpen, 0)
        XCTAssertTrue(adjust.localAdjustments.isEmpty)
        XCTAssertEqual(adjust.filter, .portra, "Adjust's reset keeps the filter")
        XCTAssertEqual(adjust.speedBlur, 0.5, "and FX")
        XCTAssertEqual(adjust.rotation, 1, "and the crop")

        let filter = busy.resetting(.filter)
        XCTAssertEqual(filter.filter, .none)
        XCTAssertEqual(filter.filterStrength, 1)
        XCTAssertEqual(filter.exposure, 0.5)

        XCTAssertEqual(busy.resetting(.fxBlur).speedBlur, 0)
        XCTAssertEqual(busy.resetting(.fxBlur).doubleExposure, 0.5)
        XCTAssertEqual(busy.resetting(.fxPrivacy).faceRedaction, .none)
        XCTAssertFalse(busy.resetting(.subjectStyle).colorSplash)
        XCTAssertEqual(busy.resetting(.subjectCreate).dispersion, 0)
        XCTAssertFalse(PhotoAdjustmentState().canReset(.light))
    }

    @MainActor
    func testResetIsUndoable() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Reset-" + UUID().uuidString) ?? .standard)
        vm.setAdjustment(.exposure, to: 0.5)
        vm.setFilter(.portra)
        vm.reset(.light)
        XCTAssertEqual(vm.adjustments.exposure, 0)
        XCTAssertEqual(vm.adjustments.filter, .portra)
        vm.undo()
        XCTAssertEqual(vm.adjustments.exposure, 0.5)
    }
}

final class MatchLookTests: XCTestCase {
    private func pixels(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 200) -> [UInt8] {
        (0..<count).flatMap { i in [UInt8(min(255, Int(r) + i % 20)), UInt8(min(255, Int(g) + i % 20)), UInt8(min(255, Int(b) + i % 20)), 255] }
    }

    func testMatchingAPhotoToItselfChangesNothing() {
        let stats = ColorStats.from(rgba: pixels(120, 110, 100))
        let match = LookMatch.between(source: stats, reference: stats)
        for c in 0..<3 { XCTAssertEqual(match.scale[c], 1, accuracy: 1e-6) }
        XCTAssertEqual(match.offset[0], 0, accuracy: 1e-6)
        XCTAssertEqual(match.offset[1], 0, accuracy: 1e-6)
        XCTAssertTrue(match.isUsable)
    }

    func testWarmReferenceWarmsTheRender() {
        let processor = ImageProcessingService.shared
        let source = ColorStats.from(rgba: pixels(120, 120, 120))
        let reference = ColorStats.from(rgba: pixels(200, 140, 70))
        var state = PhotoAdjustmentState()
        state.lookMatch = LookMatch.between(source: source, reference: reference, amount: 1)
        let gray = CIImage(color: CIColor(red: 0.47, green: 0.47, blue: 0.47)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let averaged = processor.apply(state, to: gray).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: gray.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(averaged, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertGreaterThan(Int(pixel[0]), Int(pixel[2]) + 30, "red above blue: warmer")
        XCTAssertNotNil(ImageProcessingService.kernel("matchLook"))
    }

    func testExtremeReferencesAreLimited() {
        let source = ColorStats(mean: [0.5, 0.5, 0.5], std: [0.2, 0.01, 0.01])
        let reference = ColorStats(mean: [1, 1, 0], std: [0.9, 0.5, 0.5])
        let match = LookMatch.between(source: source, reference: reference)
        XCTAssertLessThanOrEqual(match.scale[0], 1.6)
        XCTAssertLessThanOrEqual(match.scale[1], 2.0)
        XCTAssertTrue(match.isUsable)
    }

    @MainActor
    func testFrameNeedsAVideo() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Frame-" + UUID().uuidString) ?? .standard)
        XCTAssertFalse(vm.isAvailable(.frame))
        XCTAssertEqual(CameraControl.frame.group, .tools)
        XCTAssertEqual(PhotoAdjustmentState().resetting(.fxBlend).lookMatch, nil)
    }
}
