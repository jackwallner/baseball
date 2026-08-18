import XCTest
@testable import Baseball_Savvy_StatScout

final class StretchRunTests: XCTestCase {
    /// Comfortably inside the window, so a window change breaks the window
    /// tests rather than silently rewriting every other test's premise.
    private let inWindow = StretchRunCampaign.starts.addingTimeInterval(60 * 60 * 24 * 7)

    private func decide(
        now: Date? = nil,
        hasCompletedOnboarding: Bool = true,
        seenCampaign: String = "",
        customerStateResolved: Bool = true,
        isPro: Bool = false,
        forcePresentation: Bool = false
    ) -> StretchRunDecision {
        StretchRunCampaign.decision(
            now: now ?? inWindow,
            hasCompletedOnboarding: hasCompletedOnboarding,
            seenCampaign: seenCampaign,
            customerStateResolved: customerStateResolved,
            isPro: isPro,
            forcePresentation: forcePresentation
        )
    }

    // MARK: - Window

    func testHiddenBeforeWindowOpens() {
        let decision = decide(now: StretchRunCampaign.starts.addingTimeInterval(-1))
        XCTAssertFalse(decision.shouldPresent)
    }

    func testVisibleAtTheInstantTheWindowOpens() {
        let decision = decide(now: StretchRunCampaign.starts)
        XCTAssertEqual(decision.creative, .upgrade)
    }

    func testVisibleInsideTheWindow() {
        XCTAssertEqual(decide().creative, .upgrade)
    }

    func testVisibleAtTheFinalSecondOfTheWindow() {
        let decision = decide(now: StretchRunCampaign.ends)
        XCTAssertEqual(decision.creative, .upgrade)
    }

    func testHiddenAfterWindowCloses() {
        let decision = decide(now: StretchRunCampaign.ends.addingTimeInterval(1))
        XCTAssertFalse(decision.shouldPresent)
    }

    func testHiddenNextSeason() {
        let decision = decide(now: StretchRunCampaign.starts.addingTimeInterval(60 * 60 * 24 * 365))
        XCTAssertFalse(decision.shouldPresent)
    }

    /// The campaign closes at 11:59:59 p.m. Pacific on September 30, 2026,
    /// which is the 2026-10-01T06:59:59Z instant the strategy doc fixed on.
    func testWindowClosesAtTheDocumentedUTCInstant() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expected = utc.date(from: DateComponents(
            year: 2026, month: 10, day: 1, hour: 6, minute: 59, second: 59
        ))
        XCTAssertEqual(StretchRunCampaign.ends, expected)
    }

    func testWindowOpensBeforeItCloses() {
        XCTAssertLessThan(StretchRunCampaign.starts, StretchRunCampaign.ends)
    }

    // MARK: - Customer state

    func testHiddenUntilCustomerStateIsKnown() {
        // `isPro` defaults to false, so rendering on an unresolved state would
        // show an upgrade pitch to a paying subscriber for one frame.
        let decision = decide(customerStateResolved: false, isPro: false)
        XCTAssertFalse(decision.shouldPresent)
    }

    func testSubscriberSeesTheProCreativeNotAnOffer() {
        XCTAssertEqual(decide(isPro: true).creative, .pro)
    }

    func testFreeUserSeesTheUpgradeCreative() {
        XCTAssertEqual(decide(isPro: false).creative, .upgrade)
    }

    // MARK: - Onboarding and dismissal

    func testHiddenDuringOnboarding() {
        XCTAssertFalse(decide(hasCompletedOnboarding: false).shouldPresent)
    }

    /// Unlike the update showcase, onboarding does not burn the campaign: a
    /// brand new user is exactly who this card is for.
    func testOnboardingDoesNotMarkTheCampaignSeen() {
        XCTAssertFalse(decide(hasCompletedOnboarding: false).shouldPresent)
        XCTAssertEqual(decide(hasCompletedOnboarding: true).creative, .upgrade)
    }

    func testDismissalHidesItForGood() {
        let decision = decide(seenCampaign: StretchRunCampaign.identifier)
        XCTAssertFalse(decision.shouldPresent)
    }

    func testAnUnrelatedStoredIdentifierDoesNotHideIt() {
        let decision = decide(seenCampaign: UpdateShowcaseCampaign.identifier)
        XCTAssertEqual(decision.creative, .upgrade)
    }

    // MARK: - Debug override

    func testForceBypassesWindowAndDismissal() {
        let decision = decide(
            now: StretchRunCampaign.ends.addingTimeInterval(60 * 60 * 24 * 30),
            hasCompletedOnboarding: false,
            seenCampaign: StretchRunCampaign.identifier,
            customerStateResolved: false,
            forcePresentation: true
        )
        XCTAssertEqual(decision.creative, .upgrade)
    }

    func testForceStillRespectsSubscriberState() {
        let decision = decide(isPro: true, forcePresentation: true)
        XCTAssertEqual(decision.creative, .pro)
    }

    func testForceIsOffByDefault() {
        // Nothing sets the env var in a plain test run, so a shipped build
        // can't be talked into showing the card outside its window.
        XCTAssertFalse(StretchRunCampaign.isForced)
    }

    // MARK: - Campaign identity

    func testCampaignIdentifierIsDistinctFromTheUpdateShowcase() {
        XCTAssertNotEqual(StretchRunCampaign.identifier, UpdateShowcaseCampaign.identifier)
        XCTAssertNotEqual(StretchRunCampaign.storageKey, UpdateShowcaseCampaign.storageKey)
    }

    // MARK: - Paywall trigger

    func testSeasonalTriggerHasItsOwnImpressionID() {
        XCTAssertEqual(PaywallTrigger.stretchRun.paywallImpressionId, "statscout_paywall_stretch_run")
    }

    func testSeasonalTriggerImpressionIDIsUnique() {
        let triggers: [PaywallTrigger] = [
            .pastSeason, .lockedSeason(2024), .yearCompare, .playerComparison,
            .onboarding, .activation, .upgrade, .pastSeasonsLoad, .teamView,
            .winback, .playerScouting, .recentForm, .bestWorst, .stretchRun
        ]
        let ids = triggers.map(\.paywallImpressionId)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testSeasonalTriggerSellsTheProductNotAPrice() {
        // The offer-code campaign this replaced would have put a price in the
        // pitch. Nothing here may quote one: prices are storefront-local and
        // only StoreKit knows them.
        let copy = PaywallTrigger.stretchRun.title + " " + PaywallTrigger.stretchRun.subtitle
        XCTAssertFalse(copy.contains("$"))
        XCTAssertFalse(copy.lowercased().contains("off"))
        XCTAssertFalse(copy.lowercased().contains("discount"))
        XCTAssertFalse(copy.lowercased().contains("sale"))
    }

    func testSeasonalTriggerMakesNoTeamOrLeagueClaim() {
        // The app has no standings feed, so nothing may imply one.
        let copy = (PaywallTrigger.stretchRun.title + " " + PaywallTrigger.stretchRun.subtitle).lowercased()
        for banned in ["mlb", "playoff odds", "games back", "clinch", "wild card"] {
            XCTAssertFalse(copy.contains(banned), "seasonal copy must not claim \(banned)")
        }
    }
}
