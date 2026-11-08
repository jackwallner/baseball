import XCTest

/// Release gate journeys (see ~/ios/qa/README.md). They assert reachability
/// and the core loop's outcome; `QA.checkpoint` judges every screen.
///
/// Data is the bundled demo slate (`-ScreenshotData`), so no network is needed
/// for players. RevenueCat is the Test Store key in DEBUG builds, never `appl_`.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Onboarding done, update showcase already seen, bundled demo players.
    private let returning = [
        "-ScreenshotData",
        "-hasCompletedOnboarding", "YES",
        "-lastSeenUpdateShowcase", "stats-trends-compare-1.3.1",
    ]

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["STATSCOUT_RESET_TEAM_FAVORITE"] = "1"
    }

    // MARK: - Journeys

    func testFirstRunOnboardingToStats() {
        QA.launch(app, arguments: ["-ScreenshotData", "-hasCompletedOnboarding", "NO"])
        let continueButton = button("Continue", "Weiter")
        XCTAssertTrue(continueButton.waitForExistence(timeout: 30), "Onboarding should open")
        QA.checkpoint(app, "onboarding-first-page")

        var page = 1
        while continueButton.exists, page < 8 {
            continueButton.tap()
            page += 1
            QA.checkpoint(app, "onboarding-page-\(page)")
        }

        let getStarted = button("Get Started", "Loslegen")
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20), "The last onboarding page should offer Get Started")
        QA.checkpoint(app, "onboarding-offer")
        getStarted.tap()

        XCTAssertTrue(button("Search", "Suchen").waitForExistence(timeout: 30), "Stats should open after onboarding")
        QA.checkpoint(app, "stats-first-value")
    }

    func testOnboardingSkipReachesStats() {
        QA.launch(app, arguments: ["-ScreenshotData", "-hasCompletedOnboarding", "NO"])
        let skip = button("Skip", "Überspringen")
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "Onboarding should offer Skip")
        skip.tap()
        XCTAssertTrue(button("Search", "Suchen").waitForExistence(timeout: 30), "Stats should open after Skip")
        QA.checkpoint(app, "stats-after-skip")
    }

    func testPaywallShownAndDismissed() {
        QA.launch(app, arguments: returning)
        let upgrade = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@ OR label ENDSWITH %@", "unlock all features", "alle Funktionen freischalten")).firstMatch
        XCTAssertTrue(upgrade.waitForExistence(timeout: 30), "A free user should see the upgrade button")
        QA.checkpoint(app, "stats-free")
        upgrade.tap()

        let close = button("Close", "Schließen")
        XCTAssertTrue(close.waitForExistence(timeout: 20), "The paywall should open with a Close button")
        QA.checkpoint(app, "paywall")
        close.tap()

        XCTAssertTrue(upgrade.waitForExistence(timeout: 10), "Closing the paywall should return to Stats")
        QA.checkpoint(app, "paywall-dismissed")
    }

    func testReturnVisitAcrossTabs() {
        QA.launch(app, arguments: returning)
        XCTAssertTrue(button("Search", "Suchen").waitForExistence(timeout: 30), "Stats should open")
        QA.checkpoint(app, "stats-return")

        QA.relaunch(app)
        XCTAssertTrue(button("Search", "Suchen").waitForExistence(timeout: 30), "Stats should reopen without onboarding")
        QA.checkpoint(app, "stats-after-relaunch")

        openTab("Trends")
        QA.checkpoint(app, "trends")
        openTab("Teams")
        XCTAssertTrue(app.buttons["team-NYY"].waitForExistence(timeout: 20), "Teams should list clubs")
        QA.checkpoint(app, "teams")
        openTab("Compare", "Vergleichen")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label IN %@", ["YOUR PLAYERS", "DEINE SPIELER"])).firstMatch.waitForExistence(timeout: 20), "Compare should open")
        QA.checkpoint(app, "compare")
    }

    func testInterruptionOnPlayerProfile() {
        QA.launch(app, arguments: returning)
        openProfile("Judge", as: "Aaron Judge")
        QA.checkpoint(app, "profile-before-interrupt")

        QA.interrupt(app)
        XCTAssertEqual(app.state, .runningForeground, "The app should come back to the foreground")
        XCTAssertTrue(profileFollowButton("Aaron Judge").waitForExistence(timeout: 20), "The profile should survive the interruption")
        QA.checkpoint(app, "profile-after-interrupt")
    }

    /// Core loop: find a player, follow them, see them under YOUR PLAYERS on
    /// Compare, and still be following after the app is killed and reopened.
    func testCoreLoopFollowPlayerSurvivesRelaunch() {
        let name = "Aaron Judge"
        QA.launch(app, arguments: returning)
        XCTAssertTrue(button("Search", "Suchen").waitForExistence(timeout: 30), "Stats should open")
        QA.checkpoint(app, "stats")

        openProfile("Judge", as: name)
        // Earlier journeys share this install; start from not following.
        if unfollow(name).exists {
            unfollow(name).tap()
        }
        let follow = button("Follow \(name)", "\(name) folgen")
        XCTAssertTrue(follow.waitForExistence(timeout: 10), "An unfollowed player should offer Follow")
        QA.checkpoint(app, "profile-not-following")

        follow.tap()
        XCTAssertTrue(unfollow(name).waitForExistence(timeout: 10), "Following should flip the button to Unfollow")
        QA.checkpoint(app, "profile-following")

        openTab("Compare", "Vergleichen")
        XCTAssertTrue(followedRow(name).waitForExistence(timeout: 20), "\(name) should be listed under YOUR PLAYERS")
        QA.checkpoint(app, "compare-your-players")

        QA.relaunch(app)
        XCTAssertTrue(button("Search", "Suchen").waitForExistence(timeout: 30), "Stats should reopen after the relaunch")
        openTab("Compare", "Vergleichen")
        XCTAssertTrue(followedRow(name).waitForExistence(timeout: 20), "\(name) should still be followed after a relaunch")
        QA.checkpoint(app, "compare-your-players-after-relaunch")

        openTab("Stats")
        openProfile("Judge", as: name)
        XCTAssertTrue(unfollow(name).waitForExistence(timeout: 10), "The profile should still show Unfollow after a relaunch")
        QA.checkpoint(app, "profile-following-after-relaunch")
    }

    // MARK: - Helpers

    /// The button whose label is the English or the German string.
    private func button(_ english: String, _ german: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", [english, german])).firstMatch
    }

    private func openTab(_ title: String, _ german: String? = nil) {
        let tab = button(title, german ?? title)
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "\(title) tab should exist")
        tab.tap()
    }

    /// Searches Stats for `query`, opens the matching player and clears the
    /// trial pitch that the second profile open of an install raises.
    private func openProfile(_ query: String, as name: String, journey: String = #function) {
        let field = app.textFields["dashboardSearchField"]
        if !field.exists {
            let search = button("Search", "Suchen")
            XCTAssertTrue(search.waitForExistence(timeout: 20), "Stats should offer Search")
            search.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The search field should open")
        field.tap()
        field.typeText(query)

        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Search should find \(name)")
        row.tap()

        // From the second open of an install the trial pitch covers the profile.
        let maybeLater = button("Maybe later", "Vielleicht später")
        if maybeLater.waitForExistence(timeout: 6) {
            QA.checkpoint(app, "trial-pitch", journey: journey)
            maybeLater.tap()
            XCTAssertTrue(maybeLater.waitForNonExistence(timeout: 10), "The trial pitch should dismiss")
        }
        XCTAssertTrue(profileFollowButton(name).waitForExistence(timeout: 20), "\(name)'s profile should open")
        QA.checkpoint(app, "profile", journey: journey)
    }

    private func unfollow(_ name: String) -> XCUIElement {
        button("Unfollow \(name)", "\(name) nicht mehr folgen")
    }

    private func profileFollowButton(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Follow \(name)", "Unfollow \(name)", "\(name) folgen", "\(name) nicht mehr folgen"])).firstMatch
    }

    private func followedRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
}
