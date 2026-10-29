import XCTest
@testable import Baseball_Savvy_StatScout

final class LocalizationTests: XCTestCase {
    private let shippedLanguages = ["es", "fr", "it", "ja", "pt-BR", "zh-Hant", "ko", "zh-Hans", "de"]

    func testEveryLocalizationIsCompiledIntoTheAppBundle() {
        let bundles = [Bundle.main] + Bundle.allBundles
        for language in shippedLanguages {
            let localizedBundle = bundles.compactMap { bundle -> Bundle? in
                guard let path = bundle.path(forResource: language, ofType: "lproj") else { return nil }
                return Bundle(path: path)
            }.first
            XCTAssertNotNil(localizedBundle, "Missing compiled \(language).lproj")
        }
    }

    func testNewLanguagesTranslateCoreLabels() throws {
        let expected: [(String, String, String)] = [
            ("de", "Compare", "Vergleichen"),
            ("ko", "Compare", "비교"),
            ("zh-Hans", "Compare", "对比"),
        ]
        let bundles = [Bundle.main] + Bundle.allBundles
        for (language, key, translation) in expected {
            let bundle = try XCTUnwrap(bundles.compactMap { host -> Bundle? in
                guard let path = host.path(forResource: language, ofType: "lproj") else { return nil }
                return Bundle(path: path)
            }.first)
            XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), translation)
        }
    }

    func testEnglishOrdinals() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "en")
        XCTAssertEqual(1.ordinal, "1st")
        XCTAssertEqual(11.ordinal, "11th")
        XCTAssertEqual(22.ordinal, "22nd")
        XCTAssertEqual(94.ordinal, "94th")
    }

    func testOneDayTrialUsesSingularCopy() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "en")
        let trial = IntroTrial(unit: .day, count: 1)
        XCTAssertEqual(trial.label, "1-day free trial")
        XCTAssertEqual(trial.startLabel, "Start 1-day free trial")
        XCTAssertEqual(trial.thenSentence(price: "$4.99"), "1-day free trial, then $4.99.")
        let path = try XCTUnwrap(([Bundle.main] + Bundle.allBundles).compactMap {
            $0.path(forResource: "de", ofType: "lproj")
        }.first)
        let german = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(german.localizedString(forKey: "1-day free trial", value: nil, table: nil), "1 Tag gratis testen")
    }

    func testMetricNamesFallBackToTheFeedLabel() {
        XCTAssertEqual(MetricName.localized("Some Future Metric"), "Some Future Metric")
        XCTAssertFalse(MetricName.localized("Sprint Speed").isEmpty)
    }

    func testRosterCountUsesLocalePluralRules() throws {
        let path = try XCTUnwrap(([Bundle.main] + Bundle.allBundles).compactMap {
            $0.path(forResource: "es", ofType: "lproj")
        }.first)
        let bundle = try XCTUnwrap(Bundle(path: path))
        let locale = Locale(identifier: "es")
        let one = 1
        let two = 2
        XCTAssertEqual(String(localized: "\(one) tracked · \(String(2026))", bundle: bundle, locale: locale), "1 seguido · 2026")
        XCTAssertEqual(String(localized: "\(two) tracked · \(String(2026))", bundle: bundle, locale: locale), "2 seguidos · 2026")
    }

    func testBaseballNumbersUseLocaleDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(BaseballNumberStyle.format(0.312, decimals: 3, omitLeadingZero: true, locale: german), ",312")
        XCTAssertEqual(BaseballNumberStyle.format(3.25, decimals: 2, locale: german), "3,25")
        XCTAssertEqual(BaseballNumberStyle.format(0.312, decimals: 3, omitLeadingZero: true, locale: english), ".312")
        XCTAssertEqual(BaseballNumberStyle.localizedDisplay(".312", locale: german), ",312")
        XCTAssertEqual(BaseballNumberStyle.localizedDisplay("95.4 mph", locale: german), "95,4 mph")
        XCTAssertEqual(BaseballNumberStyle.localizedDisplay("95,4 mph", locale: german), "95,4 mph")
    }

    func testTeamCountUsesLocalePluralRules() throws {
        let path = try XCTUnwrap(([Bundle.main] + Bundle.allBundles).compactMap {
            $0.path(forResource: "es", ofType: "lproj")
        }.first)
        let bundle = try XCTUnwrap(Bundle(path: path))
        let locale = Locale(identifier: "es")
        let one = 1
        let two = 2
        XCTAssertEqual(String(localized: "\(one) teams", bundle: bundle, locale: locale), "1 equipo")
        XCTAssertEqual(String(localized: "\(two) teams", bundle: bundle, locale: locale), "2 equipos")
    }
}
