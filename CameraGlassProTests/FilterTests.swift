import CoreImage
import XCTest
@testable import CameraGlassPro

final class FilterCatalogTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    func testEveryFilterHasACategoryAndName() {
        let grouped = FilterCategory.allCases.flatMap(\.filters)
        XCTAssertEqual(Set(grouped), Set(PhotoFilter.allCases.filter { $0 != .none }), "each filter appears in one tab")
        XCTAssertEqual(grouped.count, Set(grouped).count, "no filter appears twice")
        for filter in PhotoFilter.allCases { XCTAssertFalse(filter.label.isEmpty) }
        XCTAssertEqual(FilterCategory.y2k.filters.count, 8)
        XCTAssertEqual(FilterCategory.digicam.title, "DigiCam FX")
        XCTAssertEqual(FilterCategory.digicam.filters, [.pointShoot, .nightFlash, .coolCCD, .y2006, .digicam, .ccd, .retro])
        XCTAssertEqual(grouped.count, 112, "112 filters")
        XCTAssertEqual(FilterCategory.allCases.count, 14)
        for category in FilterCategory.allCases { XCTAssertFalse(category.filters.isEmpty, "\(category) is empty") }
        XCTAssertEqual(Set(PhotoFilter.allCases.map(\.label)).count, PhotoFilter.allCases.count, "names are unique")
    }

    func testEveryFilterRendersWithSameExtent() throws {
        let input = CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        for filter in PhotoFilter.allCases {
            var state = PhotoAdjustmentState()
            state.filter = filter
            let output = processor.apply(state, to: input)
            XCTAssertEqual(output.extent, input.extent, "\(filter) changed the size")
            XCTAssertNotNil(processor.context.createCGImage(output, from: input.extent), "\(filter) failed to render")
        }
    }

    /// Renders `image` to an 8-bit gray bitmap (w x h) for pixel checks.
    private func lumaPixels(_ image: CIImage, width: Int, height: Int) -> [Double] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                                                             y: CGFloat(height) / image.extent.height))
        processor.context.render(scaled, toBitmap: &pixels, rowBytes: width * 4,
                                 bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return stride(from: 0, to: pixels.count, by: 4).map { (i: Int) -> Double in
            let r: Double = 0.2126 * Double(pixels[i])
            let g: Double = 0.7152 * Double(pixels[i + 1])
            let b: Double = 0.0722 * Double(pixels[i + 2])
            return r + g + b
        }
    }

    /// No filter may add text, timestamps, logos or other marks: on a flat image the result must stay
    /// smooth (text would create sharp local edges). Smooth falloff like a vignette is allowed.
    func testNoFilterDrawsTextOrMarks() {
        let flat = CIImage(color: CIColor(red: 0.45, green: 0.42, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        for filter in PhotoFilter.allCases {
            var state = PhotoAdjustmentState()
            state.filter = filter
            let output = processor.apply(state, to: flat)
            let smooth = output.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: output.extent)
            let a = lumaPixels(output, width: 64, height: 48)
            let b = lumaPixels(smooth, width: 64, height: 48)
            var worst = 0.0
            for y in 4..<44 { for x in 4..<60 { worst = max(worst, abs(a[y * 64 + x] - b[y * 64 + x])) } }
            XCTAssertLessThan(worst, 12, "\(filter) added sharp marks (text or overlay?) to a flat image")
        }
    }

    func testRemovedFiltersLoadAsNoFilter() throws {
        let json = #"{"exposure":0,"filter":"dateStamp"}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.filter, .none)
        XCTAssertEqual(state.exposure, 0)
    }

    // MARK: Film grain

    private func standardDeviation(_ values: [Double]) -> Double {
        let mean: Double = values.reduce(0, +) / Double(values.count)
        let squares: [Double] = values.map { (v: Double) -> Double in (v - mean) * (v - mean) }
        return (squares.reduce(0, +) / Double(values.count)).squareRoot()
    }

    private func grainSpread(on gray: CGFloat, amount: Double) -> Double {
        let input = CIImage(color: CIColor(red: gray, green: gray, blue: gray)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let output = processor.filmGrain(input, amount: amount, extent: input.extent)
        // Sample at full resolution (crop, no scaling) so grain isn't averaged away.
        let crop = output.cropped(to: CGRect(x: 100, y: 100, width: 64, height: 48))
            .transformed(by: CGAffineTransform(translationX: -100, y: -100))
        let values = lumaPixels(crop, width: 64, height: 48)
        return standardDeviation(values)
    }

    func testGrainKernelCompiles() {
        XCTAssertNotNil(ImageProcessingService.grainKernel, "Metal grain kernel failed to compile: grain would silently do nothing")
    }

    func testZeroGrainIsExactlyClean() {
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertTrue(processor.filmGrain(input, amount: 0, extent: input.extent) === input)
        XCTAssertTrue(processor.apply(PhotoAdjustmentState(), to: input) === input)
        XCTAssertEqual(grainSpread(on: 0.5, amount: 0), 0, accuracy: 0.01)
    }

    func testGrainFollowsLuminanceLikeFilm() {
        let mid = grainSpread(on: 0.5, amount: 0.6)
        XCTAssertGreaterThan(mid, grainSpread(on: 0.03, amount: 0.6), "grain fades in deep shadows")
        XCTAssertGreaterThan(mid, grainSpread(on: 0.97, amount: 0.6), "grain fades in bright highlights")
    }

    func testGrainIsFineAndProgressive() {
        let subtle = grainSpread(on: 0.5, amount: 0.2)
        let strong = grainSpread(on: 0.5, amount: 1)
        XCTAssertGreaterThan(subtle, 0.3, "visible at low settings")
        XCTAssertGreaterThan(strong, subtle, "smooth progression")
        XCTAssertLessThan(strong, 30, "even at maximum it stays photographic, not a wall of noise")
    }

    func testGrainNeverTintsColors() {
        let input = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let output = processor.filmGrain(input, amount: 1, extent: input.extent).cropped(to: CGRect(x: 100, y: 100, width: 64, height: 48))
            .transformed(by: CGAffineTransform(translationX: -100, y: -100))
        var pixels = [UInt8](repeating: 0, count: 64 * 48 * 4)
        processor.context.render(output, toBitmap: &pixels, rowBytes: 64 * 4, bounds: CGRect(x: 0, y: 0, width: 64, height: 48),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let redMinusGreen: [Double] = stride(from: 0, to: pixels.count, by: 4).map { (i: Int) -> Double in Double(pixels[i]) - Double(pixels[i + 1]) }
        let spread = standardDeviation(redMinusGreen)
        XCTAssertLessThan(spread, 1.5, "grain changes brightness only, never hue (no red/green speckle)")
        XCTAssertGreaterThan(Set(stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 1] }).count, 4, "grain is there")
    }

    /// Neighbor difference relative to overall spread: lower means bigger, smoother grains.
    private func grainRoughness(_ size: GrainSize) -> Double {
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 2400, height: 300))
        let crop = processor.filmGrain(input, amount: 1, size: size, extent: input.extent)
            .cropped(to: CGRect(x: 400, y: 100, width: 128, height: 64))
            .transformed(by: CGAffineTransform(translationX: -400, y: -100))
        let values = lumaPixels(crop, width: 128, height: 64)
        let spread = standardDeviation(values)
        let steps: [Double] = zip(values, values.dropFirst()).map { (a: Double, b: Double) -> Double in abs(a - b) }
        let step: Double = steps.reduce(0, +) / Double(steps.count)
        return step / max(spread, 0.001)
    }

    func testGrainSizeChangesGrainSize() {
        XCTAssertGreaterThan(grainRoughness(.fine), grainRoughness(.medium))
        XCTAssertGreaterThan(grainRoughness(.medium), grainRoughness(.coarse))
    }

    // MARK: Auto enhance

    private func flat(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 400) -> [UInt8] {
        (0..<count).flatMap { _ in [r, g, b, 255] }
    }

    func testAutoBrightensDarkPhotos() {
        let state = ImageProcessingService.autoEnhanced(PhotoAdjustmentState(), rgba: flat(40, 40, 40))
        XCTAssertGreaterThan(state.exposure, 0.3)
    }

    func testAutoLeavesWellExposedNeutralPhotosAlmostAlone() {
        var pixels: [UInt8] = []
        for v in stride(from: 10, through: 245, by: 5) { pixels += flat(UInt8(v), UInt8(v), UInt8(v), count: 8) }
        let state = ImageProcessingService.autoEnhanced(PhotoAdjustmentState(), rgba: pixels)
        XCTAssertEqual(state.exposure, 0, accuracy: 0.3)
        XCTAssertEqual(state.warmth, 0)
        XCTAssertEqual(state.contrast, 1)
    }

    func testAutoWarmsBlueCastAndRecoversClippedHighlights() {
        XCTAssertGreaterThan(ImageProcessingService.autoEnhanced(PhotoAdjustmentState(), rgba: flat(90, 120, 170)).warmth, 0)
        XCTAssertLessThan(ImageProcessingService.autoEnhanced(PhotoAdjustmentState(), rgba: flat(250, 250, 250)).highlights, 0)
    }

    func testAutoKeepsFilterAndGrain() {
        var current = PhotoAdjustmentState()
        current.filter = .noir
        current.grain = 0.4
        let state = ImageProcessingService.autoEnhanced(current, rgba: flat(40, 40, 40))
        XCTAssertEqual(state.filter, .noir)
        XCTAssertEqual(state.grain, 0.4)
    }

    private func averageRed(_ image: CIImage) throws -> Double {
        let filter = try XCTUnwrap(CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent),
        ]))
        let output = try XCTUnwrap(filter.outputImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[0])
    }
}

