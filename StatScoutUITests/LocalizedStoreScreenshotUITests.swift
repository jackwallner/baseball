import UIKit
import XCTest

@MainActor
final class LocalizedStoreScreenshotUITests: XCTestCase {
    struct LocaleCase: Decodable {
        let store: String
        let language: String
        let region: String
        let seasonPicker: String
        let yearCompare: String
        let scenes: [Int]
    }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    func testLocalizedStoreScreens() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "StoreScreenshotLocales", withExtension: "json"))
        let locales = try JSONDecoder().decode([LocaleCase].self, from: Data(contentsOf: url))

        for locale in locales {
            for scene in locale.scenes {
                let route = [1: "stats", 2: "player", 3: "trends", 5: "team", 6: "player", 7: "stats"][scene]!
                let app = launch(locale, route: route, scene: scene)
                waitFor("Aaron Judge", in: app)

                switch scene {
                case 1:
                    selectSeason("2025", locale: locale, in: app)
                case 2:
                    XCTAssertTrue(app.buttons[locale.yearCompare].waitForExistence(timeout: 60))
                case 3:
                    waitFor("xwOBA", in: app)
                case 5:
                    selectSeason("2025", locale: locale, in: app)
                case 6:
                    let yearCompare = app.buttons[locale.yearCompare].firstMatch
                    XCTAssertTrue(yearCompare.waitForExistence(timeout: 60))
                    yearCompare.tap()
                    waitFor("2025", in: app)
                case 7:
                    selectSeason("2025", locale: locale, in: app)
                    waitFor("SB", in: app)
                default:
                    XCTFail("Unexpected scene \(scene)")
                }

                Thread.sleep(forTimeInterval: 2)
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "\(locale.store)__\(String(format: "%02d", scene))"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
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
            "-DuoSeed", "-StoreScreenshotData", "-DuoTour", "-DuoRoutes", route,
            "-hasCompletedOnboarding", "YES",
        ]
        if scene == 7 { app.launchArguments.append("-StoreScreenshotStandardRunning") }
        app.launch()
        return app
    }

    private func selectSeason(_ year: String, locale: LocaleCase, in app: XCUIApplication) {
        let current = app.buttons[locale.seasonPicker].firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 60), "Season selector is missing")
        current.tap()
        tap(year, in: app)
        waitFor(year, in: app)
        Thread.sleep(forTimeInterval: 2)
    }

    private func waitFor(_ text: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[cd] %@ OR value CONTAINS[cd] %@", text, text))
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 90), "Missing \(text)")
    }
}
