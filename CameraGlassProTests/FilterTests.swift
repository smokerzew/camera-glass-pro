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
        XCTAssertEqual(FilterCategory.y2k.filters.count, 4)
        XCTAssertEqual(FilterCategory.digicam.title, "DigiCam FX")
        XCTAssertEqual(FilterCategory.digicam.filters, [.digicam, .ccd, .retro])
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
        return stride(from: 0, to: pixels.count, by: 4).map {
            0.2126 * Double(pixels[$0]) + 0.7152 * Double(pixels[$0 + 1]) + 0.0722 * Double(pixels[$0 + 2])
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

    private func grainSpread(on gray: CGFloat, amount: Double) -> Double {
        let input = CIImage(color: CIColor(red: gray, green: gray, blue: gray)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let output = processor.filmGrain(input, amount: amount, extent: input.extent)
        // Sample at full resolution (crop, no scaling) so grain isn't averaged away.
        let crop = output.cropped(to: CGRect(x: 100, y: 100, width: 64, height: 48))
            .transformed(by: CGAffineTransform(translationX: -100, y: -100))
        let values = lumaPixels(crop, width: 64, height: 48)
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
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