@MainActor
final class FilterPickerModelTests: XCTestCase {
    func testGrainSizeIsUndoableAndSaved() throws {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Filters-\(UUID().uuidString)") ?? .standard)
        vm.setGrainSize(.coarse)
        XCTAssertEqual(vm.adjustments.grainSize, .coarse)
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: JSONEncoder().encode(vm.adjustments))
        XCTAssertEqual(decoded.grainSize, .coarse)
        vm.undo()
        XCTAssertEqual(vm.adjustments.grainSize, .medium)
        vm.autoEnhance() // no media: does nothing
        XCTAssertFalse(vm.hasEdits)
    }

    func testSetFilterIsUndoable() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Filters-\(UUID().uuidString)") ?? .standard)
        vm.setFilter(.y2kGlow)
        XCTAssertEqual(vm.adjustments.filter, .y2kGlow)
        vm.setFilter(.y2kGlow) // same filter: no extra undo step
        vm.undo()
        XCTAssertEqual(vm.adjustments.filter, .none)
    }

    func testFilterControlOpensPicker() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Filters-\(UUID().uuidString)") ?? .standard)
        vm.isControlPanelOpen = true
        vm.perform(.filter)
        XCTAssertTrue(vm.showFilterPicker)
        XCTAssertFalse(vm.isControlPanelOpen, "the panel closes so the pop-up has room")
    }
}
