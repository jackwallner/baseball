import XCTest
@testable import Baseball_Savvy_StatScout

/// The upgrade CTA copy.
///
/// This exists because the trial branch is otherwise unreachable in any
/// automated run: `StoreService.configureIfNeeded()` refuses to configure
/// RevenueCat under `targetEnvironment(simulator)`, so `yearlyPackage` is nil
/// in every simulator launch and a `.storekit` configuration can't change it.
/// Before the label was split into a pure function, "Try Free" could only be
/// confirmed by installing on a physical device and looking at it.
final class UpgradeCTATests: XCTestCase {
    func testSaysTryFreeWhenATrialIsAvailable() {
        XCTAssertEqual(StoreService.upgradeCTALabel(trialAvailable: true), "Try Free")
    }

    func testFallsBackToUpgradeWithoutATrial() {
        XCTAssertEqual(StoreService.upgradeCTALabel(trialAvailable: false), "Upgrade")
    }

    /// The point of the shared label: the toolbar pill, the Settings button and
    /// the leaderboard footer previously said "Try Free", "Upgrade" and "Unlock
    /// StatScout+" for the same destination. They now all read this one
    /// function, so a change to the copy can't drift between them again.
    func testOneLabelForEveryEntryPoint() {
        for trialAvailable in [true, false] {
            let label = StoreService.upgradeCTALabel(trialAvailable: trialAvailable)
            XCTAssertFalse(label.isEmpty)
            // Terse enough for the nav-bar pill, which is the tightest of the
            // three slots and the first place an over-long label would clip.
            XCTAssertLessThanOrEqual(label.count, 12, "\(label) is too long for the toolbar pill")
        }
    }
}
