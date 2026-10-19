import XCTest

@MainActor
final class PlayerShareCardUITests: XCTestCase {
    func testShareButtonOpensShareSheetWithCard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launch()

        let searchButton = app.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 20), "Dashboard should load")
        searchButton.tap()
        let searchField = app.textFields["dashboardSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Judge")

        let judge = app.staticTexts["Aaron Judge"].firstMatch
        XCTAssertTrue(judge.waitForExistence(timeout: 20), "Search should find the player")
        judge.tap()

        let share = app.buttons["sharePlayerCard"]
        XCTAssertTrue(share.waitForExistence(timeout: 20), "Profile should offer a share button")
        // A free user's first profile opens under the trial pitch.
        let maybeLater = app.buttons["Maybe later"]
        if maybeLater.waitForExistence(timeout: 5) {
            maybeLater.tap()
            sleep(1)
        }
        attach("profile")
        share.tap()

        // The share sheet's header carries the rendered card as its preview.
        let sheet = app.otherElements["ActivityListView"].firstMatch
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10) || copy.waitForExistence(timeout: 5), "Share sheet should appear")
        sleep(2)
        attach("share-sheet")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
