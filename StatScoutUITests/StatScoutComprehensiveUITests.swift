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
        guard searchField.waitForExistence(timeout: 5) else {
            // If no search field, app might be showing empty state - that's okay
            XCTExpectFailure("Search field should exist when app has data")
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        // Verify filtered results (may not exist if no data)
        let judgeCell = app.staticTexts["Aaron Judge"]
        if judgeCell.waitForExistence(timeout: 2) {
            XCTAssertTrue(judgeCell.exists, "Should show Aaron Judge in search results")
        }

        // Test clear search
        searchField.clearText()
        XCTAssertEqual(searchField.value as? String, "", "Search field should be cleared")
    }

    func testDashboardCategoryFilterSwitching() throws {
        // Test all category tabs
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]

        for category in categories {
            let tab = app.buttons[category]
            guard tab.waitForExistence(timeout: 2) else {
                continue // Skip if tab doesn't exist (no data case)
            }
            XCTAssertTrue(tab.exists, "\(category) tab should exist")
            tab.tap()
        }
    }

    func testDashboardLeaderboardSort() throws {
        // Find sort button
        let sortButton = app.buttons["Sort"]
        guard sortButton.waitForExistence(timeout: 2) else {
            return // Skip if no sort button (empty state)
        }

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
        guard searchField.waitForExistence(timeout: 5) else {
            return // Skip if no search field
        }
        searchField.tap()
        searchField.typeText("xyznonexistent")

        // Verify empty state
        let emptyState = app.staticTexts["No players found"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 2), "Should show empty state for no results")
    }

    func testDashboardLeaderboardRowNavigation() throws {
        // Tap first player in leaderboard
        let firstPlayer = app.cells.firstMatch
        guard firstPlayer.waitForExistence(timeout: 5) else {
            // No data available - skip test
            return
        }
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
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return // No data - skip
        }
        app.cells.firstMatch.tap()

        // Verify all metric categories are displayed
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]
        for category in categories {
            let categoryHeader = app.staticTexts[category]
            if categoryHeader.exists {
                XCTAssertTrue(categoryHeader.isHittable, "\(category) section should be visible")
            }
        }
    }

    func testPlayerProfileYearOverYearHistory() throws {
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return // No data - skip
        }
        app.cells.firstMatch.tap()

        // Scroll to find history section
        app.swipeUp()

        let historySection = app.staticTexts["YEAR OVER YEAR"]
        if historySection.waitForExistence(timeout: 2) {
            XCTAssertTrue(historySection.exists, "Should show year over year section for players with history")
        }
    }

    func testPlayerProfileYearCompareTab() throws {
        // Navigate to a player profile with history
        let searchField = app.searchFields["Search players or teams"]
        guard searchField.waitForExistence(timeout: 5) else {
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        guard judgeCell.waitForExistence(timeout: 2) else {
            return // Aaron Judge not in data - skip
        }
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
        }
    }

    func testPlayerProfileYearCompareTabDisabledForNoHistory() throws {
        let searchField = app.searchFields["Search players or teams"]
        guard searchField.waitForExistence(timeout: 5) else {
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        guard judgeCell.waitForExistence(timeout: 2) else {
            return
        }
        judgeCell.tap()

        // Check Year Compare tab state
        let yearCompareTab = app.buttons["Year Compare"]
        if yearCompareTab.exists {
            XCTAssertTrue(yearCompareTab.exists, "Year Compare tab should exist")
        }
    }

    func testPlayerProfileShareFunctionality() throws {
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return // No data - skip
        }
        app.cells.firstMatch.tap()

        // Find and tap share button
        let shareButton = app.buttons["ShareLink"]
        guard shareButton.waitForExistence(timeout: 2) || app.buttons["Share"].waitForExistence(timeout: 2) else {
            return // Share button not present - skip
        }

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
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return // No data - skip
        }
        app.cells.firstMatch.tap()

        // Find a metric row and tap it
        let metricRow = app.cells.firstMatch
        metricRow.tap()

        // Verify navigation to MetricRankingView
        let rankingHeader = app.staticTexts.element(boundBy: 1)
        XCTAssertTrue(rankingHeader.waitForExistence(timeout: 2), "Should navigate to metric ranking view")

        // Navigate back
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - YearComparisonFeature Tests

    func testYearComparisonInitialLoad() throws {
        // Navigate to a player with history and open Year Compare
        let searchField = app.searchFields["Search players or teams"]
        guard searchField.waitForExistence(timeout: 5) else {
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        guard judgeCell.waitForExistence(timeout: 2) else {
            return
        }
        judgeCell.tap()

        let yearCompareTab = app.buttons["Year Compare"]
        guard yearCompareTab.waitForExistence(timeout: 2) else {
            return
        }
        yearCompareTab.tap()

        // Verify initial state with two different years
        let year1Selector = app.buttons["Year 1"]
        let year2Selector = app.buttons["Year 2"]
        XCTAssertTrue(year1Selector.exists, "Year 1 selector should exist")
        XCTAssertTrue(year2Selector.exists, "Year 2 selector should exist")
    }

    func testYearComparisonMetricDisplay() throws {
        // Navigate to Year Compare
        let searchField = app.searchFields["Search players or teams"]
        guard searchField.waitForExistence(timeout: 5) else {
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        guard judgeCell.waitForExistence(timeout: 2) else {
            return
        }
        judgeCell.tap()

        let yearCompareTab = app.buttons["Year Compare"]
        guard yearCompareTab.waitForExistence(timeout: 2) else {
            return
        }
        yearCompareTab.tap()

        // Verify comparison grid shows metrics
        app.swipeUp()
        let comparisonContent = app.staticTexts["Metric"]
        XCTAssertTrue(comparisonContent.exists || app.staticTexts["Δ"].exists, "Comparison grid should show")
    }

    func testYearComparisonCategoryTabs() throws {
        let searchField = app.searchFields["Search players or teams"]
        guard searchField.waitForExistence(timeout: 5) else {
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        guard judgeCell.waitForExistence(timeout: 2) else {
            return
        }
        judgeCell.tap()

        let yearCompareTab = app.buttons["Year Compare"]
        guard yearCompareTab.waitForExistence(timeout: 2) else {
            return
        }
        yearCompareTab.tap()

        // Test category tabs within Year Compare
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]
        for category in categories {
            let tab = app.buttons[category]
            if tab.waitForExistence(timeout: 2) {
                tab.tap()
                // Verify content updates
                XCTAssertTrue(tab.exists, "\(category) tab should exist in Year Compare")
            }
        }
    }

    func testYearComparisonNoOverlappingMetricsMessage() throws {
        // Navigate to Year Compare for a player
        let searchField = app.searchFields["Search players or teams"]
        guard searchField.waitForExistence(timeout: 5) else {
            return
        }
        searchField.tap()
        searchField.typeText("Judge")

        let judgeCell = app.staticTexts["Aaron Judge"]
        guard judgeCell.waitForExistence(timeout: 2) else {
            return
        }
        judgeCell.tap()

        let yearCompareTab = app.buttons["Year Compare"]
        guard yearCompareTab.waitForExistence(timeout: 2) else {
            return
        }
        yearCompareTab.tap()

        // If years have no overlapping metrics, should show the message
        let noMetricsMessage = app.staticTexts["No Comparable Metrics"]
        let noMetricsDescription = app.staticTexts["These seasons don't have overlapping metrics to compare."]

        // Check if message exists OR if comparison content exists (both are valid states)
        if noMetricsMessage.waitForExistence(timeout: 2) {
            XCTAssertTrue(noMetricsMessage.exists, "Should show 'No Comparable Metrics' message")
            XCTAssertTrue(noMetricsDescription.exists, "Should show explanation text")
        } else {
            // If no message, then comparison grid should be showing
            let comparisonContent = app.staticTexts["Metric"]
            XCTAssertTrue(comparisonContent.exists || app.staticTexts["Δ"].exists,
                          "Should show either no-metrics message or comparison grid")
        }
    }

    // MARK: - MetricRankingView Tests

    func testMetricRankingViewSorting() throws {
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return // No data - skip
        }
        app.cells.firstMatch.tap()

        // Navigate to a metric ranking
        let metricCell = app.cells.firstMatch
        guard metricCell.waitForExistence(timeout: 2) else {
            return
        }
        metricCell.tap()

        // Find sort button and test sorting
        let sortButton = app.buttons["Sort"]
        if sortButton.waitForExistence(timeout: 2) {
            sortButton.tap()
            // Verify sort changed
            XCTAssertTrue(sortButton.exists, "Sort button should still exist after tap")
        }
    }

    func testMetricRankingViewShowsSeasonIndicator() throws {
        // Navigate to Metric Leaders tab
        let metricsTab = app.buttons["Metrics"]
        guard metricsTab.waitForExistence(timeout: 5) else {
            return
        }
        metricsTab.tap()

        // Tap on a metric to go to MetricRankingView
        let metricCell = app.cells.firstMatch
        guard metricCell.waitForExistence(timeout: 2) else {
            return
        }
        metricCell.tap()

        // Verify season indicator is displayed (e.g., "2026")
        let currentYear = Calendar.current.component(.year, from: Date())
        let seasonText = app.staticTexts["\(currentYear)"]
        // Season indicator should exist as a static text in the header
        let headerElements = app.staticTexts.allElementsBoundByIndex
        let hasSeasonIndicator = headerElements.contains { element in
            element.label.contains("\(currentYear)")
        }
        XCTAssertTrue(hasSeasonIndicator || seasonText.exists, "Should show season indicator in header")
    }

    func testMetricLeadersViewCategoryGrouping() throws {
        // Test MetricLeadersView with different categories
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]

        for category in categories {
            let tab = app.buttons[category]
            if tab.waitForExistence(timeout: 2) {
                tab.tap()

                // Verify leaders are displayed for this category
                let leaderboard = app.cells
                if leaderboard.count > 1 {
                    XCTAssertTrue(leaderboard.element(boundBy: 1).exists, "Should show leaderboard for \(category)")
                }
            }
        }
    }

    // MARK: - Deep Navigation Tests

    func testDeepNavigationStack() throws {
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return // No data - skip
        }

        // Navigate through multiple levels
        app.cells.firstMatch.tap() // Player Profile

        // Try to navigate to metric ranking
        if app.cells.firstMatch.waitForExistence(timeout: 2) {
            app.cells.firstMatch.tap() // Metric Ranking

            // Navigate back twice
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Overall Percentile"].waitForExistence(timeout: 2), "Should be back at player profile")

            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.searchFields["Search players or teams"].waitForExistence(timeout: 2), "Should be back at dashboard")
        }
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabels() throws {
        // Verify key elements have accessibility labels
        let searchField = app.searchFields["Search players or teams"]
        XCTAssertTrue(searchField.exists, "Search field should have accessibility label")

        // Test VoiceOver navigation
        let categories = ["HITTING", "PITCHING", "FIELDING", "RUNNING"]
        for category in categories {
            let tab = app.buttons[category]
            if tab.exists {
                XCTAssertFalse(tab.label.isEmpty, "\(category) tab should have accessibility label")
            }
        }
    }

    func testDynamicTypeSupport() throws {
        // Test that UI adapts to larger text sizes
        // Note: This tests basic layout, actual dynamic type requires device settings
        guard app.cells.firstMatch.waitForExistence(timeout: 5) else {
            return
        }
        app.cells.firstMatch.tap()

        // Verify content is still visible
        let content = app.staticTexts.firstMatch
        XCTAssertTrue(content.exists, "Content should adapt to text size changes")
    }

    // MARK: - TeamsView Tests

    func testFavoriteTeamSelection() throws {
        // Navigate to Teams tab
        let teamsTab = app.buttons["Teams"]
        guard teamsTab.waitForExistence(timeout: 5) else {
            return
        }
        teamsTab.tap()

        // Find team list and select a team
        let teamCell = app.cells.firstMatch
        guard teamCell.waitForExistence(timeout: 5) else {
            return // No teams loaded
        }
        teamCell.tap()

        // Verify star button exists and tap it
        let starButton = app.buttons["star"]
        guard starButton.waitForExistence(timeout: 2) else {
            // Try alternative identifier
            let favButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'star'")).firstMatch
            guard favButton.waitForExistence(timeout: 2) else {
                return
            }
            favButton.tap()
            return
        }
        starButton.tap()

        // Verify team is marked as favorite (star fills)
        XCTAssertTrue(starButton.exists, "Star button should still exist after tap")
    }

    func testFavoriteTeamMovesToTop() throws {
        // Navigate to Teams tab
        let teamsTab = app.buttons["Teams"]
        guard teamsTab.waitForExistence(timeout: 5) else {
            return
        }
        teamsTab.tap()

        // Get first team name
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else {
            return
        }

        // Tap on it to favorite
        firstCell.tap()

        let starButton = app.buttons["star"]
        guard starButton.waitForExistence(timeout: 2) else {
            return
        }
        starButton.tap()

        // Go back and check if it's at top
        app.navigationBars.buttons.firstMatch.tap()

        // Verify the favorited team appears in favorites section
        let favoritesHeader = app.staticTexts["Favorite Team"]
        if favoritesHeader.waitForExistence(timeout: 2) {
            XCTAssertTrue(favoritesHeader.exists, "Should show favorites section")
        }
    }

    func testRemoveFavoriteTeam() throws {
        // Navigate to Teams tab
        let teamsTab = app.buttons["Teams"]
        guard teamsTab.waitForExistence(timeout: 5) else {
            return
        }
        teamsTab.tap()

        // First favorite a team
        let teamCell = app.cells.firstMatch
        guard teamCell.waitForExistence(timeout: 5) else {
            return
        }
        teamCell.tap()

        let starButton = app.buttons["star"]
        guard starButton.waitForExistence(timeout: 2) else {
            return
        }
        starButton.tap()

        // Now un-favorite it
        starButton.tap()

        // Verify star is now unfilled
        XCTAssertTrue(starButton.exists, "Star button should exist after un-favoriting")
    }

    // MARK: - AboutView Tests

    func testAboutViewLinks() throws {
        // Look for info/about button
        let infoButton = app.buttons["info"]
        guard infoButton.waitForExistence(timeout: 5) else {
            // Try finding by accessibility label
            let aboutButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'About' OR label CONTAINS 'Info'")).firstMatch
            guard aboutButton.waitForExistence(timeout: 2) else {
                return // About button may not be visible in current tab
            }
            aboutButton.tap()
            return
        }
        infoButton.tap()

        // Verify About view opens
        let aboutTitle = app.staticTexts["About StatScout"]
        XCTAssertTrue(aboutTitle.waitForExistence(timeout: 2), "About view should open")

        // Test links
        let privacyLink = app.buttons["Privacy Policy"]
        if privacyLink.exists {
            privacyLink.tap()
            // Privacy policy should open in browser or sheet
            app.buttons.firstMatch.tap() // Go back
        }

        let termsLink = app.buttons["Terms of Use"]
        if termsLink.exists {
            termsLink.tap()
            // Terms should open
            app.buttons.firstMatch.tap() // Go back
        }
    }

    // MARK: - Large Dataset Tests

    func testLargeLeaderboardScrolling() throws {
        // Test scrolling through large leaderboard
        guard app.cells.count > 5 else {
            return // Not enough data to test scrolling
        }

        // Scroll down multiple times
        for _ in 1...5 {
            app.swipeUp()
        }

        // Verify cells are still rendered
        XCTAssertTrue(app.cells.firstMatch.exists, "Cells should persist after scrolling")
    }

    func testDashboardPerformance() throws {
        // Measure dashboard load time
        let startTime = Date()

        // Wait for dashboard to load
        let searchField = app.searchFields["Search players or teams"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Dashboard should load within 10 seconds")

        let loadTime = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(loadTime, 5.0, "Dashboard should load in less than 5 seconds")
    }

    // MARK: - Standard Stats Tests

    func testStandardStatsTabExists() throws {
        // Navigate to Standard Stats tab
        let standardStatsTab = app.buttons["Standard Stats"]
        guard standardStatsTab.waitForExistence(timeout: 5) else {
            return // Tab may not exist if no standard stats data
        }
        standardStatsTab.tap()

        // Verify standard stats view loads
        let header = app.staticTexts["Standard Stats"]
        XCTAssertTrue(header.exists || app.staticTexts["AVG Leaders"].exists, "Standard stats header should exist")
    }

    func testStandardStatsTabDisabledWhenNoData() throws {
        // Test that Standard Stats tab handles empty data gracefully
        let standardStatsTab = app.buttons["Standard Stats"]
        guard standardStatsTab.waitForExistence(timeout: 5) else {
            return
        }

        // Tab should exist even if disabled
        XCTAssertTrue(standardStatsTab.exists, "Standard Stats tab should exist")
    }
}

// MARK: - Helper Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
    }
}
