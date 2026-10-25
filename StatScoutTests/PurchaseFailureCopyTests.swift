import XCTest
import RevenueCat
@testable import Baseball_Savvy_StatScout

/// Copy shown when a purchase does not complete.
///
/// App Review rejected 1.5.0 under 2.1(b) for "an error message after we
/// attempted to make a purchase". Two things produced one: a cancelled sheet
/// was reported as a red error, and a genuine failure borrowed whatever string
/// happened to be sitting in `StoreService.lastError`, which is set by product
/// loading and by customer-info refreshes as well. The mapping below is what
/// replaced that, so it is worth pinning: `purchase` is unreachable in the
/// simulator (RevenueCat is never configured there), and this is the only part
/// of the failure path an automated run can actually reach.
final class PurchaseFailureCopyTests: XCTestCase {
    private func message(for code: ErrorCode) -> String {
        let error = NSError(domain: ErrorCode.errorDomain, code: code.rawValue)
        return StoreService.purchaseFailureMessage(for: error)
    }

    func testNetworkFailureNamesTheConnection() {
        XCTAssertTrue(message(for: .networkError).contains("connection"))
    }

    func testStoreOutageIsToldApart() {
        XCTAssertNotEqual(message(for: .storeProblemError), message(for: .networkError))
    }

    func testRestrictionsPointAtScreenTime() {
        XCTAssertTrue(message(for: .purchaseNotAllowedError).contains("Screen Time"))
    }

    func testUnknownFailureStillGetsAnActionableLine() {
        let message = StoreService.purchaseFailureMessage(
            for: NSError(domain: "SomeOtherDomain", code: 42)
        )
        XCTAssertEqual(message, "Couldn't complete the purchase. Please try again.")
    }

    /// The message has to stand on its own: it is rendered inline, under the
    /// button, with no title and no alert around it.
    func testEveryMessageIsASentence() {
        let codes: [ErrorCode] = [
            .networkError, .offlineConnectionError, .storeProblemError,
            .purchaseNotAllowedError, .purchaseInvalidError,
            .productNotAvailableForPurchaseError, .ineligibleError
        ]
        for code in codes {
            let text = message(for: code)
            XCTAssertFalse(text.isEmpty, "\(code) has no copy")
            XCTAssertTrue(text.hasSuffix("."), "\(code) copy is not a sentence: \(text)")
        }
    }
}

final class PendingUnlockActionTests: XCTestCase {
    func testEntitlementWaitsForOfferDismissalBeforeOpeningAnotherSheet() {
        var pending = PendingUnlockAction()
        var openedPicker = false
        pending.set { openedPicker = true }

        pending.resume(isPro: true)
        XCTAssertFalse(openedPicker)
        pending.dismiss(isPro: true, purchasePending: false)
        XCTAssertTrue(openedPicker)
    }

    func testChosenSeasonResumesOnlyAfterEntitlementAndOnlyOnce() {
        var pending = PendingUnlockAction()
        var selectedSeason = 2026
        var resumes = 0
        pending.set { selectedSeason = 2023; resumes += 1 }

        pending.resume(isPro: false)
        XCTAssertEqual(selectedSeason, 2026)
        pending.dismiss(isPro: true, purchasePending: false)
        pending.resume(isPro: true)
        XCTAssertEqual(selectedSeason, 2023)
        XCTAssertEqual(resumes, 1)
    }

    func testDismissalWithoutPurchaseDoesNotResumeOnALaterUpgrade() {
        var pending = PendingUnlockAction()
        var openedComparison = false
        pending.set { openedComparison = true }

        pending.dismiss(isPro: false, purchasePending: false)
        pending.resume(isPro: true)
        XCTAssertFalse(openedComparison)
    }

    func testPendingApprovalRetainsTheComparisonAfterDismissal() {
        var pending = PendingUnlockAction()
        var openedComparison = 0
        pending.set { openedComparison += 1 }

        pending.dismiss(isPro: false, purchasePending: true)
        pending.resume(isPro: false)
        XCTAssertEqual(openedComparison, 0)
        pending.resume(isPro: true)
        pending.resume(isPro: true)
        XCTAssertEqual(openedComparison, 1)
    }

    @MainActor
    func testBothModeIsPreservedRatherThanDefaultingToRecent() {
        var pending = PendingUnlockAction()
        var mode = PlayerProfileView.FormDisplayMode.season
        pending.set { mode = .both }

        pending.dismiss(isPro: true, purchasePending: false)
        XCTAssertEqual(mode, .both)
    }

    func testLatestLockedActionReplacesEarlierRequest() {
        var pending = PendingUnlockAction()
        var selectedSeason = 2026
        pending.set { selectedSeason = 2024 }
        pending.set { selectedSeason = 2022 }

        pending.dismiss(isPro: true, purchasePending: false)
        XCTAssertEqual(selectedSeason, 2022)
    }
}
