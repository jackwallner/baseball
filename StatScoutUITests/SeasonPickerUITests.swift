import XCTest

final class SeasonPickerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testSeasonPickerShowsCorrectYears() throws {
        // Wait for app to load data
        let leaderboard = app.staticTexts["LEADERBOARD"]
        XCTAssertTrue(leaderboard.waitForExistence(timeout: 10), "Leaderboard should appear")

        // Find the year picker (should show current year like "2026")
        let currentYear = Calendar.current.component(.year, from: Date())
        let yearButton = app.buttons.containing(.staticText, identifier: String(currentYear)).firstMatch

        // If not found by text, try finding by partial match
        let yearPicker = app.buttons.element(boundBy: 0) // First button in nav area

        // Take screenshot of initial state
        let screenshot1 = XCUIScreen.main.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "01_Initial_State"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // Tap the year picker to open menu
        if yearButton.exists {
            yearButton.tap()
        } else {
            // Try tapping at coordinates where year picker should be
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.15))
            coordinate.tap()
        }

        // Wait for menu to open
        sleep(2)

        // Take screenshot of menu open
        let screenshot2 = XCUIScreen.main.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "02_Menu_Open"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // Verify year format - check for years in menu
        // Years should be 2015-2026 range
        var foundYears: [String] = []
        for year in 2015...2026 {
            let yearString = String(year)
            if app.buttons[yearString].exists || app.staticTexts[yearString].exists {
                foundYears.append(yearString)
            }
        }

        print("Found years: \(foundYears)")
        XCTAssertGreaterThan(foundYears.count, 0, "Should find at least one year in the picker")

        // Check for comma in year format (should NOT have comma)
        let commaYearPattern = app.staticTexts.containing(NSPredicate(format: "label CONTAINS ','"))
        XCTAssertEqual(commaYearPattern.count, 0, "Year format should not contain comma")
    }

    func testSelectDifferentYear() throws {
        // Wait for data to load
        sleep(5)

        // Take initial screenshot
        let screenshot1 = XCUIScreen.main.screenshot()
        let attachment1 = XCTAttachment(screenshot: screenshot1)
        attachment1.name = "03_Before_Year_Change"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // Tap year picker
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.15))
        coordinate.tap()
        sleep(2)

        // Try to select 2024
        let year2024Button = app.buttons["2024"]
        if year2024Button.exists {
            year2024Button.tap()
        } else {
            // Tap at approximate location of 2024 in menu
            let menuCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            menuCoordinate.tap()
        }

        sleep(3)

        // Take screenshot after year change
        let screenshot2 = XCUIScreen.main.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.name = "04_After_Year_Change"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // Verify app didn't crash and still shows leaderboard
        XCTAssertTrue(app.staticTexts["LEADERBOARD"].exists, "Leaderboard should still exist after year change")
    }
}
