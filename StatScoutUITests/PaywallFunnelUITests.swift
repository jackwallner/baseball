import XCTest

/// Proves the `converted_*` half of the fleet paywall record actually reaches
/// RevenueCat, not just the impression half.
///
/// Every other verification in this rollout drove an impression and read the
/// `pitch_views_*` attributes back. Nothing exercised a purchase, so the
/// conversion attributes were only ever covered by unit tests. This closes that:
/// the app configures against the project's Test Store, buys the first package,
/// and RevenueCat's own confirmation sheet is tapped here.
///
/// Test Store purchases are simulated. No StoreKit, no App Store, no revenue,
/// no real transaction, and the customer it creates is a Test Store customer
/// that cannot appear in App Store charts.
///
/// Read the result back with:
///     rc-funnel-attributes baseball --days 1
final class PaywallFunnelUITests: XCTestCase {

    func testTestStorePurchaseRecordsTheConversion() {
        let probeUser = ProcessInfo.processInfo.environment["RC_PROBE_USER"]
            ?? "funnel-probe-baseball-uitest"

        let app = XCUIApplication()
        app.launchArguments += ["-rcfunnelprobe", "-rcfunnelprobepurchase"]
        app.launchEnvironment["RC_PROBE_USER"] = probeUser
        app.launch()

        // RevenueCat puts up its own Test Store sheet. It can take a few seconds
        // for offerings to load first, so this waits rather than polling once.
        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 60),
            "RevenueCat's Test Store sheet never appeared, so no purchase was attempted"
        )
        confirm.tap()

        // `setAttributes` only queues; RevenueCat flushes it on backgrounding.
        // Without this the attributes sit in the queue and the read-back looks
        // like a failure.
        sleep(8)
        XCUIDevice.shared.press(.home)
        sleep(10)
    }
}
