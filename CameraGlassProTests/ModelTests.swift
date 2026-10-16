import XCTest
@testable import CameraGlassPro

final class AdjustmentStateTests: XCTestCase {
    func testDefaultsAreIdentityAndInsideRanges() {
        let state = PhotoAdjustmentState()
        XCTAssertTrue(state.isIdentity)
        for parameter in AdjustmentParameter.allCases {
            XCTAssertTrue(parameter.range.contains(parameter.defaultValue), "\(parameter) default out of range")
            XCTAssertEqual(state[parameter], parameter.defaultValue)
        }
    }

    func testSubscriptClampsToRange() {
        var state = PhotoAdjustmentState()
        state[.exposure] = 99
        XCTAssertEqual(state.exposure, 2)
        state[.saturation] = -5
        XCTAssertEqual(state.saturation, 0)
        state[.highlights] = 0.5
        XCTAssertEqual(state.highlights, 0)
        state[.contrast] = .nan
        XCTAssertEqual(state.contrast, 1, "non-finite values fall back to the default")
    }

    func testClampedFixesDirectlyAssignedValues() {
        var state = PhotoAdjustmentState()
        state.warmth = 7
        state.shadows = -3
        let clamped = state.clamped()
        XCTAssertEqual(clamped.warmth, 1)
        XCTAssertEqual(clamped.shadows, -1)
    }

    func testResetSingleParameterKeepsOthers() {
        var state = PhotoAdjustmentState()
        state[.exposure] = 1
        state[.contrast] = 1.3
        state.reset(.exposure)
        XCTAssertEqual(state.exposure, 0)
        XCTAssertEqual(state.contrast, 1.3)
        XCTAssertFalse(state.isModified(.exposure))
        XCTAssertTrue(state.isModified(.contrast))
        XCTAssertFalse(state.isIdentity)
    }

    func testNightLookCountsAsEdit() {
        var state = PhotoAdjustmentState()
        state.nightLook = true
        XCTAssertFalse(state.isIdentity)
    }

    func testFormatting() {
        XCTAssertEqual(AdjustmentParameter.exposure.format(0.5), "+0.5 EV")
        XCTAssertEqual(AdjustmentParameter.contrast.format(1), "0")
        XCTAssertEqual(AdjustmentParameter.contrast.format(1.25), "+25")
        XCTAssertEqual(AdjustmentParameter.shadows.format(-0.4), "-40")
    }
}

final class FramingTests: XCTestCase {
    func testZoomClamp() {
        XCTAssertEqual(ZoomLimits.clamp(0.1), 0.5)
        XCTAssertEqual(ZoomLimits.clamp(12), 5)
        XCTAssertEqual(ZoomLimits.clamp(2), 2)
        XCTAssertEqual(ZoomLimits.clamp(.infinity), 1)
    }

    func testZoomLabels() {
        XCTAssertEqual(ZoomLimits.label(for: 0.5), ".5")
        XCTAssertEqual(ZoomLimits.label(for: 1), "1")
        XCTAssertEqual(ZoomLimits.label(for: 2.34), "2.3")
    }

