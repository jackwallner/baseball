import XCTest
@testable import Baseball_Savvy_StatScout

/// A two-way player carries a batting line and a pitching line at once, and
/// five labels (H, R, HR, BB, SO) appear on both. These pin the client side of
/// telling them apart; `backend/tests/test_ingest.py` pins the ingest side.
final class StandardStatsTests: XCTestCase {

    private func ohtani() -> Player {
        Player(
            playerId: 660271, name: "Shohei Ohtani", team: "LAD", position: "TWP",
            handedness: "L/R", imageURL: nil, updatedAt: Date(), season: 2026,
            playerType: "two_way",
            metrics: [
                Metric(id: "h1", label: "xwOBA", value: ".405", percentile: 98, category: .hitting),
                Metric(id: "p1", label: "xwOBA", value: ".257", percentile: 94, category: .pitching),
            ],
            standardStats: [
                StandardStat(id: "std-hit-AVG", label: "AVG", value: "0.282", category: .hitting),
                StandardStat(id: "std-hit-AB", label: "AB", value: "373", category: .hitting),
                StandardStat(id: "std-hit-H", label: "H", value: "105", category: .hitting),
                StandardStat(id: "std-hit-HR", label: "HR", value: "46", category: .hitting),
                StandardStat(id: "std-pit-ERA", label: "ERA", value: "1.79", category: .pitching),
                StandardStat(id: "std-pit-H", label: "H", value: "55", category: .pitching),
                StandardStat(id: "std-pit-HR", label: "HR", value: "4", category: .pitching),
                StandardStat(id: "std-fld-E", label: "E", value: "1", category: .fielding),
            ],
            games: []
        )
    }

    func testAmbiguousLabelResolvesToTheRequestedSide() {
        let stats = ohtani().standardStats ?? []
        XCTAssertEqual(stats.stat("H", category: .hitting, playerType: "two_way")?.value, "105")
        XCTAssertEqual(stats.stat("H", category: .pitching, playerType: "two_way")?.value, "55")
        XCTAssertEqual(stats.stat("HR", category: .hitting, playerType: "two_way")?.value, "46")
        XCTAssertEqual(stats.stat("HR", category: .pitching, playerType: "two_way")?.value, "4")
    }

    func testUnambiguousLabelsDoNotNeedTheRightCategory() {
        let stats = ohtani().standardStats ?? []
        // ERA only exists on one line, so asking for it as "hitting" still works
        // rather than returning nil and blanking the row.
        XCTAssertEqual(stats.stat("ERA", category: .hitting, playerType: "two_way")?.value, "1.79")
        XCTAssertEqual(stats.stat("AVG", category: .pitching, playerType: "two_way")?.value, "0.282")
    }

    func testBattingLineIsInternallyConsistent() {
        let stats = ohtani().standardStats ?? []
        let avg = Double(stats.stat("AVG", category: .hitting, playerType: "two_way")!.value)!
        let ab = Double(stats.stat("AB", category: .hitting, playerType: "two_way")!.value)!
        let h = Double(stats.stat("H", category: .hitting, playerType: "two_way")!.value)!
        // The bug made this fail by a factor of two: .282 x 373 is 105, not 55.
        XCTAssertEqual(avg * ab, h, accuracy: 1.0)
    }

    // MARK: - Legacy rows with no category

    func testLegacyPitchingOnlyLabelsInferPitching() {
        for label in ["ERA", "WHIP", "IP", "QS", "BF", "K/9"] {
            let stat = StandardStat(id: "std-\(label)", label: label, value: "1")
            XCTAssertEqual(stat.resolvedCategory(playerType: "two_way"), .pitching, label)
        }
    }

    func testLegacyFieldingLabelsInferFielding() {
        for label in ["E", "A", "PO", "DP", "FLD%", "GF"] {
            let stat = StandardStat(id: "std-\(label)", label: label, value: "1")
            XCTAssertEqual(stat.resolvedCategory(playerType: "batter"), .fielding, label)
        }
    }

    func testLegacyRowsFallBackToThePlayersOwnSide() {
        let h = StandardStat(id: "std-H", label: "H", value: "88")
        XCTAssertEqual(h.resolvedCategory(playerType: "pitcher"), .pitching)
        XCTAssertEqual(h.resolvedCategory(playerType: "batter"), .hitting)
    }

    func testCategoryIsOptionalOnTheWire() throws {
        // Rows written before the backend emitted a category must still decode.
        let json = #"{"id":"std-H","label":"H","value":"105"}"#.data(using: .utf8)!
        let stat = try JSONDecoder().decode(StandardStat.self, from: json)
        XCTAssertNil(stat.category)
        XCTAssertEqual(stat.value, "105")
    }

    func testCategoryDecodesLowercaseBackendValue() throws {
        let json = #"{"id":"std-hit-H","label":"H","value":"105","category":"hitting"}"#.data(using: .utf8)!
        let stat = try JSONDecoder().decode(StandardStat.self, from: json)
        XCTAssertEqual(stat.category, .hitting)
    }

    func testPlayerDecodesLiveStandardStatCategoryCasing() throws {
        let json = #"{"id":660271,"name":"Shohei Ohtani","team":"LAD","position":"TWP","handedness":"L/R","image_url":null,"updated_at":"2026-07-28T05:40:44.802835+00:00","season":2026,"player_type":"two_way","source":"baseball_savant_enhanced","metrics":[{"id":"h1","label":"xwOBA","value":".405","category":"Hitting","percentile":98}],"standard_stats":[{"id":"std-hit-H","label":"H","value":"105","category":"hitting"}],"games":[]}"#.data(using: .utf8)!
        let player = try JSONDecoder.statScout.decode(Player.self, from: json)
        XCTAssertEqual(player.standardStats?.first?.category, .hitting)
    }

    // MARK: - Overall percentile weighting

    /// A flat mean over every metric let whichever category happened to carry
    /// the most metrics dominate. Two identical bats should score the same
    /// regardless of how much glove data came with them.
    func testOverallPercentileWeightsCategoriesEqually() {
        func make(fieldingMetrics: Int) -> Player {
            var metrics = [
                Metric(id: "h1", label: "xwOBA", value: ".400", percentile: 90, category: .hitting),
                Metric(id: "h2", label: "Barrel%", value: "15%", percentile: 90, category: .hitting),
            ]
            for i in 0..<fieldingMetrics {
                metrics.append(Metric(id: "f\(i)", label: "Range (OAA)", value: "", percentile: 10, category: .fielding))
            }
            return Player(
                playerId: 1, name: "X", team: "NYY", position: "RF", handedness: "R/R",
                imageURL: nil, updatedAt: Date(), season: 2026, playerType: "batter",
                metrics: metrics, standardStats: [], games: []
            )
        }
        XCTAssertEqual(make(fieldingMetrics: 1).overallPercentile, make(fieldingMetrics: 4).overallPercentile)
        // 90 hitting, 10 fielding, averaged per category.
        XCTAssertEqual(make(fieldingMetrics: 1).overallPercentile, 50)
    }

    func testTwoWayOverallTakesTheBetterSide() {
        XCTAssertEqual(ohtani().overallPercentile, 98)
    }
}
