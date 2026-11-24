import XCTest
@testable import Baseball_Savvy_StatScout

/// Gates on the system rating prompt. The tracker persists to
/// `UserDefaults.standard`, so each test snapshots and restores it to leave
/// the simulator install where it was.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private var saved: (Int, Date?, Date?, ReviewPromptOutcome?)!

    override func setUp() async throws {
        saved = (
            ReviewPromptTracker.appLaunchCount,
            ReviewPromptTracker.firstAppOpenDate,
            ReviewPromptTracker.lastShownDate,
            ReviewPromptTracker.outcome
        )
        ReviewPromptTracker.outcome = nil
        ReviewPromptTracker.lastShownDate = nil
    }

    override func tearDown() async throws {
        ReviewPromptTracker.appLaunchCount = saved.0
        ReviewPromptTracker.firstAppOpenDate = saved.1
        ReviewPromptTracker.lastShownDate = saved.2
        ReviewPromptTracker.outcome = saved.3
    }

    func testAsksFromTheSecondLaunch() {
        ReviewPromptTracker.appLaunchCount = 2
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testNeverAsksInTheFirstSession() {
        ReviewPromptTracker.appLaunchCount = 1
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testRequiresFinishedOnboarding() {
        ReviewPromptTracker.appLaunchCount = 9
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: false))
    }

    func testWaitsOutTheCooldown() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-29 * 86_400)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-31 * 86_400)
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testOpeningTheReviewPageEndsTheAsks() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.markOpenedWriteReview()
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-400 * 86_400)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testSendingFeedbackStillLeavesARatingAsk() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.markFeedbackSent()
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testFeedbackAfterWriteReviewKeepsTheStop() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.markOpenedWriteReview()
        ReviewPromptTracker.markFeedbackSent()
        XCTAssertEqual(ReviewPromptTracker.outcome, .openedWriteReview)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    /// The call stamps the cooldown, so a second moment right after is blocked.
    func testTheCallStampsTheCooldown() {
        ReviewPromptTracker.appLaunchCount = 9
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testFollowingAsksButUnfollowingDoesNot() {
        XCTAssertTrue(ReviewMoment.followFinished(nowFollowing: true))
        XCTAssertFalse(ReviewMoment.followFinished(nowFollowing: false))
    }

    func testOnlyAMemberBuildingAMatchupAsks() {
        XCTAssertTrue(ReviewMoment.comparisonBuilt(isPro: true, changedMatchup: true))
        XCTAssertFalse(ReviewMoment.comparisonBuilt(isPro: false, changedMatchup: true))
        XCTAssertFalse(ReviewMoment.comparisonBuilt(isPro: true, changedMatchup: false))
    }

    func testAStampFromAFutureClockDoesNotHoldTheCooldownShut() {
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(90 * 86_400)
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }
}
