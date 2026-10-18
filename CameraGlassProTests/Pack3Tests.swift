import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import CameraGlassPro

final class Pack3Tests: XCTestCase {
    private let processor = ImageProcessingService.shared
    private let extent = CGRect(x: 0, y: 0, width: 300, height: 300)
    private let subjectRect = CGRect(x: 110, y: 110, width: 80, height: 100)

    private func flat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: extent)
    }

    private func average(_ image: CIImage, _ rect: CGRect) -> [Int] {
        let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(averaged, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return [Int(pixel[0]), Int(pixel[1]), Int(pixel[2])]
    }

    private var middle: CGRect { CGRect(x: 120, y: 120, width: 60, height: 60) }

    // MARK: Adjustments

    func testTintVibranceWhitesBlacks() {
        var state = PhotoAdjustmentState()
        state.tint = 1
        let magenta = average(processor.apply(state, to: flat(0.5, 0.5, 0.5)), middle)
        XCTAssertGreaterThan((magenta[0] + magenta[2]) / 2, magenta[1] + 4, "+ tint goes magenta")

        state = PhotoAdjustmentState()
        state.vibrance = 1
        let muted = flat(0.5, 0.45, 0.4)
        let vivid = average(processor.apply(state, to: muted), middle)
        let before = average(muted, middle)
        XCTAssertGreaterThan(vivid[0] - vivid[2], before[0] - before[2], "vibrance adds color")

        state = PhotoAdjustmentState()
        state.whites = 1
        XCTAssertGreaterThan(average(processor.apply(state, to: flat(0.8, 0.8, 0.8)), middle)[1], average(flat(0.8, 0.8, 0.8), middle)[1])
        state = PhotoAdjustmentState()
        state.blacks = 1
        XCTAssertGreaterThan(average(processor.apply(state, to: flat(0.02, 0.02, 0.02)), middle)[1], average(flat(0.02, 0.02, 0.02), middle)[1] + 10)
        state.blacks = 0
        state.dehaze = -1
        XCTAssertGreaterThan(average(processor.apply(state, to: flat(0.1, 0.1, 0.1)), middle)[1], 40, "- dehaze adds haze")
        XCTAssertEqual(AdjustmentParameter.tint.group, .color)
        XCTAssertEqual(AdjustmentParameter.whites.group, .light)
    }

    // MARK: Filters

    func testGameBoyIsGreenTones() {
        var state = PhotoAdjustmentState()
        state.filter = .gameBoy
        for gray: CGFloat in [0.1, 0.5, 0.9] {
            let rgb = average(processor.apply(state, to: flat(gray, gray * 0.8, gray * 0.6)), middle)
            XCTAssertGreaterThan(rgb[1], rgb[2], "green tone")
        }
        XCTAssertEqual(FilterCategory.travel.filters, [.tokyoNeon, .santoriniBlue, .parisRose])
    }

    // MARK: Light & Retro

    func testSpotlightDarkensTheEdges() {
        var state = PhotoAdjustmentState()
        state.spotlight = 1
        let output = processor.apply(state, to: flat(0.5, 0.5, 0.5))
        XCTAssertLessThan(average(output, CGRect(x: 0, y: 0, width: 20, height: 20))[1],
                          average(output, CGRect(x: 140, y: 140, width: 20, height: 20))[1] - 40)
    }

    func testBlindsMakeBarsOfLight() {
        var state = PhotoAdjustmentState()
        state.blinds = 1
        let output = processor.apply(state, to: flat(0.5, 0.5, 0.5))
        var values: [Int] = []
        for y in stride(from: 10, to: 290, by: 9) { values.append(average(output, CGRect(x: 150, y: y, width: 2, height: 2))[1]) }
        XCTAssertGreaterThan((values.max() ?? 0) - (values.min() ?? 0), 60, "light and shadow bars")
    }

    func testHalftoneBalanceAndModes() {
        let ramp = CIFilter.linearGradient()
        ramp.point0 = CGPoint(x: 0, y: 0)
        ramp.point1 = CGPoint(x: 300, y: 0)
        ramp.color0 = .black
        ramp.color1 = .white
        let input = (ramp.outputImage ?? flat(0.5, 0.5, 0.5)).cropped(to: extent)
        var state = PhotoAdjustmentState()
        state.halftone = 1
        state.halftoneBalance = -1
        let inky = average(processor.apply(state, to: input), extent)[1]
        state.halftoneBalance = 1
        let papery = average(processor.apply(state, to: input), extent)[1]
        XCTAssertGreaterThan(papery, inky + 30, "the slider sets how much white shows")
        state.halftoneColor = true
        XCTAssertEqual(processor.apply(state, to: input).extent, extent)
    }

    func testOtherLightAndRetroEffectsRender() {
        let dots = CIImage(color: .white).cropped(to: CGRect(x: 140, y: 140, width: 6, height: 6))
            .composited(over: flat(0.2, 0.25, 0.3))
        for change in [{ (s: inout PhotoAdjustmentState) in s.glow = 1 }, { $0.sparkle = 1 }, { $0.vhs = 1 },
                       { $0.chroma = 1 }, { $0.depthMap = 1 }, { $0.depthMap = 1; $0.depthHeat = true }] {
            var state = PhotoAdjustmentState()
            change(&state)
            let output = processor.apply(state, to: dots)
            XCTAssertEqual(output.extent, extent)
            XCTAssertNotEqual(average(output, CGRect(x: 100, y: 100, width: 100, height: 100)),
                              average(dots, CGRect(x: 100, y: 100, width: 100, height: 100)), "changes the photo")
        }
        var sparkle = PhotoAdjustmentState()
        sparkle.sparkle = 1
        let glints = processor.apply(sparkle, to: dots)
        XCTAssertGreaterThan(average(glints, CGRect(x: 160, y: 141, width: 15, height: 4))[1],
                             average(dots, CGRect(x: 160, y: 141, width: 15, height: 4))[1] + 15, "star arm beside the light")
        XCTAssertNotNil(ImageProcessingService.kernel("vhsLook"))
        XCTAssertNotNil(ImageProcessingService.kernel("combineChannels"))
    }

    func testDepthMapPutsTheSubjectNearest() {
        let mask = CIImage(color: .white).cropped(to: subjectRect).composited(over: CIImage(color: .black).cropped(to: extent))
        var state = PhotoAdjustmentState()
        state.depthMap = 1
        let output = processor.apply(state, to: flat(0.4, 0.4, 0.4), subjectMask: mask)
        XCTAssertGreaterThan(average(output, CGRect(x: 130, y: 130, width: 40, height: 60))[1],
                             average(output, CGRect(x: 10, y: 270, width: 40, height: 20))[1] + 80, "subject bright, far scene dark")
    }

    // MARK: Tools

    func testRefineSubjectAddAndErase() {
        let photo = flat(0.9, 0.2, 0.1)
        var state = PhotoAdjustmentState()
        state.hologram = 1
        // No detected subject: an add stroke defines one in the middle.
        state.maskStrokes = [MaskStroke(add: true, width: 0.3, points: [CGPoint(x: 0.5, y: 0.5)])]
        let black = CIImage(color: .black).cropped(to: extent)
        let output = processor.apply(state, to: photo, subjectMask: black)
        XCTAssertGreaterThan(average(output, middle)[2], average(photo, middle)[2] + 40, "painted area became the hologram")
        XCTAssertEqual(average(output, CGRect(x: 5, y: 5, width: 20, height: 20)), average(photo, CGRect(x: 5, y: 5, width: 20, height: 20)))

        state.maskStrokes.append(MaskStroke(add: false, width: 0.5, points: [CGPoint(x: 0.5, y: 0.5)]))
        let erased = processor.apply(state, to: photo, subjectMask: black)
        XCTAssertEqual(average(erased, middle)[0], average(photo, middle)[0], accuracy: 3, "erased again")
    }

    func testLiquifyPushesContent() {
        let square = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 100, y: 130, width: 40, height: 40))
            .composited(over: flat(0.3, 0.3, 0.3))
        var state = PhotoAdjustmentState()
        // Push right through the square's middle (top-left normalized: y 0.5).
        state.liquifyStrokes = [LiquifyStroke(points: [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.6, y: 0.5)], radius: 0.12, strength: 1)]
        let output = processor.apply(state, to: square)
        XCTAssertEqual(output.extent, extent)
        let beside = CGRect(x: 150, y: 140, width: 20, height: 20)
        XCTAssertGreaterThan(average(output, beside)[0], average(square, beside)[0] + 40, "red pushed to the right")
    }

    func testResetsCoverTheNewPages() {
        var state = PhotoAdjustmentState()
        state.glow = 0.5
        state.vhs = 0.5
        state.depthMap = 0.5
        XCTAssertEqual(state.resetting(.fxLight).glow, 0)
        XCTAssertEqual(state.resetting(.fxRetro).vhs, 0)
        XCTAssertEqual(state.resetting(.fxArt).depthMap, 0)
        XCTAssertEqual(state.resetting(.fxLight).vhs, 0.5, "only its own page")
    }
}
