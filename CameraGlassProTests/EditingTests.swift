import CoreImage
import XCTest
@testable import CameraGlassPro

final class TextureGrainZebraTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func solid(_ value: CGFloat, size: CGFloat = 64) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value)).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func averageAlpha(_ image: CIImage) -> Double {
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[3])
    }

    func testTextureAndGrainKeepExtent() {
        var state = PhotoAdjustmentState()
        state.texture = 0.8
        state.grain = 0.6
        XCTAssertFalse(state.isIdentity)
        let input = solid(0.5)
        XCTAssertEqual(processor.apply(state, to: input).extent, input.extent)
    }

    func testGrainAddsVariation() throws {
        var state = PhotoAdjustmentState()
        state.grain = 1
        let output = processor.apply(state, to: solid(0.5))
        let image = try XCTUnwrap(processor.context.createCGImage(output, from: output.extent))
        let data = try XCTUnwrap(ScopeData.compute(from: image))
        let usedBins = data.luma.filter { $0 > 0 }.count
        XCTAssertGreaterThan(usedBins, 2, "grain should spread a flat gray across several tones")
    }

    func testZebrasOnlyOnHighlights() {
        XCTAssertGreaterThan(averageAlpha(processor.zebraOverlay(for: solid(1))), 20)
        XCTAssertLessThan(averageAlpha(processor.zebraOverlay(for: solid(0.5))), 2)
    }

    func testOlderSavedRecipesStillDecode() throws {
        let old = #"{"exposure":0.5,"brightness":0,"contrast":1.2,"saturation":1,"warmth":0,"highlights":0,"shadows":0,"nightLook":false}"#
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(old.utf8))
        XCTAssertEqual(state.exposure, 0.5)
        XCTAssertEqual(state.contrast, 1.2)
        XCTAssertEqual(state.texture, 0)
        XCTAssertEqual(state.filter, .none)
    }
}

@MainActor
final class UndoAndPresetTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "Editing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testUndoRedo() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        XCTAssertFalse(vm.canUndo)
        vm.cycleFilter()
        XCTAssertEqual(vm.adjustments.filter, .vivid)
        XCTAssertTrue(vm.canUndo)
        vm.undo()
        XCTAssertEqual(vm.adjustments.filter, .none)
        XCTAssertTrue(vm.canRedo)
        vm.redo()
        XCTAssertEqual(vm.adjustments.filter, .vivid)
    }

    func testRapidSliderChangesShareOneUndoStep() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        vm.setAdjustment(.exposure, to: 0.3)
        vm.setAdjustment(.exposure, to: 0.6)
        vm.setAdjustment(.exposure, to: 0.9)
        vm.undo()
        XCTAssertEqual(vm.adjustments.exposure, 0, "one undo reverts the whole drag")
        XCTAssertFalse(vm.canUndo)
    }

    func testPresetsPersistApplyAndDelete() throws {
        let defaults = makeDefaults()
        let vm = CameraWorkspaceViewModel(defaults: defaults)
        vm.setAdjustment(.warmth, to: 0.5)
        vm.savePreset(named: "  Warm  ")
        vm.resetAllAdjustments()

        let relaunched = CameraWorkspaceViewModel(defaults: defaults)
        let preset = try XCTUnwrap(relaunched.presets.first)
        XCTAssertEqual(preset.name, "Warm")
        relaunched.applyPreset(preset)
        XCTAssertEqual(relaunched.adjustments.warmth, 0.5)

        relaunched.savePreset(named: "warm") // same name replaces, no duplicate
        XCTAssertEqual(relaunched.presets.count, 1)
        relaunched.deletePreset(try XCTUnwrap(relaunched.presets.first))
        XCTAssertTrue(CameraWorkspaceViewModel(defaults: defaults).presets.isEmpty)
    }
}
