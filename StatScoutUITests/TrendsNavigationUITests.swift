import XCTest

@MainActor
final class TrendsNavigationUITests: XCTestCase {
    func testPlayerRowOpensProfile() {
        let app = XCUIApplication()
        app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1"
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-lastSeenUpdateShowcase", "stats-trends-compare-1.3.1",
        ]
        app.launch()

        let trendsTab = app.buttons["Trends"]
        XCTAssertTrue(trendsTab.waitForExistence(timeout: 15))
        trendsTab.tap()

        let playerRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "trend-player-")
        ).firstMatch
        XCTAssertTrue(playerRow.waitForExistence(timeout: 40), "A Trends player row should load")
        let playerName = playerRow.label
            .split(separator: ",")
            .dropFirst()
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(playerName.isEmpty, "The Trends row should identify its player")
        playerRow.tap()

        XCTAssertTrue(
            app.navigationBars[playerName].waitForExistence(timeout: 10),
            "Tapping a Trends row should open that player's profile"
        )
    }
}
