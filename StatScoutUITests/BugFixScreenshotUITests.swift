import XCTest

/// Drives the live app (Pro forced on) through the screens this pass changed and
/// writes a PNG per screen, so the layouts can actually be looked at rather than
/// reasoned about. Not an assertion suite; it exists to produce the images.
@MainActor
final class BugFixScreenshotUITests: XCTestCase {

    /// Attachments rather than a file write: the runner is sandboxed inside the
    /// simulator, so a path on the host is simply not writable from here. They
    /// come back out of the result bundle with `xcresulttool`.
    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FORCE_PRO"] = "1"
        app.launch()

        // Onboarding, then the what's-new showcase, both of which sit over the
        // tab bar and would swallow every tap below.
        let skip = app.buttons["Skip"]
        let getStarted = app.buttons["Get Started"]
        let startScouting = app.buttons["Start Scouting"]
        _ = skip.waitForExistence(timeout: 10)
            || getStarted.waitForExistence(timeout: 1)
            || startScouting.waitForExistence(timeout: 1)
        for _ in 0..<8 {
            if skip.exists { skip.tap(); continue }
            if getStarted.exists { getStarted.tap(); continue }
            if startScouting.exists { startScouting.tap(); continue }
            break
        }
        return app
    }

    func testCaptureChangedScreens() throws {
        let app = launched()

        // Wait for live data before touching anything.
        let playerRow = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+,.*")
        ).firstMatch
        _ = playerRow.waitForExistence(timeout: 60)
        save(app, "01-stats")

        // Trends: qualifier chip on the control row, coverage date in the caption.
        app.buttons["Trends"].firstMatch.tap()
        sleep(8)
        save(app, "02-trends")

        // Teams → a club, whose cards now stack their pickers. Matched by name
        // rather than "first button in the scroll view", which is the category
        // tab strip and isn't hittable.
        app.buttons["Teams"].firstMatch.tap()
        sleep(5)
        // Rows carry the club's full name as their accessibility label.
        let teamRow = app.buttons["Seattle Mariners"].firstMatch
        if teamRow.waitForExistence(timeout: 25) {
            teamRow.tap()
            sleep(4)
            save(app, "03-team-advanced")

            if app.buttons["Roster"].firstMatch.waitForExistence(timeout: 10) {
                app.buttons["Roster"].firstMatch.tap()
                sleep(2)
                save(app, "04-team-roster-season")

                if app.buttons["Recent"].firstMatch.exists {
                    app.buttons["Recent"].firstMatch.tap()
                    sleep(8)
                    save(app, "05-team-roster-recent")
                }
                if app.buttons["Filters"].firstMatch.exists {
                    app.buttons["Filters"].firstMatch.tap()
                    sleep(2)
                    save(app, "06-roster-filters-menu")
                    app.tap()
                }
            }
        }

        // Compare: the new Team vs Team card.
        app.buttons["Compare"].firstMatch.tap()
        sleep(3)
        save(app, "07-compare")
    }
}
