import XCTest
@testable import Baseball_Savvy_StatScout

final class UpdateShowcaseTests: XCTestCase {
    func testExistingUserSeesUnseenCampaign() {
        let decision = UpdateShowcaseCampaign.decision(
            hasCompletedOnboarding: true,
            seenCampaign: ""
        )

        XCTAssertTrue(decision.shouldPresent)
        XCTAssertFalse(decision.shouldMarkSeen)
    }

    func testFreshInstallSkipsCampaignAndMarksItSeen() {
        let decision = UpdateShowcaseCampaign.decision(
            hasCompletedOnboarding: false,
            seenCampaign: ""
        )

        XCTAssertFalse(decision.shouldPresent)
        XCTAssertTrue(decision.shouldMarkSeen)
    }

    func testSeenCampaignDoesNotPresentAgain() {
        let decision = UpdateShowcaseCampaign.decision(
            hasCompletedOnboarding: true,
            seenCampaign: UpdateShowcaseCampaign.identifier
        )

        XCTAssertFalse(decision.shouldPresent)
        XCTAssertFalse(decision.shouldMarkSeen)
    }

    func testDebugOverrideForcesPresentation() {
        let decision = UpdateShowcaseCampaign.decision(
            hasCompletedOnboarding: false,
            seenCampaign: UpdateShowcaseCampaign.identifier,
            forcePresentation: true
        )

        XCTAssertTrue(decision.shouldPresent)
        XCTAssertFalse(decision.shouldMarkSeen)
    }
}
