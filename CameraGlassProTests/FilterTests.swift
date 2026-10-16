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

    func testDateStampDrawsInTheCorner() throws {
        let input = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        var stamp = PhotoAdjustmentState()
        stamp.filter = .dateStamp
        var digicam = PhotoAdjustmentState()
        digicam.filter = .digicam
        // Compare the bottom-right corner (Core Image origin is bottom-left) with and without the stamp.
        let corner = CGRect(x: 360, y: 0, width: 240, height: 80)
        let with = try averageRed(processor.apply(stamp, to: input).cropped(to: corner))
        let without = try averageRed(processor.apply(digicam, to: input).cropped(to: corner))
        XCTAssertGreaterThan(with, without + 3, "orange date text should brighten the corner")
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
