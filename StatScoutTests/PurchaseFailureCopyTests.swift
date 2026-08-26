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
