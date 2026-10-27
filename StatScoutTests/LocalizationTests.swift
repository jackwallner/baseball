import XCTest
@testable import Baseball_Savvy_StatScout

final class LocalizationTests: XCTestCase {
    func testEnglishOrdinals() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "en")
        XCTAssertEqual(1.ordinal, "1st")
        XCTAssertEqual(11.ordinal, "11th")
        XCTAssertEqual(22.ordinal, "22nd")
        XCTAssertEqual(94.ordinal, "94th")
    }

    func testMetricNamesFallBackToTheFeedLabel() {
        XCTAssertEqual(MetricName.localized("Some Future Metric"), "Some Future Metric")
        XCTAssertFalse(MetricName.localized("Sprint Speed").isEmpty)
    }
}
