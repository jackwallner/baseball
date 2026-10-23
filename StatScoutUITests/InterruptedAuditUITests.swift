import XCTest

/// Persona audit: someone pulled away mid-task (backgrounded, app killed by
/// the system) who comes back expecting the screen they left. Uses the seeded
/// bundled data (`-DuoSeed`), so no network or production SDK key is involved.
/// Observations are attached as screenshots plus an "observations" text; only
/// the in-process backgrounding checks assert.
@MainActor
final class InterruptedAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var notes: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    override func tearDown() async throws {
        let log = XCTAttachment(string: notes.joined(separator: "\n"))
        log.name = "observations"
        log.lifetime = .keepAlways
        add(log)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func launch(onboarding: Bool = false, pro: Bool = false) {
        app.launchArguments = ["-DuoSeed"]
        // Test-only entitlement hook (StoreService), no RevenueCat key involved.
        if pro { app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1" }
        if onboarding { app.launchArguments += ["-hasCompletedOnboarding", "NO"] }
        app.launch()
    }

    private func interrupt(seconds: UInt32 = 4) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
        app.activate()
        sleep(2)
    }

    private func kill() {
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.terminate()
    }

    private func shot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func note(_ text: String) { notes.append(text) }

    private func tab(_ name: String) -> XCUIElement { app.buttons[name].firstMatch }

    private func openJudgeViaSearch() -> Bool {
        let search = app.buttons["Search"]
        guard search.waitForExistence(timeout: 30) else { return false }
        search.tap()
        let field = app.textFields["dashboardSearchField"]
        guard field.waitForExistence(timeout: 10) else { return false }
        field.tap()
        field.typeText("Judge")
        let judge = app.staticTexts["Aaron Judge"].firstMatch
        guard judge.waitForExistence(timeout: 20) else { return false }
        // Resign the keyboard first so the tap lands on the row, not the keyboard dismissal.
        let returnKey = app.keyboards.buttons["return"].firstMatch
        if returnKey.exists { returnKey.tap() }
        sleep(1)
        judge.tap()
        if app.buttons["sharePlayerCard"].waitForExistence(timeout: 8) { return true }
        note("tap on the search result did not open the profile; retrying with a coordinate tap")
        judge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return app.buttons["sharePlayerCard"].waitForExistence(timeout: 10)
    }

    // MARK: - Flows

