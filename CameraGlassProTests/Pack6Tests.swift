import CoreImage
import XCTest
@testable import CameraGlassPro

/// Pack 6: sunset sky band, tiled Remove, Focus Brush, face retouch, Collage.
final class Pack6Tests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func pixel(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> (r: Double, g: Double, b: Double) {
        var p = [UInt8](repeating: 0, count: 4)
        processor.context.render(image, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(p[0]), Double(p[1]), Double(p[2]))
    }

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect)
    }

    private var checker: CIImage {
        CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 0.15, green: 0.4, blue: 0.1), "inputColor1": CIColor(red: 0.35, green: 0.55, blue: 0.2),
            "inputWidth": 3,
        ])?.outputImage ?? CIImage(color: .green)
    }

    // MARK: Sunset sky band

    /// Blue sky at the top, a smooth orange glow band, then textured land.
    func testSunsetGlowJustAboveTheHorizonCountsAsSky() throws {
        let e = CGRect(x: 0, y: 0, width: 300, height: 300)
        let scene = solid(0.25, 0.45, 0.85, CGRect(x: 0, y: 190, width: 300, height: 110))
            .composited(over: solid(0.95, 0.55, 0.25, CGRect(x: 0, y: 150, width: 300, height: 40)))
            .composited(over: checker.cropped(to: CGRect(x: 0, y: 0, width: 300, height: 150)))
            .cropped(to: e)
        let mask = try XCTUnwrap(processor.skyMask(for: scene, extent: e))
        XCTAssertGreaterThan(pixel(mask, 150, 250).r, 200, "blue sky is sky")
        XCTAssertGreaterThan(pixel(mask, 150, 170).r, 150, "the smooth orange glow just above the horizon is sky too")
        XCTAssertLessThan(pixel(mask, 150, 60).r, 40, "textured land is not")
    }

    // MARK: Remove

    func testTilesCoverEveryPaintedPixel() {
        let w = 64, h = 48
        var hole = [UInt8](repeating: 0, count: w * h)
        for y in 10..<30 { for x in 5..<50 { hole[y * w + x] = 255 } }
        let tiles = ImageProcessingService.tiles(of: hole, width: w, height: h, size: 12)
        XCTAssertGreaterThan(tiles.count, 4)
        for y in 10..<30 {
            for x in 5..<50 {
                XCTAssertTrue(tiles.contains { x >= $0.minX && x < $0.maxX && y >= $0.minY && y < $0.maxY }, "(\(x), \(y)) covered")
            }
        }
        XCTAssertTrue(ImageProcessingService.tiles(of: [UInt8](repeating: 0, count: w * h), width: w, height: h, size: 12).isEmpty)
    }

    // MARK: Focus Brush

    func testFocusBrushKeepsPaintedAreaSharpAndBlursFarAway() {
        let e = CGRect(x: 0, y: 0, width: 300, height: 200)
        let stripes = (CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0.9, green: 0.9, blue: 0.9), "inputColor1": CIColor(red: 0.1, green: 0.1, blue: 0.1),
            "inputWidth": 4, "inputSharpness": 1,
        ])?.outputImage ?? CIImage(color: .gray)).cropped(to: e)
        var state = PhotoAdjustmentState()
        state.focusStrokes = [MaskStroke(add: true, width: 0.2, points: [CGPoint(x: 0.15, y: 0.5)])] // left side
        state.focusBlur = 1
        XCTAssertTrue(state.isHeavy)
        let output = processor.apply(state, to: stripes)
        func contrast(_ x: CGFloat) -> Double {
            let values = stride(from: x, to: x + 12, by: 1).map { pixel(output, $0, 100).g }
            return (values.max() ?? 0) - (values.min() ?? 0)
        }
        XCTAssertGreaterThan(contrast(40), 150, "painted area stays sharp")
        XCTAssertLessThan(contrast(270), 60, "far side is blurred")
        XCTAssertTrue(state.canReset(.fxBlur))
        XCTAssertTrue(state.resetting(.fxBlur).focusStrokes.isEmpty)
    }

    // MARK: Face retouch

    func testFaceRetouchLeavesPhotosWithoutFacesAlone() {
        let flat = solid(0.6, 0.5, 0.4, CGRect(x: 0, y: 0, width: 120, height: 120))
        var state = PhotoAdjustmentState()
        state.eyeBrighten = 1
        state.teethWhiten = 1
        let output = processor.apply(state, to: flat)
        XCTAssertEqual(pixel(output, 60, 60).r, pixel(flat, 60, 60).r, accuracy: 1)
        XCTAssertEqual(AdjustmentParameter.eyes.group, .detail)
        XCTAssertEqual(AdjustmentParameter.teeth.title, "Whiten Teeth")
        XCTAssertTrue(state.canReset(.detail))
        XCTAssertEqual(state.resetting(.detail).eyeBrighten, 0)
    }

    func testTeethKernelWhitensYellowTeethButNotLips() throws {
        let kernel = try XCTUnwrap(ImageProcessingService.kernel("teethWhiten"))
        let e = CGRect(x: 0, y: 0, width: 8, height: 8)
        let mask = solid(1, 1, 1, e)
        let teeth = solid(0.85, 0.75, 0.5, e), lips = solid(0.7, 0.15, 0.2, e)
        let whiter = try XCTUnwrap(kernel.apply(extent: e, arguments: [teeth, mask, Float(1)]))
        let before = pixel(teeth, 4, 4), after = pixel(whiter, 4, 4)
        XCTAssertLessThan(after.r - after.b, before.r - before.b - 20, "less yellow")
        let lipsAfter = pixel(try XCTUnwrap(kernel.apply(extent: e, arguments: [lips, mask, Float(1)])), 4, 4)
        XCTAssertEqual(lipsAfter.r, pixel(lips, 4, 4).r, accuracy: 3, "lips stay red")
    }

    func testOldSavesDecodeWithoutTheNewSettings() throws {
        let old = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data("{}".utf8))
        XCTAssertTrue(old.focusStrokes.isEmpty)
        XCTAssertEqual(old.focusBlur, 0.6)
        XCTAssertEqual(old.eyeBrighten, 0)
        XCTAssertTrue(old.isIdentity)
    }

    // MARK: Collage

    func testEveryLayoutTilesTheFrameExactly() {
        for count in 2...Collage.maxPhotos {
            let layouts = Collage.layouts(for: count)
            XCTAssertFalse(layouts.isEmpty, "\(count) photos have a layout")
            for cells in layouts {
                XCTAssertEqual(cells.count, count)
                let area = cells.reduce(0) { $0 + $1.width * $1.height }
                XCTAssertEqual(area, 1, accuracy: 0.001, "no gaps or overlaps")
                for (i, a) in cells.enumerated() {
                    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001).contains(a))
                    for b in cells[(i + 1)...] { XCTAssertLessThan(a.intersection(b).width * a.intersection(b).height, 0.0001) }
                }
            }
        }
        XCTAssertTrue(Collage.layouts(for: 1).isEmpty)
    }

    func testCollageRendersEdgeToEdgeAtTheChosenShape() throws {
        let red = solid(1, 0, 0, CGRect(x: 0, y: 0, width: 400, height: 300))
        let blue = solid(0, 0, 1, CGRect(x: 0, y: 0, width: 300, height: 400))
        let collage = try XCTUnwrap(Collage.render([red, blue], layout: Collage.layouts(for: 2)[0], shape: .portrait, longEdge: 500))
        XCTAssertEqual(collage.extent, CGRect(x: 0, y: 0, width: 400, height: 500))
        XCTAssertGreaterThan(pixel(collage, 100, 250).r, 200, "left cell is the first photo")
        XCTAssertGreaterThan(pixel(collage, 300, 250).b, 200, "right cell is the second photo")
        XCTAssertGreaterThan(pixel(collage, 199, 2).r + pixel(collage, 200, 2).b, 400, "the cells meet with no gap or border")
        XCTAssertNil(Collage.render([red], layout: Collage.layouts(for: 2)[0], shape: .square, longEdge: 100))
    }

    @MainActor
    func testCollageNeedsTwoPhotos() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Collage-\(UUID().uuidString)") ?? .standard)
        XCTAssertFalse(vm.isAvailable(.collage))
        XCTAssertEqual(CameraControl.collage.group, .camera)
    }
}
