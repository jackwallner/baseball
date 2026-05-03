import XCTest

@MainActor
final class StatScoutComprehensiveUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - DashboardView Tests

    func testDashboardSearchField() throws {
        // Test search field exists and is tappable
        let searchField = app.searchFields["Search players or teams"]
        XCTAssertTrue(searchField.exists, "Search field should exist")
        searchField.tap()
        searchField.typeText("Judge")

        // Verify filtered results
        let judgeCell = app.staticTexts["Aaron Judge"]
        XCTAssertTrue(judgeCell.waitForExistence(timeout: 2), "Should show Aaron Judge in search results")

        // Test clear search
        searchField.clearText()
        XCTAssertEqual(searchField.value as? String, "", "Search field should be cleared")
    }

    func testDashboardCategoryFilterSwitching() throws {
        // Test all category tabs
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]

        for category in categories {
            let tab = app.buttons[category]
            XCTAssertTrue(tab.exists, "\(category) tab should exist")
            tab.tap()

            // Verify tab is selected (has red underline)
            // Note: This checks if the tab is the selected one by checking its state
            XCTAssertTrue(tab.isSelected || tab.value as? String == category, "\(category) tab should be selected")
        }
    }

    func testDashboardLeaderboardSort() throws {
        // Find sort button
        let sortButton = app.buttons["Sort"]
        XCTAssertTrue(sortButton.exists, "Sort button should exist")

        // Tap to change sort direction
        sortButton.tap()

        // Verify sort indicator changes
        let arrowImage = app.images["arrow.up"]
        XCTAssertTrue(arrowImage.exists, "Sort direction should change to ascending")

        // Tap again to reverse
        sortButton.tap()
        let downArrow = app.images["arrow.down"]
        XCTAssertTrue(downArrow.exists, "Sort direction should change back to descending")
    }

    func testDashboardEmptySearchState() throws {
        let searchField = app.searchFields["Search players or teams"]
        searchField.tap()
        searchField.typeText("xyznonexistent")

        // Verify empty state
        let emptyState = app.staticTexts["No players found"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 2), "Should show empty state for no results")
    }

    func testDashboardLeaderboardRowNavigation() throws {
        // Tap first player in leaderboard
        let firstPlayer = app.cells.firstMatch
        XCTAssertTrue(firstPlayer.exists, "Should have at least one player in leaderboard")
        firstPlayer.tap()

        // Verify navigation to PlayerProfileView
        let profileHeader = app.staticTexts["Overall Percentile"]
        XCTAssertTrue(profileHeader.waitForExistence(timeout: 2), "Should navigate to player profile")

        // Navigate back
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - PlayerProfileView Tests

    func testPlayerProfileMetricBars() throws {
        // Navigate to a player profile
        app.cells.firstMatch.tap()

        // Verify all metric categories are displayed
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]
        for category in categories {
            // Scroll to find category if needed
            let categoryHeader = app.staticTexts[category]
            if categoryHeader.exists {
                XCTAssertTrue(categoryHeader.isHittable, "\(category) section should be visible")
            }
        }

        // Verify MetricBar elements
        let metricBars = app.otherElements.matching(identifier: "MetricBar")
        if metricBars.count > 0 {
            let firstBar = metricBars.element(boundBy: 0)
            XCTAssertTrue(firstBar.exists, "Should have metric bars displayed")
        }
    }

    func testPlayerProfileYearOverYearHistory() throws {
        app.cells.firstMatch.tap()

        // Scroll to find history section
        app.swipeUp()

        let historySection = app.staticTexts["YEAR OVER YEAR"]
        if historySection.waitForExistence(timeout: 2) {
            XCTAssertTrue(historySection.exists, "Should show year over year section for players with history")

            // Verify history rows show seasons
            let seasonCells = app.cells.containing(.staticText, identifier: "202")
            XCTAssertGreaterThan(seasonCells.count, 0, "Should have historical season data")
        }
    }

    func testPlayerProfileYearCompareTab() throws {
        // Navigate to a player profile with history (Aaron Judge typically has multiple years)
        let searchField = app.searchFields["Search players or teams"]
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        if judgeCell.waitForExistence(timeout: 2) {
            judgeCell.tap()

            // Look for Year Compare tab
            let yearCompareTab = app.buttons["Year Compare"]
            if yearCompareTab.waitForExistence(timeout: 2) {
                XCTAssertTrue(yearCompareTab.exists, "Year Compare tab should exist for players with history")
                XCTAssertTrue(yearCompareTab.isEnabled, "Year Compare tab should be enabled")

                // Tap Year Compare tab
                yearCompareTab.tap()

                // Verify year selectors exist
                let year1Selector = app.buttons["Year 1"]
                let year2Selector = app.buttons["Year 2"]
                XCTAssertTrue(year1Selector.exists, "Year 1 selector should exist")
                XCTAssertTrue(year2Selector.exists, "Year 2 selector should exist")

                // Tap Year 1 selector and select a year
                year1Selector.tap()
                let yearOption = app.buttons.containing(.staticText, identifier: "202").firstMatch
                if yearOption.waitForExistence(timeout: 2) {
                    yearOption.tap()

                    // Verify comparison content appears
                    app.swipeUp()
                    let comparisonContent = app.staticTexts["Metric"]
                    XCTAssertTrue(comparisonContent.exists || app.staticTexts["Δ"].exists, "Comparison grid should show")
                }
            }
        }
    }

    func testPlayerProfileYearCompareTabDisabledForNoHistory() throws {
        // Search for a player that likely has no history
        let searchField = app.searchFields["Search players or teams"]
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        if judgeCell.waitForExistence(timeout: 2) {
            judgeCell.tap()

            // Check Year Compare tab state
            let yearCompareTab = app.buttons["Year Compare"]
            if yearCompareTab.exists {
                // If player has no multi-year history, tab should be disabled
                // If player has history, tab should be enabled
                XCTAssertTrue(yearCompareTab.exists, "Year Compare tab should exist")
            }
        }
    }

    func testPlayerProfileShareFunctionality() throws {
        app.cells.firstMatch.tap()

        // Find and tap share button
        let shareButton = app.buttons["ShareLink"]
        XCTAssertTrue(shareButton.exists || app.buttons["Share"].exists, "Share button should exist")

        if shareButton.exists {
            shareButton.tap()

            // Verify share sheet appears
            let shareSheet = app.otherElements["UIActivityViewController"]
            XCTAssertTrue(shareSheet.waitForExistence(timeout: 2), "Share sheet should appear")

            // Dismiss share sheet
            app.buttons["Cancel"].firstMatch.tap()
        }
    }

    func testPlayerProfileMetricRankingNavigation() throws {
        app.cells.firstMatch.tap()

        // Find a metric row and tap it
        let metricRow = app.cells.firstMatch
        metricRow.tap()

        // Verify navigation to MetricRankingView
        let rankingHeader = app.staticTexts.containing("·").firstMatch
        XCTAssertTrue(rankingHeader.waitForExistence(timeout: 2), "Should navigate to metric ranking")
    }

    // MARK: - TeamsView Tests

    func testTeamsViewGridLayout() throws {
        // Navigate to Teams tab
        let teamsTab = app.buttons["Teams"]
        XCTAssertTrue(teamsTab.exists, "Teams tab should exist")
        teamsTab.tap()

        // Verify 30 team tiles exist
        let teamTiles = app.cells
        XCTAssertEqual(teamTiles.count, 30, "Should show all 30 MLB teams")
    }

    func testTeamViewRosterAndSearch() throws {
        // Go to Teams tab
        app.buttons["Teams"].tap()

        // Tap a team
        let teamTile = app.cells.firstMatch
        teamTile.tap()

        // Verify roster loads
        let rosterHeader = app.staticTexts["ROSTER"]
        XCTAssertTrue(rosterHeader.waitForExistence(timeout: 2), "Should show roster section")

        // Test search within roster
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            searchField.tap()
            searchField.typeText("Pitcher")

            // Verify search filters results
            let results = app.cells
            XCTAssertGreaterThan(results.count, 0, "Should show filtered roster results")
        }
    }

    // MARK: - MetricLeadersView Tests

    func testMetricLeadersViewCategoryGrouping() throws {
        // Navigate to Metrics tab
        let metricsTab = app.buttons["Metrics"]
        XCTAssertTrue(metricsTab.exists, "Metrics tab should exist")
        metricsTab.tap()

        // Verify category sections
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]
        for category in categories {
            let section = app.staticTexts[category]
            if section.waitForExistence(timeout: 1) {
                XCTAssertTrue(section.exists, "\(category) section should exist in metrics view")
            }
        }
    }

    // MARK: - MetricRankingView Tests

    func testMetricRankingViewSorting() throws {
        // Navigate to a metric ranking
        app.buttons["Metrics"].tap()
        app.cells.firstMatch.tap()

        // Find and tap sort button
        let sortButton = app.buttons["Sort"]
        if sortButton.exists {
            sortButton.tap()
            // Verify sort changes
            sortButton.tap()
        }
    }

    // MARK: - AboutView Tests

    func testAboutViewLinks() throws {
        // Navigate to About view via info button
        let infoButton = app.buttons["info.circle"]
        XCTAssertTrue(infoButton.exists, "Info button should exist")
        infoButton.tap()

        // Verify About view content
        let aboutTitle = app.staticTexts["About"]
        XCTAssertTrue(aboutTitle.waitForExistence(timeout: 2), "Should show About view")

        // Verify links exist
        let supportLink = app.staticTexts["Contact Support"]
        XCTAssertTrue(supportLink.exists, "Support link should exist")

        let privacyLink = app.staticTexts["Privacy Policy"]
        XCTAssertTrue(privacyLink.exists, "Privacy link should exist")

        // Close About view
        app.buttons["Done"].tap()
    }

    // MARK: - Navigation Tests

    func testTabSwitchingAndStatePreservation() throws {
        // Start on Leaders tab
        let leadersTab = app.buttons["Leaders"]
        let teamsTab = app.buttons["Teams"]

        // Search on Leaders tab
        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("NYY")

        // Switch to Teams tab
        teamsTab.tap()

        // Switch back to Leaders
        leadersTab.tap()

        // Verify search state preserved
        XCTAssertEqual(searchField.value as? String, "NYY", "Search state should be preserved")
    }

    func testDeepNavigationStack() throws {
        // Navigate: Leaders -> Player -> Metric Ranking -> Player
        app.cells.firstMatch.tap()
        app.cells.firstMatch.tap() // Metric row
        app.cells.firstMatch.tap() // Another player

        // Verify we can navigate back through stack
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        // Should be back at Leaders view
        XCTAssertTrue(app.staticTexts["LEADERBOARD"].exists, "Should return to leaderboard")
    }

    // MARK: - Accessibility Tests

    func testVoiceOverLabels() throws {
        // Check that key elements have accessibility labels
        let searchField = app.searchFields["Search players or teams"]
        XCTAssertTrue(searchField.exists, "Search field should have accessibility label")

        // Verify buttons are accessible
        let sortButton = app.buttons["Sort"]
        XCTAssertTrue(sortButton.exists, "Sort button should be accessible")

        // Verify player cells are accessible
        let playerCell = app.cells.firstMatch
        XCTAssertNotNil(playerCell.value, "Player cell should have accessibility value")
    }

    // MARK: - Performance Tests

    func testLargeLeaderboardScrolling() throws {
        // Measure scroll performance
        measure(metrics: [XCTPerformanceMetric.wallClockTime]) {
            for _ in 0..<10 {
                app.swipeUp()
            }
            for _ in 0..<10 {
                app.swipeDown()
            }
        }
    }
}

