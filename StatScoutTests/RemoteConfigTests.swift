import XCTest
@testable import Baseball_Savvy_StatScout

/// The offering-metadata reader and the trial button wording it drives.
final class RemoteConfigTests: XCTestCase {
    private let sevenDay = IntroTrial(unit: .day, count: 7)

    private func arm(_ metadata: [String: Any]?) -> TrialCTA { TrialCTA.from(metadata: metadata) }

    func testMissingNonStringAndUnknownValuesAreControl() {
        XCTAssertEqual(arm(nil), .sevenDay)
        XCTAssertEqual(arm([:]), .sevenDay)
        XCTAssertEqual(arm(["trial_cta": 3]), .sevenDay)
        XCTAssertEqual(arm(["trial_cta": true]), .sevenDay)
        XCTAssertEqual(arm(["trial_cta": "ours"]), .sevenDay)
    }

    func testKnownValuesPickTheirArm() {
        XCTAssertEqual(arm(["trial_cta": "seven_day"]), .sevenDay)
        XCTAssertEqual(arm(["trial_cta": "my"]), .my)
        XCTAssertEqual(arm(["trial_cta": "your"]), .your)
    }

    func testControlIsExactlyTodaysCopy() {
        XCTAssertEqual(TrialCTA.sevenDay.title(.sentence, trial: sevenDay), sevenDay.startLabel)
        XCTAssertEqual(TrialCTA.sevenDay.title(.titleCase, trial: sevenDay), String(localized: "Start Free Trial"))
    }

    func testControlKeepsTheRealTrialLength() {
        let threeDay = IntroTrial(unit: .day, count: 3)
        XCTAssertEqual(TrialCTA.sevenDay.title(.sentence, trial: threeDay), threeDay.startLabel)
    }

    func testEnglishTitlesPerArmAndSurface() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "en")
        XCTAssertEqual(TrialCTA.sevenDay.title(.sentence, trial: sevenDay), "Start 7-day free trial")
        XCTAssertEqual(TrialCTA.sevenDay.title(.titleCase, trial: sevenDay), "Start Free Trial")
        XCTAssertEqual(TrialCTA.my.title(.sentence, trial: sevenDay), "Start my free trial")
        XCTAssertEqual(TrialCTA.my.title(.titleCase, trial: sevenDay), "Start My Free Trial")
        XCTAssertEqual(TrialCTA.your.title(.sentence, trial: sevenDay), "Start your free trial")
        XCTAssertEqual(TrialCTA.your.title(.titleCase, trial: sevenDay), "Start Your Free Trial")
    }

    func testArmsDoNotLeakTheTrialLength() {
        for surface in [TrialCTA.Surface.sentence, .titleCase] {
            XCTAssertFalse(TrialCTA.my.title(surface, trial: sevenDay).contains("7"))
            XCTAssertFalse(TrialCTA.your.title(surface, trial: sevenDay).contains("7"))
        }
    }

    /// An account without a free trial never sees an arm: the callers only
    /// ask for one when the package is eligible, so the plain priced copy is
    /// untouched. Pinned through the copy that branch returns.
    func testIneligibleWordingIsUnchanged() {
        XCTAssertEqual(StoreService.upgradeCTALabel(trialAvailable: false), "Upgrade")
    }

    func testRatingSwitchIsOnByDefaultAndOffOnlyForOff() {
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: nil))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
        XCTAssertFalse(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
    }
}
