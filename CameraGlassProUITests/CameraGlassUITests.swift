import XCTest

/// Drives the real app in the simulator. Screenshots are kept as test attachments; CI exports them and
/// publishes them (release "screenshots") so the layout can be reviewed without a device.
class CameraGlassUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        let bundle = Bundle(for: CameraGlassUITestCase.self)
        let url = try XCTUnwrap(bundle.url(forResource: "sample-landscape", withExtension: "jpg"), "sample photo missing")
        app.launchEnvironment["UITEST_PHOTO_B64"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
        let export = app.buttons["Export photo"]
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: export)
        waitForExpectations(timeout: 30) // the sample photo has loaded
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Lets springs and renders settle before a screenshot.
    func settle(_ seconds: TimeInterval = 1.2) {
        _ = app.wait(for: .runningForeground, timeout: 1)
        Thread.sleep(forTimeInterval: seconds)
    }

    func openPanel(_ page: String) {
        if !app.otherElements["More controls"].exists { app.buttons["More controls"].tap() }
        XCTAssertTrue(app.otherElements["More controls"].waitForExistence(timeout: 5), "controls panel opens")
        app.buttons[page].firstMatch.tap()
    }

    /// Opens a control from the ⠿ panel.
    func open(_ control: String, page: String = "Edit") {
        openPanel(page)
        let button = app.buttons.matching(identifier: control).allElementsBoundByIndex.last ?? app.buttons[control]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(control) control exists")
        button.tap()
    }

    /// Taps the viewfinder well away from any pop-up (the top third of the screen).
    func tapOutside() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    }

    func popUp(_ name: String) -> XCUIElement { app.otherElements[name] }
}

final class ScreenshotTour: CameraGlassUITestCase {
    func testTour() {
        settle(2)
        shot("01-main")

        openPanel("Edit"); settle(); shot("02-panel-edit")
        app.buttons["Camera"].firstMatch.tap(); settle(0.6); shot("03-panel-camera")
        app.buttons["Tools"].firstMatch.tap(); settle(0.6); shot("04-panel-tools")
        tapOutside(); settle(0.6)

        open("Filter"); settle(2.5); shot("05-filters")
        tapOutside(); settle(0.6)

        open("Styles"); settle(); shot("06-styles")
        tapOutside(); settle(0.6)

        open("Fx"); settle()
        for (index, page) in ["Blur", "Blend", "Ghost", "Art", "Light", "Retro", "Pop", "Privacy"].enumerated() {
            let tab = popUp("FX").buttons[page]
            if tab.exists { tab.tap(); settle(0.7); shot(String(format: "07-fx-%02d-%@", index + 1, page.lowercased())) }
        }
        tapOutside(); settle(0.6)

        open("Subject"); settle(2); shot("08-subject-style")
        let sunset = popUp("Subject").buttons["Sunset"]
        if sunset.exists { sunset.tap(); settle(3); shot("09-subject-sky-sunset") }
        for page in ["Adjust", "Create"] {
            let tab = popUp("Subject").buttons[page]
            if tab.exists { tab.tap(); settle(0.8); shot("10-subject-\(page.lowercased())") }
        }
        tapOutside(); settle(0.6)

        open("Adjust"); settle(1.5); shot("11-adjust-light")
        for tab in ["Color", "Detail", "Effects", "Local", "AI"] {
            let segment = app.buttons[tab].firstMatch
            if segment.exists { segment.tap(); settle(0.6); shot("12-adjust-\(tab.lowercased())") }
        }
        app.buttons["Done"].firstMatch.tap(); settle(0.8)

        open("Crop"); settle(1.5); shot("13-crop")
        app.buttons["Cancel"].firstMatch.tap(); settle(0.8)

        open("Remove", page: "Tools"); settle(1.5)
        let canvas = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        canvas.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.38)))
        settle(2.5); shot("14-remove")
        app.buttons["Done"].firstMatch.tap(); settle(0.8)

        app.buttons["Export photo"].tap(); settle(1.2); shot("15-export")
        app.buttons["Done"].firstMatch.tap(); settle(0.8)

        // PANO mode: two modes to the right of PHOTO.
        let mode = app.descendants(matching: .any)["Mode"]
        mode.swipeLeft(); settle(0.8); mode.swipeLeft(); settle(1.2); shot("16-mode-after-two-swipes")
    }
}

final class TapTests: CameraGlassUITestCase {
    /// Tapping outside a pop-up closes it, and the tap doesn't reach the controls underneath.
    func testTapOutsideClosesPopUpsWithoutPressingBehind() {
        for (control, name, page) in [("Filter", "Filters", "Edit"), ("Fx", "FX", "Edit"), ("Subject", "Subject", "Edit"),
                                      ("Styles", "Photographic Styles", "Edit")] {
            open(control, page: page)
            XCTAssertTrue(popUp(name).waitForExistence(timeout: 5), "\(name) opens")
            tapOutside()
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: popUp(name))
            waitForExpectations(timeout: 3)
            XCTAssertFalse(app.otherElements["Photos"].exists, "a tap outside \(name) must not open the photo picker")
        }
    }

    /// Tapping a pop-up's own controls keeps it open.
    func testTapsInsideKeepPopUpOpen() {
        open("Fx")
        let fx = popUp("FX")
        XCTAssertTrue(fx.waitForExistence(timeout: 5))
        for page in ["Light", "Retro", "Blur"] { fx.buttons[page].tap() }
        fx.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertTrue(fx.exists, "FX stays open while using it")
        XCTAssertTrue(fx.buttons["Reset"].exists, "each FX page has its own Reset")
    }

    /// Done closes a pop-up; the main screen's shutter still works afterwards (opens the picker).
    func testDoneClosesAndShutterStillWorks() {
        open("Filter")
        let filters = popUp("Filters")
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        filters.buttons["Done"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: filters)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["Replace"].isHittable, "the shutter is reachable again")
    }

    /// The Remove editor opens from Tools and closes with Done.
    func testRemoveEditorRoundTrip() {
        open("Remove", page: "Tools")
        XCTAssertTrue(app.staticTexts["REMOVE"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Export photo"].waitForExistence(timeout: 5))
    }
}