    func testAspectRatiosFollowImageOrientation() {
        let portrait = CGSize(width: 3000, height: 4000)
        let landscape = CGSize(width: 4000, height: 3000)
        XCTAssertEqual(AspectRatioOption.fourThree.resolvedRatio(imageSize: portrait), 0.75, accuracy: 0.0001)
        XCTAssertEqual(AspectRatioOption.fourThree.resolvedRatio(imageSize: landscape), 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(AspectRatioOption.sixteenNine.resolvedRatio(imageSize: portrait), 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(AspectRatioOption.square.resolvedRatio(imageSize: landscape), 1)
        XCTAssertEqual(AspectRatioOption.original.resolvedRatio(imageSize: CGSize(width: 1000, height: 500)), 2)
        XCTAssertEqual(AspectRatioOption.original.resolvedRatio(imageSize: .zero), 0.75)
    }

    func testAspectCycleVisitsAllOptions() {
        var option = AspectRatioOption.original
        var seen: [AspectRatioOption] = []
        for _ in AspectRatioOption.allCases { seen.append(option); option = option.next }
        XCTAssertEqual(Set(seen), Set(AspectRatioOption.allCases))
        XCTAssertEqual(option, .original)
    }

    func testFrameSizeFitsContainer() {
        let size = FramingGeometry.frameSize(ratio: 0.75, in: CGSize(width: 390, height: 400))
        XCTAssertEqual(size.height, 400, accuracy: 0.001)
        XCTAssertEqual(size.width, 300, accuracy: 0.001)
        XCTAssertEqual(FramingGeometry.frameSize(ratio: 0, in: CGSize(width: 10, height: 10)), .zero)
    }

    func testVisibleRectFillCropsCenter() {
        // 4:3 landscape image in a 3:4 portrait frame, fill: full height, centered width.
        let rect = FramingGeometry.visibleRect(image: CGSize(width: 4000, height: 3000), ratio: 0.75, zoom: 1, fill: true)
        XCTAssertEqual(rect.height, 3000, accuracy: 0.5)
        XCTAssertEqual(rect.width, 2250, accuracy: 0.5)
        XCTAssertEqual(rect.midX, 2000, accuracy: 0.5)

        let zoomed = FramingGeometry.visibleRect(image: CGSize(width: 4000, height: 3000), ratio: 0.75, zoom: 2, fill: true)
        XCTAssertEqual(zoomed.width, 1125, accuracy: 0.5)
        XCTAssertEqual(zoomed.height, 1500, accuracy: 0.5)
        XCTAssertEqual(zoomed.midY, 1500, accuracy: 0.5)
    }

    func testVisibleRectNeverExceedsImage() {
        let image = CGSize(width: 4000, height: 3000)
        let fit = FramingGeometry.visibleRect(image: image, ratio: 0.75, zoom: 0.5, fill: false)
        XCTAssertEqual(fit, CGRect(origin: .zero, size: image))
        let normalized = FramingGeometry.normalizedVisibleRect(image: image, ratio: 1, zoom: 1, fill: true)
        XCTAssertEqual(normalized.height, 1, accuracy: 0.0001)
        XCTAssertEqual(normalized.width, 0.75, accuracy: 0.0001)
    }

    func testGridLineOffsets() {
        XCTAssertEqual(GridShape.lineOffsets(divisions: 3, length: 300), [100, 200])
        XCTAssertEqual(GridShape.lineOffsets(divisions: 6, length: 600).count, 5)
        XCTAssertTrue(GridShape.lineOffsets(divisions: 1, length: 300).isEmpty)
    }

    func testModesAreHonest() {
        XCTAssertFalse(CameraMode.photo.isPreviewOnly)
        for mode in CameraMode.allCases where mode != .photo {
            XCTAssertTrue(mode.isPreviewOnly)
            XCTAssertTrue(mode.explanation.hasPrefix("Preview only"), "\(mode) must say it is preview-only")
        }
    }
}

final class ErrorMappingTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(PhotoImportError.map(CancellationError()), .cancelled)
        XCTAssertEqual(PhotoImportError.map(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)), .cancelled)
        XCTAssertEqual(PhotoImportError.map(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)), .fileAccessDenied)
        XCTAssertEqual(PhotoImportError.map(PhotoImportError.tooLarge), .tooLarge)
        XCTAssertEqual(PhotoImportError.map(URLError(.notConnectedToInternet)), .loadFailed)
    }

    func testMessagesAreUserFacing() {
        let cases: [PhotoImportError] = [.loadFailed, .unsupportedData, .tooLarge, .fileAccessDenied, .cancelled]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("Error Domain"), "no raw NSError text")
        }
    }
}

