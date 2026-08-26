import XCTest

/// Onboarding has to fit the canvas it is given, not the one it was designed on.
///
/// StatScout is an iPhone-only app, so on iPad it runs in the iPhone
/// compatibility window: 375x622pt, about 140pt shorter than the iPhone the
/// flow was laid out for (an iPhone SE is the same shape). At that height the
/// old layout overflowed, and SwiftUI resolves an overflow by truncating each
/// `Text` to one line and clipping the remainder — App Review rejected 1.5.0
/// under guideline 4 for exactly that. Clipped content is not hittable, so
/// "every bullet is hittable" is the assertion that catches the regression.
///
/// Run this against an iPad destination to exercise the compatibility window;
/// on an iPhone destination it guards the same layout on the roomier canvas.
@MainActor
final class CompactLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "NO"]
        app.launch()
    }

    private func assertFullyVisible(_ element: XCUIElement, _ message: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(message) is missing")
        XCTAssertTrue(element.isHittable, "\(message) is clipped or covered")
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(element.frame),
            "\(message) extends outside the window: \(element.frame)"
        )
    }

    func testFirstPageShowsEveryBullet() throws {
        for bullet in [
            "Every qualified player ranked",
            "xwOBA, Barrel%, Sprint Speed, and more",
            "Updated daily, always fresh",
            "No account, no sign-up"
        ] {
            assertFullyVisible(app.staticTexts[bullet], "Page 1 bullet '\(bullet)'")
        }
        assertFullyVisible(app.buttons["Continue"], "Page 1 Continue button")
        assertFullyVisible(app.buttons["Skip"], "Skip button")
    }

    /// The last page is the tightest: it carries four bullets *and* the whole
    /// purchase block (price, disclosure, Terms/Privacy, CTA, Restore). It is
    /// also the page App Review was looking at.
    func testPurchasePageShowsEveryBulletAndTheWholePurchaseBlock() throws {
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Continue should exist on page 1")
        cont.tap()
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should exist on page 2")
        cont.tap()

        for bullet in [
            "The Trends board: the league ranked by who's moving",
            "Last 7 / 15 / 30 day form on any player or team",
            "Head-to-head matchups across every percentile",
            "Every season back to 2015, and year-over-year"
        ] {
            assertFullyVisible(app.staticTexts[bullet], "Purchase page bullet '\(bullet)'")
        }

        // The free-tier exit has to stay reachable next to the paid CTA, and
        // the billed amount has to stay visible above it (3.1.2(c)).
        assertFullyVisible(app.buttons["Get Started"], "Get Started")
        assertFullyVisible(app.buttons["Restore Purchases"], "Restore Purchases")
    }
}
