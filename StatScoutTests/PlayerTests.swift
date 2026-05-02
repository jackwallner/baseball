import XCTest
@testable import Baseball_Savvy_StatScout

final class PlayerTests: XCTestCase {
    func testOverallPercentileDoubleAverage() {
        let metrics = [
            Metric(id: "m1", label: "A", value: "1", percentile: 75, category: .hitting),
            Metric(id: "m2", label: "B", value: "2", percentile: 76, category: .hitting),
            Metric(id: "m3", label: "C", value: "3", percentile: 77, category: .hitting)
        ]
        let player = Player(
            playerId: 1, name: "Test", team: "NYY", position: "RF",
            handedness: "R/R", imageURL: nil,
            updatedAt: Date(), metrics: metrics, standardStats: [], games: []
        )
        XCTAssertEqual(player.overallPercentile, 76) // 75.9 rounded
    }

    func testShareSummaryIncludesTopSignal() {
        let metric = Metric(id: "m1", label: "xwOBA", value: ".463", percentile: 100, category: .hitting)
        let player = Player(
            playerId: 1, name: "Aaron Judge", team: "NYY", position: "RF",
            handedness: "R/R", imageURL: nil,
            updatedAt: Date(), metrics: [metric], standardStats: [], games: []
        )
        let summary = player.shareSummary
        XCTAssertTrue(summary.contains("Aaron Judge"))
        XCTAssertTrue(summary.contains("xwOBA"))
        XCTAssertTrue(summary.contains("100th"))
    }

    func testTwoWayOverallUsesBestCategoryAverage() {
        let metrics = [
            Metric(id: "h1", label: "xwOBA", value: ".400", percentile: 95, category: .hitting),
            Metric(id: "h2", label: "Barrel%", value: "12", percentile: 95, category: .hitting),
            Metric(id: "p1", label: "xwOBA", value: ".320", percentile: 30, category: .pitching),
            Metric(id: "p2", label: "K%", value: "22", percentile: 30, category: .pitching)
        ]
        let player = Player(
            playerId: 1, name: "Two Way", team: "LAA", position: "Two-way",
            handedness: "L/R", imageURL: nil,
            updatedAt: Date(), playerType: "two_way",
            metrics: metrics, standardStats: [], games: []
        )
        XCTAssertEqual(player.overallPercentile, 95)
    }

    func testPlayerDecodesSeasonAndPlayerType() throws {
        let json = """
        {
            "id": 1,
            "name": "Test",
            "team": "NYY",
            "position": "RF",
            "handedness": "R/R",
            "image_url": null,
            "updated_at": "2026-04-28T12:00:00Z",
            "season": 2026,
            "player_type": "batter",
            "source": "baseball_savant",
            "metrics": [],
            "standard_stats": [],
            "games": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder.statScout
        let player = try decoder.decode(Player.self, from: json)
        XCTAssertEqual(player.season, 2026)
        XCTAssertEqual(player.playerType, "batter")
        XCTAssertEqual(player.source, "baseball_savant")
    }

    func testInitialsHandleSuffixes() {
        let player = Player(playerId: 1, name: "Bobby Witt Jr.", team: "KC", position: "SS", handedness: "R/R", imageURL: nil, updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(player.initials, "BWJ")
    }

    func testWeeklyDeltaSumsRecentGamesOnly() {
        let now = Date()
        let player = Player(
            playerId: 1, name: "Test", team: "NYY", position: "RF",
            handedness: "R/R", imageURL: nil,
            updatedAt: now, metrics: [], standardStats: [],
            games: [
                GameTrend(id: "recent-up", date: now.addingTimeInterval(-24 * 3600), opponent: "BOS", summary: "", percentileDelta: 5, keyMetric: "xwOBA"),
                GameTrend(id: "recent-down", date: now.addingTimeInterval(-2 * 24 * 3600), opponent: "TOR", summary: "", percentileDelta: -2, keyMetric: "Barrel%"),
                GameTrend(id: "old", date: now.addingTimeInterval(-8 * 24 * 3600), opponent: "TB", summary: "", percentileDelta: 20, keyMetric: "Hard-Hit%")
            ]
        )

        XCTAssertEqual(player.weeklyDelta, 3)
    }
}
