import XCTest

final class FocusTalkUITests: XCTestCase {
    @MainActor func app() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-ui-state"]
        app.launch()
        return app
    }

    @MainActor func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func allowNotifications() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 2) {
            springboard.buttons["Allow"].tap()
        }
    }

    @MainActor func testArtifactHomeAndPlanSheetFlow() {
        let app = app()
        capture("01-artifact-home")

        // Check Top Bar
        XCTAssertTrue(app.staticTexts["FocusTalk"].exists)
        XCTAssertTrue(app.buttons["Session and settings"].exists)

        // Check Stage & Readout
        XCTAssertTrue(app.staticTexts["What’s on your plate?"].exists)
        XCTAssertTrue(app.buttons["Play an example"].exists)

        // Check Dock
        XCTAssertTrue(app.buttons["Plan"].exists)
        XCTAssertTrue(app.buttons["Talk"].exists)
        XCTAssertTrue(app.buttons["Start"].exists)
        XCTAssertFalse(app.buttons["Start"].isEnabled)

        // Open Plan Sheet
        app.buttons["Plan"].tap()
        capture("02-plan-sheet-empty")
        XCTAssertTrue(app.staticTexts["Your plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play the example"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Your plan"].waitForNonExistence(timeout: 5))

        // Open More Sheet (Session & Settings)
        let moreBtn = app.buttons["Session and settings"]
        XCTAssertTrue(moreBtn.waitForExistence(timeout: 5))
        moreBtn.tap()
        capture("03-session-and-settings")
        XCTAssertTrue(app.staticTexts["Session and settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Read replies aloud"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Haptics"].exists)
        XCTAssertTrue(app.buttons["Winding"].exists)
        XCTAssertTrue(app.buttons["Ticking"].exists)
        XCTAssertTrue(app.buttons["Alarm"].exists)
        XCTAssertTrue(app.buttons["Timer object Tomato"].exists)
        XCTAssertTrue(app.switches["Start the next block on its own"].exists)
        XCTAssertTrue(app.buttons["Add 5 minutes"].exists)
        XCTAssertTrue(app.buttons["Skip this block"].exists)
        XCTAssertTrue(app.buttons["End session"].exists)
        XCTAssertTrue(app.buttons["Start over"].exists)
        app.buttons["Close settings"].tap()
        XCTAssertTrue(app.staticTexts["Session and settings"].waitForNonExistence(timeout: 5))

        // Tap "Play an example"
        let playExampleBtn = app.buttons["Play an example"]
        XCTAssertTrue(playExampleBtn.waitForExistence(timeout: 5))
        playExampleBtn.tap()
        allowNotifications()
        capture("04-plan-ready")

        XCTAssertTrue(app.staticTexts["Your plan is ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 5))

        // Open Plan Sheet to see generated blocks and timeline
        app.buttons["Plan"].tap()
        capture("05-plan-sheet-timeline")
        XCTAssertTrue(app.staticTexts["Client deck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start session"].exists)

        // Start session from plan sheet
        app.buttons["Start session"].firstMatch.tap()
        allowNotifications()
        capture("06-session-running")

        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Focus block 1 of 5"].waitForExistence(timeout: 5))

        // Pause
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))

        // Resume
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))

        // Open settings and end session
        app.buttons["Session and settings"].tap()
        let endBtn = app.buttons["End session"]
        XCTAssertTrue(endBtn.waitForExistence(timeout: 5))
        endBtn.tap()
        // Tap again to confirm
        let confirmEndBtn = app.buttons["Tap again to end"]
        XCTAssertTrue(confirmEndBtn.waitForExistence(timeout: 3))
        confirmEndBtn.tap()
        app.buttons["Close settings"].tap()
        XCTAssertTrue(app.staticTexts["Session and settings"].waitForNonExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Session done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start over"].exists)
    }

    @MainActor func testTypedInputFallback() {
        let app = app()
        app.buttons["Session and settings"].tap()
        app.buttons["Type instead"].tap()

        let input = app.textFields["Tasks and time available"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Read book for 30 minutes")
        app.buttons["Plan"].firstMatch.tap()
        capture("07-typed-input")
    }

    @MainActor func testManualDialSetsTimer() {
        let app = app()
        let dial = app.otherElements["Tomato timer"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))

        // Drag dial to wind it
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6))
            .press(forDuration: 0.1, thenDragTo: dial.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)))

        allowNotifications()
        capture("08-manual-dial-running")
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    }

    @MainActor func testChoosingAnObjectChangesTheDialAndItsSounds() {
        let app = app()
        app.buttons["Session and settings"].tap()
        let apple = app.buttons["Timer object Apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        XCTAssertTrue(apple.isSelected)
        XCTAssertEqual(app.buttons["Alarm"].value as? String, "Temple blocks")
        XCTAssertEqual(app.buttons["Ticking"].value as? String, "Woodblock")
        capture("10-object-apple")
        app.buttons["Close settings"].tap()
        XCTAssertEqual(app.otherElements["Tomato timer"].label, "Apple timer")

        // Each object can still use any sound: switch ticking off from the menu.
        app.buttons["Session and settings"].tap()
        app.buttons["Ticking"].tap()
        let none = app.buttons["None"]
        XCTAssertTrue(none.waitForExistence(timeout: 5))
        none.tap()
        XCTAssertEqual(app.buttons["Ticking"].value as? String, "None")

        // Put the default back so later tests and screenshots see the tomato.
        app.buttons["Timer object Tomato"].tap()
        app.buttons["Close settings"].tap()
        XCTAssertEqual(app.otherElements["Tomato timer"].label, "Tomato timer")
    }

    @MainActor func testBackgroundDialPresentation() {
        let app = app()
        app.buttons["Play an example"].tap()
        allowNotifications()
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 5))
        app.buttons["Start session"].tap()
        allowNotifications()

        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        capture("09-dynamic-island")

        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.85)))
        capture("10-lock-screen")
        app.activate()
    }

    @MainActor func testSpokenReplyPreferenceSurvivesRelaunch() {
        let app = app()
        app.buttons["Session and settings"].tap()
        let voice = app.switches["Read replies aloud"]
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        XCTAssertEqual(voice.value as? String, "1")
        voice.tap()
        XCTAssertEqual(voice.value as? String, "0")
        app.buttons["Close settings"].tap()
        XCTAssertTrue(app.buttons["Talk"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Session and settings"].tap()
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        XCTAssertEqual(voice.value as? String, "0")
    }

    @MainActor func testTypedStartAcceptsExistingProposal() {
        let app = app()
        app.buttons["Play an example"].tap()
        XCTAssertTrue(app.buttons["Start session"].waitForExistence(timeout: 5))
        app.buttons["Session and settings"].tap()
        app.buttons["Type instead"].tap()
        let input = app.textFields["Tasks and time available"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("start\n")
        allowNotifications()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Client deck"].exists)
    }

    @MainActor func testLargeTextHome() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-ui-state", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Talk"].waitForExistence(timeout: 5))
        capture("11-large-text")
    }
}
