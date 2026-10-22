import XCTest

/// Persona audit: large text, imperfect vision, one-handed reach. Runs on the
/// bundled public demo data (`-DuoSeed`), never Supabase or RevenueCat.
@MainActor
final class AccessibilityPersonaUITests: XCTestCase {
    private static let xxxl = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let ax1 = "UICTContentSizeCategoryAccessibilityM"
    private static let standard = "UICTContentSizeCategoryL"

    private func launch(size: String, onboarding: Bool, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-DuoSeed", "-hasCompletedOnboarding", onboarding ? "NO" : "YES",
                                "-UIPreferredContentSizeCategoryName", size] + extra
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Lists every button and link with its frame, flagging targets under 44pt,
    /// controls with no label, and controls in the top third (hard one-handed).
    private func audit(_ app: XCUIApplication, _ name: String) {
        let screen = app.windows.firstMatch.frame
        var lines = ["screen \(Int(screen.width))x\(Int(screen.height))"]
        for kind in [XCUIElement.ElementType.button, .switch, .textField] {
            for el in app.descendants(matching: kind).allElementsBoundByIndex.prefix(30) {
                let f = el.frame
                guard f.width > 0, f.height > 0, f.intersects(screen) else { continue }
                var flags: [String] = []
                if f.height < 44 || f.width < 44 { flags.append("SMALL") }
                if el.label.isEmpty { flags.append("NOLABEL") }
                if f.midY < screen.height / 3 { flags.append("TOPZONE") }
                if f.maxX > screen.maxX + 1 || f.minX < -1 { flags.append("CLIPPED-X") }
                lines.append("\(kind.rawValue) '\(el.label)' id=\(el.identifier) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) \(flags.joined(separator: ","))")
            }
        }
        let att = XCTAttachment(string: lines.joined(separator: "\n"))
        att.name = "audit-\(name)"
        att.lifetime = .keepAlways
        add(att)
    }

    func testOnboardingAtLargestText() {
        let app = launch(size: Self.xxxl, onboarding: true)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 30))
        sleep(2)
        attach("onb1-xxxl")
        audit(app, "onb1-xxxl")
        app.buttons["Continue"].tap()
        sleep(1)
        attach("onb2-xxxl")
        app.buttons["Continue"].tap()
        sleep(2)
        attach("onb3-xxxl")
        audit(app, "onb3-xxxl")
    }

    func testOnboardingStandardText() {
        let app = launch(size: Self.standard, onboarding: true)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 30))
        sleep(2)
        attach("onb1-std")
        audit(app, "onb1-std")
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        sleep(2)
        attach("onb3-std")
        audit(app, "onb3-std")
    }

    func testTabsAtLargestText() {
        let app = launch(size: Self.xxxl, onboarding: false)
        sleep(6)
        attach("stats-xxxl")
        audit(app, "stats-xxxl")
        for tab in ["Trends", "Teams", "Compare"] {
            let b = app.buttons[tab].firstMatch
            if b.waitForExistence(timeout: 5) { b.tap() } else { XCTFail("no tab \(tab)") }
            sleep(3)
            attach("\(tab.lowercased())-xxxl")
            audit(app, "\(tab.lowercased())-xxxl")
        }
    }

    func testTabsAtStandardText() {
        let app = launch(size: Self.standard, onboarding: false)
        sleep(6)
        attach("stats-std")
        audit(app, "stats-std")
        for tab in ["Trends", "Teams", "Compare"] {
            let b = app.buttons[tab].firstMatch
            if b.waitForExistence(timeout: 5) { b.tap() } else { XCTFail("no tab \(tab)") }
            sleep(3)
            attach("\(tab.lowercased())-std")
            audit(app, "\(tab.lowercased())-std")
        }
    }

    func testPlayerProfileAtLargestText() {
        let app = launch(size: Self.xxxl, onboarding: false)
        sleep(6)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Judge'")).firstMatch
        if row.waitForExistence(timeout: 10) { row.tap() } else {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Judge'")).firstMatch.tap()
        }
        sleep(4)
        let later = app.buttons["Maybe later"]
        if later.waitForExistence(timeout: 3) { attach("profile-pitch-xxxl"); later.tap(); sleep(1) }
        attach("profile-1-xxxl")
        audit(app, "profile-1-xxxl")
        for i in 2...4 {
            app.swipeUp()
            sleep(1)
            attach("profile-\(i)-xxxl")
        }
        audit(app, "profile-4-xxxl")
    }

    func testPlayerProfileAtStandardText() {
        let app = launch(size: Self.standard, onboarding: false)
        sleep(6)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Judge'")).firstMatch
        if row.waitForExistence(timeout: 10) { row.tap() } else {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Judge'")).firstMatch.tap()
        }
        sleep(4)
        let later = app.buttons["Maybe later"]
        if later.waitForExistence(timeout: 3) { attach("profile-pitch-std"); later.tap(); sleep(1) }
        attach("profile-1-std")
        audit(app, "profile-1-std")
        app.swipeUp()
        sleep(1)
        attach("profile-2-std")
    }

    func testSettingsAndPaywallAtLargestText() {
        let app = launch(size: Self.xxxl, onboarding: false)
        sleep(6)
        let gear = app.buttons["Settings"].firstMatch
        if gear.waitForExistence(timeout: 10) { gear.tap() }
        sleep(2)
        attach("settings-xxxl")
        audit(app, "settings-xxxl")
        app.swipeUp()
        sleep(1)
        attach("settings-2-xxxl")
        app.swipeUp()
        sleep(1)
        attach("settings-3-xxxl")
    }

    func testPaywallSnapshotAtLargestText() {
        let app = launch(size: Self.xxxl, onboarding: false, extra: ["-PaywallSnapshot", "yearly"])
        sleep(5)
        attach("paywall-xxxl")
        audit(app, "paywall-xxxl")
        app.swipeUp()
        sleep(1)
        attach("paywall-2-xxxl")
        audit(app, "paywall-2-xxxl")
    }

    func testSearchAtLargestText() {
        let app = launch(size: Self.xxxl, onboarding: false)
        sleep(6)
        let search = app.buttons["Search"].firstMatch
        if search.waitForExistence(timeout: 10) { search.tap() }
        sleep(1)
        attach("search-xxxl")
        audit(app, "search-xxxl")
    }
}
