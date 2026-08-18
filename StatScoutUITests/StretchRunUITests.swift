import XCTest

/// Drives the real app to the seasonal card, both variants, and captures each
/// one. The decision logic is covered by unit tests; what this adds is proof
/// that the card actually renders in the board's scroll content, that its
/// buttons are hittable, and that the subscriber variant never shows an
/// upgrade pitch.
@MainActor
final class StretchRunUITests: XCTestCase {

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// `STATSCOUT_FORCE_STRETCH_RUN` bypasses the compiled window and the
    /// resolved-customer-state gate, so this test stays honest after the
    /// campaign expires in October.
    private func launched(pro: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STATSCOUT_FORCE_STRETCH_RUN"] = "1"
        if pro { app.launchEnvironment["FORCE_PRO"] = "1" }
        app.launch()

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

    /// The card only renders once the board has rows, so wait for one.
    private func waitForBoard(_ app: XCUIApplication) {
        let playerRow = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+,.*")
        ).firstMatch
        _ = playerRow.waitForExistence(timeout: 60)
    }

    func testFreeUserSeesTheSeasonalCard() throws {
        let app = launched(pro: false)
        waitForBoard(app)

        let cta = app.buttons["SCOUT THE STRETCH RUN"]
        XCTAssertTrue(cta.waitForExistence(timeout: 20), "Seasonal card should render for a free user")
        XCTAssertTrue(app.buttons["Not now"].exists, "Seasonal card should be dismissible")
        XCTAssertFalse(app.buttons["OPEN TRENDS"].exists, "A free user must not get the subscriber variant")
        save(app, "01-stretch-run-free")

        // The CTA opens the ordinary contextual pitch, whose own button buys the
        // yearly plan in place. No offer code, no second paywall.
        cta.tap()
        XCTAssertTrue(
            app.staticTexts["Scout the Stretch Run"].waitForExistence(timeout: 10),
            "CTA should open the seasonal pitch sheet"
        )
        save(app, "02-stretch-run-sheet")

        // Nothing in the pitch may quote a price or a discount.
        XCTAssertFalse(app.staticTexts["LIMITED-TIME FIRST-YEAR OFFER"].exists)
        XCTAssertFalse(app.buttons["Claim the offer"].exists)
    }

    func testSubscriberSeesTheBenefitVariant() throws {
        let app = launched(pro: true)
        waitForBoard(app)

        let trends = app.buttons["OPEN TRENDS"]
        XCTAssertTrue(trends.waitForExistence(timeout: 20), "Subscriber should get the benefit variant")
        XCTAssertFalse(
            app.buttons["SCOUT THE STRETCH RUN"].exists,
            "A subscriber must never be shown the upgrade pitch"
        )
        save(app, "03-stretch-run-pro")

        trends.tap()
        // Landing on Trends is the whole point of the subscriber variant.
        XCTAssertTrue(
            app.buttons["Trends"].firstMatch.waitForExistence(timeout: 10),
            "OPEN TRENDS should land on the Trends tab"
        )
        save(app, "04-stretch-run-trends")
    }
}
