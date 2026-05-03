import XCTest

final class YearAuditUITests: XCTestCase {
    var app: XCUIApplication!
    var yearData: [String: [String]] = [:] // year -> list of player names

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAllYearsHaveDifferentData() throws {
        // Wait for initial load
        let leaderboard = app.staticTexts["LEADERBOARD"]
        XCTAssertTrue(leaderboard.waitForExistence(timeout: 15), "Leaderboard should appear")

        let yearsToTest = [2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026]

        for year in yearsToTest {
            print("Testing year: \(year)")

            // Open year picker
            let yearPickerCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.15))
            yearPickerCoord.tap()
            sleep(2)

            // Tap on specific year
            let yearButton = app.buttons[String(year)]
            if yearButton.exists {
                yearButton.tap()
            } else {
                // Try scrolling to find it if not visible
                let scrollArea = app.scrollViews.firstMatch
                if scrollArea.exists {
                    scrollArea.swipeUp()
                    sleep(1)
                    if yearButton.exists {
                        yearButton.tap()
                    } else {
                        XCTFail("Could not find year \(year) in picker")
                        continue
                    }
                } else {
                    // Fallback - tap at approximate location
                    let coord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                    coord.tap()
                }
            }

            sleep(5) // Wait for data to load

            // Take screenshot
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Year_\(year)_Leaderboard"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Capture top 5 player names from leaderboard
            var playerNames: [String] = []
            let tableCells = app.tables.firstMatch.cells

            for i in 1..<min(6, tableCells.count) {
                let cell = tableCells.element(boundBy: i)
                let nameLabels = cell.staticTexts.allElementsBoundByIndex
                if let nameLabel = nameLabels.first {
                    let name = nameLabel.label
                    if !name.isEmpty && name != "LEADERBOARD" {
                        playerNames.append(name)
                    }
                }
            }

            yearData[String(year)] = playerNames
            print("Year \(year) top players: \(playerNames)")

            // Wait before next iteration
            sleep(2)
        }

        // Verify data changed between years
        verifyDataChanges()
    }

    func verifyDataChanges() {
        var allPassed = true

        for year in yearData.keys.sorted() {
            guard let currentYearPlayers = yearData[year] else { continue }

            // Compare with other years
            for otherYear in yearData.keys.sorted() {
                guard otherYear != year else { continue }
                guard let otherYearPlayers = yearData[otherYear] else { continue }

                // Check if data is exactly the same (shouldn't be)
                if currentYearPlayers == otherYearPlayers && !currentYearPlayers.isEmpty {
                    print("ERROR: Year \(year) and \(otherYear) have identical data!")
                    allPassed = false
                }
            }
        }

        // Print summary
        print("\n=== YEAR AUDIT SUMMARY ===")
        for year in yearData.keys.sorted() {
            let players = yearData[year] ?? []
            print("\(year): \(players.count) players captured")
            if players.isEmpty {
                print("  WARNING: No data for \(year)")
            } else {
                print("  Top 3: \(players.prefix(3))")
            }
        }

        XCTAssertTrue(allPassed, "Years should have different data")
    }
}