@MainActor
final class ViewModelTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "CameraGlassProTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testResetFramingUsesPreferences() {
        let defaults = makeDefaults()
        defaults.set(2.0, forKey: SettingsKey.defaultZoom)
        defaults.set(AspectRatioOption.square.rawValue, forKey: SettingsKey.defaultAspect)
        let vm = CameraWorkspaceViewModel(defaults: defaults)
        XCTAssertEqual(vm.zoom, 2)
        XCTAssertEqual(vm.aspect, .square)

        vm.setZoom(4.5)
        vm.aspect = .sixteenNine
        vm.resetFraming()
        XCTAssertEqual(vm.zoom, 2)
        XCTAssertEqual(vm.aspect, .square)
    }

    func testSetZoomClamps() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        vm.setZoom(50)
        XCTAssertEqual(vm.zoom, ZoomLimits.maximum)
        vm.setZoom(0)
        XCTAssertEqual(vm.zoom, ZoomLimits.minimum)
    }

    func testAdjustmentResetAll() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        vm.setAdjustment(.exposure, to: 1.5)
        vm.setNightLook(true)
        XCTAssertTrue(vm.hasEdits)
        vm.resetAllAdjustments()
        XCTAssertFalse(vm.hasEdits)
    }

    func testCenterControlWithoutTimerOpensPicker() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        vm.timer = .off
        vm.primaryAction()
        XCTAssertTrue(vm.showPhotosPicker)
    }
}

@MainActor
final class TopBarTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "TopBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDecodeKeepsPanelOrderAndDropsUnknown() {
        XCTAssertEqual(CameraControl.decode(nil), CameraControl.defaultTopBar)
        XCTAssertEqual(CameraControl.decode("grid,flash,bogus,flash"), [.flash, .grid])
        XCTAssertEqual(CameraControl.decode(""), [])
        XCTAssertEqual(CameraControl.encode([.live, .level]), "live,level")
    }

    func testToggleTopBarPersistsAcrossLaunches() {
        let defaults = makeDefaults()
        let vm = CameraWorkspaceViewModel(defaults: defaults)
        XCTAssertEqual(vm.topBarControls, CameraControl.defaultTopBar)
        vm.toggleTopBar(.grid)
        vm.toggleTopBar(.flash)
        XCTAssertTrue(vm.isInTopBar(.grid))
        XCTAssertFalse(vm.isInTopBar(.flash))

        let relaunched = CameraWorkspaceViewModel(defaults: defaults)
        XCTAssertEqual(relaunched.topBarControls, vm.topBarControls)
    }

    func testTimerAndDepthAppearWhileActive() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        XCTAssertFalse(vm.visibleTopBarControls.contains(.timer))
        vm.perform(.timer)
        XCTAssertTrue(vm.visibleTopBarControls.contains(.timer))
    }

    func testGridLevelAndFormatPersist() {
        let defaults = makeDefaults()
        let vm = CameraWorkspaceViewModel(defaults: defaults)
        XCTAssertEqual(vm.gridStyle, .thirds)
        vm.perform(.grid)
        vm.perform(.level)
        vm.perform(.format)
        let relaunched = CameraWorkspaceViewModel(defaults: defaults)
        XCTAssertEqual(relaunched.gridStyle, .fine)
        XCTAssertTrue(relaunched.showLevel)
        XCTAssertEqual(relaunched.exportFormat, .heic)
    }

    func testExposureFromTopBarOpensPanelSlider() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        vm.perform(.exposure, fromTopBar: true)
        XCTAssertTrue(vm.isControlPanelOpen)
        XCTAssertTrue(vm.isExposureDialVisible)
    }

    func testEveryControlHasPresentation() {
        let vm = CameraWorkspaceViewModel(defaults: makeDefaults())
        for control in CameraControl.allCases {
            XCTAssertFalse(vm.symbol(for: control).isEmpty)
            XCTAssertFalse(vm.hint(for: control).isEmpty)
            XCTAssertFalse(control.title.isEmpty)
        }
    }
}