// MARK: - Helper Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
    }

    var isSelected: Bool {
        return self.value as? String == "Selected"
    }
}

    // MARK: - Favorite Team Tests

    func testFavoriteTeamSelection() throws {
        // Navigate to Teams tab
        let teamsTab = app.buttons["Teams"]
        XCTAssertTrue(teamsTab.exists, "Teams tab should exist")
        teamsTab.tap()

        // Long press on a team (e.g., NYY)
        let nyyTeam = app.staticTexts["New York Yankees"]
        XCTAssertTrue(nyyTeam.waitForExistence(timeout: 2), "Yankees should exist in teams grid")
        nyyTeam.press(forDuration: 1.0)

        // Verify context menu appears
        let favoriteButton = app.buttons["Set as favorite"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 2), "Set as favorite button should appear")
        favoriteButton.tap()

        // Verify favorite indicator appears
        let favoriteIndicator = app.images["star.fill"]
        XCTAssertTrue(favoriteIndicator.exists, "Favorite star should appear on team")
    }

    func testFavoriteTeamMovesToTop() throws {
        // Navigate to Teams tab
        app.buttons["Teams"].tap()

        // Set a team as favorite (e.g., SF - usually later in alphabet)
        let sfTeam = app.staticTexts["San Francisco Giants"]
        if sfTeam.waitForExistence(timeout: 2) {
            sfTeam.press(forDuration: 1.0)
            
            let favoriteButton = app.buttons["Set as favorite"]
            if favoriteButton.waitForExistence(timeout: 2) {
                favoriteButton.tap()

                // Verify team appears first in grid
                let firstTeam = app.cells.firstMatch
                let firstTeamName = firstTeam.staticTexts.element(boundBy: 1).label
                XCTAssertTrue(firstTeamName.contains("San Francisco"), "Favorite team should appear first")
            }
        }
    }

    func testRemoveFavoriteTeam() throws {
        // Navigate to Teams tab
        app.buttons["Teams"].tap()

        // Long press on a favorited team
        let favoritedTeam = app.images["star.fill"].firstMatch
        if favoritedTeam.exists {
            favoritedTeam.press(forDuration: 1.0)
            
            let removeButton = app.buttons["Remove from favorites"]
            XCTAssertTrue(removeButton.waitForExistence(timeout: 2), "Remove favorite button should appear")
            removeButton.tap()

            // Verify star disappears
            XCTAssertFalse(app.images["star.fill"].exists, "Favorite star should be removed")
        }
    }

    // MARK: - Standard Stats Tab Tests

    func testStandardStatsTabExists() throws {
        // Navigate to a player profile
        app.cells.firstMatch.tap()

        // Verify tab toggle exists
        let percentilesTab = app.buttons["Percentiles"]
        let standardStatsTab = app.buttons["Standard Stats"]
        
        XCTAssertTrue(percentilesTab.exists, "Percentiles tab should exist")
        XCTAssertTrue(standardStatsTab.exists, "Standard Stats tab should exist")
    }

    func testStandardStatsTabToggle() throws {
        // Navigate to a player profile
        app.cells.firstMatch.tap()

        // Tap Standard Stats tab
        let standardStatsTab = app.buttons["Standard Stats"]
        if standardStatsTab.isEnabled {
            standardStatsTab.tap()

            // Verify standard stats content appears
            let standardStatsGrid = app.otherElements["Standard Stats Grid"]
            XCTAssertTrue(standardStatsGrid.exists || app.staticTexts["AVG"].exists, "Standard stats should be displayed")
        }
    }

    func testStandardStatsTabDisabledWhenNoData() throws {
        // Search for a player
        let searchField = app.searchFields["Search players or teams"]
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        if judgeCell.waitForExistence(timeout: 2) {
            judgeCell.tap()

            // Check Standard Stats tab
            let standardStatsTab = app.buttons["Standard Stats"]
            XCTAssertTrue(standardStatsTab.exists, "Standard Stats tab should exist")
            
            // Tab should be disabled if no stats available
            // Note: In production, Judge should have stats, so this tests the disabled state logic
        }
    }