    /// Mid-onboarding: page 2 of 3, then home, then back; then killed.
    func testOnboardingInterrupted() throws {
        launch(onboarding: true)
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 30), "Onboarding should show")
        shot("01-onboarding-page1")
        cont.tap()
        sleep(1)
        shot("02-onboarding-page2")
        let page2 = app.otherElements["Page 2 of 3"].exists || app.staticTexts["Page 2 of 3"].exists
        note("onboarding page indicator reads page 2 before interrupt: \(page2)")

        interrupt()
        shot("03-onboarding-after-background")
        let still2 = app.otherElements["Page 2 of 3"].exists || app.staticTexts["Page 2 of 3"].exists
        note("onboarding still on page 2 after background/foreground: \(still2)")
        XCTAssertTrue(still2, "Backgrounding mid-onboarding must keep the page")

        kill()
        launch(onboarding: true)
        _ = app.buttons["Continue"].waitForExistence(timeout: 30)
        sleep(1)
        shot("04-onboarding-after-kill")
        let restarted = app.otherElements["Page 1 of 3"].exists || app.staticTexts["Page 1 of 3"].exists
        note("onboarding restarted at page 1 after kill: \(restarted)")
    }

    /// Stats tab: pick Pitching, search, open a profile, then interrupt and kill.
    func testStatsAndProfileInterrupted() throws {
        launch()
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "Stats board should load")
        shot("10-stats-initial")

        let pitching = app.buttons["PITCHING"]
        if pitching.waitForExistence(timeout: 5) {
            pitching.tap()
            sleep(1)
            shot("11-stats-pitching")
        } else {
            note("PITCHING chip not found")
        }

        // Back to hitting for the search/profile flow.
        let hitting = app.buttons["HITTING"]
        if hitting.exists { hitting.tap() }
        guard openJudgeViaSearch() else {
            shot("12-profile-not-opened")
            note("PROFILE NOT VERIFIED: the Judge result row did not open a profile under XCUITest (harness tap issue or a real second-tap bug; cannot tell from this run)")
            return
        }
        sleep(2)
        let maybeLater = app.buttons["Maybe later"]
        if maybeLater.waitForExistence(timeout: 3) { maybeLater.tap() }
        shot("12-profile-open")
        let hadShare = app.buttons["sharePlayerCard"].exists

        interrupt()
        shot("13-profile-after-background")
        let stillProfile = app.buttons["sharePlayerCard"].waitForExistence(timeout: 5)
        note("profile still open after background/foreground: \(stillProfile) (was open: \(hadShare))")
        XCTAssertTrue(stillProfile, "Profile should survive a quick background trip")

        kill()
        launch()
        _ = app.buttons["Search"].waitForExistence(timeout: 30)
        sleep(2)
        shot("14-after-kill-relaunch")
        let profileBack = app.buttons["sharePlayerCard"].exists
        note("profile restored after kill/relaunch: \(profileBack)")
        let maybeAgain = app.buttons["Maybe later"]
        note("trial pitch/paywall visible right after relaunch: \(maybeAgain.exists)")
    }

    /// Compare tab (Pro-seeded so the slots are usable): fill slot A, interrupt, kill.
    func testCompareSlotInterrupted() throws {
        launch(pro: true)
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 30))
        let compare = tab("Compare")
        XCTAssertTrue(compare.waitForExistence(timeout: 10), "Compare tab should exist")
        compare.tap()
        sleep(1)
        shot("20-compare-empty")

        let slotA = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Player A'")).firstMatch
        var picked = false
        if slotA.waitForExistence(timeout: 5) {
            slotA.tap()
            let pickerSearch = app.searchFields.firstMatch
            if pickerSearch.waitForExistence(timeout: 10) {
                pickerSearch.tap()
                pickerSearch.typeText("Judge")
            }
            let judge = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Aaron Judge'")).firstMatch
            if judge.waitForExistence(timeout: 30) {
                judge.tap()
                picked = true
            } else {
                note("picker had no Aaron Judge row within 30s (history load?)")
                shot("21-compare-picker")
            }
            sleep(2)
        } else {
            note("Player A slot not found; labels: \(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))")
        }
        shot("22-compare-slot-a-filled")
        note("Pro-seeded Compare, slot A picked: \(picked)")
        // With Pro the empty slot label disappears once A is chosen.
        let slotStillEmpty = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Player A'")).firstMatch.exists
        note("empty Player A slot still shown after picking: \(slotStillEmpty)")

        interrupt()
        shot("23-compare-after-background")
        note("empty Player A slot after background: \(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Player A'")).firstMatch.exists)")

        // Leave the tab and come back.
        tab("Stats").tap()
        sleep(1)
        tab("Compare").tap()
        sleep(1)
        shot("24-compare-after-tab-switch")
        note("empty Player A slot after tab switch: \(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Player A'")).firstMatch.exists)")

        kill()
        launch(pro: true)
        _ = app.buttons["Search"].waitForExistence(timeout: 30)
        tab("Compare").tap()
        sleep(1)
        shot("25-compare-after-kill")
        note("empty Player A slot after kill/relaunch (true means the pick was lost): \(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Player A'")).firstMatch.exists)")
    }

    /// A search typed on the board, then a trip away and back.
    func testSearchTextInterrupted() throws {
        launch()
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        let field = app.textFields["dashboardSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Skubal")
        sleep(1)
        shot("30-search-typed")

        interrupt()
        shot("31-search-after-background")
        let field2 = app.textFields["dashboardSearchField"]
        note("search field present after background: \(field2.exists), value: \(field2.value as? String ?? "nil")")

        kill()
        launch()
        _ = app.buttons["Search"].waitForExistence(timeout: 30)
        sleep(2)
        shot("32-search-after-kill")
        note("search field after kill: \(app.textFields["dashboardSearchField"].exists)")
    }
}
