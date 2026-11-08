import UIKit
import XCTest

@MainActor
final class LocalizedStoreScreenshotUITests: XCTestCase {
    struct LocaleCase: Decodable {
        let store, language, region: String
        let seasonPicker, yearCompare, teamFooter, swingLength, versus: String
        let scenes: [Int]
    }

    func testLocalizedStoreScreens() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "StoreScreenshotLocales", withExtension: "json"))
        let locales = try JSONDecoder().decode([LocaleCase].self, from: Data(contentsOf: url))
        let captureCount = locales.reduce(0) { $0 + $1.scenes.count }
        var capturedCount = 0

        for locale in locales {
            for scene in locale.scenes {
                let route = [1: "stats", 2: "player", 3: "trends", 4: "playercompare", 5: "team", 6: "player", 7: "stats"][scene]!
                let app = launch(locale, route: route, scene: scene)

                switch scene {
                case 1:
                    selectSeason(2025, in: app, locale: locale)
                    waitFor("Juan Soto", in: app)
                    let sotoRows = app.staticTexts
                        .matching(NSPredicate(format: "label CONTAINS[c] %@", "Juan Soto"))
                    XCTAssertEqual(sotoRows.count, 1, "The 2025 board should show Juan Soto once")
                case 2:
                    waitFor("Aaron Judge", in: app)
                    XCTAssertTrue(app.buttons[locale.yearCompare].waitForExistence(timeout: 60))
                case 3:
                    waitFor("xwOBA", in: app)
                case 4:
                    waitFor("Aaron Judge", in: app)
                    waitFor("Shohei Ohtani", in: app)
                    waitFor("xwOBA", in: app)
                case 5:
                    selectSeason(2025, in: app, locale: locale)
                    revealTeamFooter(in: app, locale: locale)
                case 6:
                    waitFor("Aaron Judge", in: app)
                    let yearCompare = app.buttons[locale.yearCompare].firstMatch
                    XCTAssertTrue(yearCompare.waitForExistence(timeout: 60))
                    yearCompare.tap()
                    waitFor("2025", in: app)
                case 7:
                    selectSeason(2025, in: app, locale: locale)
                    waitFor("SB", in: app)
                default:
                    XCTFail("Unexpected scene \(scene)")
                }

                sleep(2)
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "\(locale.store)__\(String(format: "%02d", scene))"
                attachment.lifetime = .keepAlways
                add(attachment)
                capturedCount += 1
                if capturedCount < captureCount {
                    app.terminate()
                }
            }
        }
    }

    private func launch(_ locale: LocaleCase, route: String, scene: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FORCE_PRO": "1",
            "SCREENSHOT_MODE": "1",
            "STATSCOUT_FORCE_PRO": "1",
            "TEST_RUNNER_SCREENSHOT_APP_VERSION": "1.2",
        ]
        app.launchArguments = [
            "-AppleLanguages", "(\(locale.language))",
            "-AppleLocale", locale.region,
            "-DuoSeed", "-ScreenshotData", "-StoreScreenshotData", "-DuoTour", "-DuoRoutes", route,
            "-hasCompletedOnboarding", "YES",
        ]
        if scene == 7 { app.launchArguments.append("-StoreScreenshotStandardRunning") }
        app.launch()
        return app
    }

    private func selectSeason(_ season: Int, in app: XCUIApplication, locale: LocaleCase) {
        let picker = app.buttons[locale.seasonPicker]
        XCTAssertTrue(picker.waitForExistence(timeout: 60), "Season picker is missing")
        picker.tap()

        let option = app.buttons.matching(
            NSPredicate(format: "label == %@", String(season))
        ).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 30), "Season \(season) is missing")
        option.tap()
        XCTAssertTrue(app.staticTexts[String(season)].waitForExistence(timeout: 30), "Season \(season) was not selected")
    }

    private func revealTeamFooter(in app: XCUIApplication, locale: LocaleCase) {
        let scrollView = app.scrollViews["team-screen-scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 60), "Team metrics are missing")
        waitFor(locale.swingLength, in: app)
        waitFor(locale.teamFooter, in: app)

        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.84))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        start.press(forDuration: 0.1, thenDragTo: end)

        let metric = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", locale.swingLength)
        ).firstMatch
        let footer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", locale.teamFooter)
        ).firstMatch
        let tabBar = app.descendants(matching: .any)["floating-tab-bar"]
        XCTAssertTrue(metric.waitForExistence(timeout: 30), "Swing Length is missing")
        XCTAssertTrue(footer.waitForExistence(timeout: 30), "The roster weighting note is missing")
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Floating tab bar is missing")
        XCTAssertLessThan(metric.frame.maxY, tabBar.frame.minY, "Swing Length should clear the tab bar")
        XCTAssertLessThan(footer.frame.maxY, tabBar.frame.minY, "The roster weighting note should clear the tab bar")
    }

    private func waitFor(_ text: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[cd] %@ OR value CONTAINS[cd] %@", text, text))
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 90), "Missing \(text)")
    }
}
