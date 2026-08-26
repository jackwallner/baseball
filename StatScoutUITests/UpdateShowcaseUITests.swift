import XCTest

@MainActor
final class UpdateShowcaseUITests: XCTestCase {
    func testUpdateShowcasePagesAndDismissal() throws {
        let app = XCUIApplication()
        app.launchEnvironment["STATSCOUT_FORCE_UPDATE_SHOWCASE"] = "1"
        app.launchEnvironment["FORCE_PRO"] = "1"
        app.launch()

        XCTAssertTrue(app.otherElements["updateShowcase"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Who's hot\nright now."].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "UpdateShowcase"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // SwiftUI's accessibility tree exposes the page action by its visible
        // label while the container identifier is shared by the showcase
        // descendants. Use the user-facing control name so this verifies the
        // interaction a user actually performs.
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 2))
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Any two.\nAny season."].waitForExistence(timeout: 2))

        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Every club.\nEvery angle."].waitForExistence(timeout: 2))

        let finishButton = app.buttons["Start Scouting"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2))
        finishButton.tap()
        XCTAssertFalse(app.otherElements["updateShowcase"].waitForExistence(timeout: 1))
    }
}
