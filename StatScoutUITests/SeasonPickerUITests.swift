import XCTest

@MainActor
final class SeasonPickerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FORCE_PRO"] = "1"
        app.launch()
    }

    private func seasonPicker() -> XCUIElement {
        let picker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Season and season type")
        ).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "Season picker should appear")
        return picker
    }

    func testSeasonPickerShowsCorrectYears() throws {
        let picker = seasonPicker()
        picker.tap()

        XCTAssertTrue(app.buttons["Regular Season"].waitForExistence(timeout: 2), "Regular season should be available")
        let postseasonOption = app.buttons["Postseason"]
        let prePlayoffOption = app.buttons["Postseason (after first playoff game)"]
        XCTAssertTrue(
            postseasonOption.exists || prePlayoffOption.exists,
            "Postseason should be discoverable from the season menu"
        )

        for year in StatScoutSeasonYears.all {
            XCTAssertTrue(app.buttons[year].exists, "Season menu should list \(year)")
        }
    }

    func testSelectDifferentYear() throws {
        let picker = seasonPicker()
        picker.tap()

        let targetYear = "2025"
        let targetButton = app.buttons[targetYear]
        XCTAssertTrue(targetButton.waitForExistence(timeout: 2), "Target season should be listed")
        targetButton.tap()

        let updatedPicker = seasonPicker()
        let accessibilityValue = updatedPicker.value as? String ?? ""
        XCTAssertTrue(
            updatedPicker.label.contains(targetYear)
                || accessibilityValue.contains(targetYear)
                || app.staticTexts[targetYear].exists,
            "Season picker should show the selected season"
        )
    }
}

private enum StatScoutSeasonYears {
    static let all = (2015...2026).map(String.init)
}
