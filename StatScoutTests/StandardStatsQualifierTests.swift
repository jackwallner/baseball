import XCTest
import SwiftUI
@testable import Baseball_Savvy_StatScout

/// Cumulative standard-stat percentiles use a 10-game comparison pool. Rates
/// keep the existing pool, because this rule is about volume stats only.
@MainActor
final class StandardStatPercentileTests: XCTestCase {

    private func batter(
        id: Int,
        name: String,
        games: Int?,
        playerType: String = "batter",
        category: MetricCategory = .hitting
    ) -> Player {
        let stats: [StandardStat] = [
            StandardStat(id: "std-\(id)-G", label: "G", value: String(games ?? 0), category: category),
        ]
        return Player(
            playerId: id, name: name, team: "SEA", position: "CF",
            handedness: "R", imageURL: nil, updatedAt: Date(), season: 2026,
            playerType: playerType,
            metrics: [
                Metric(
                    id: "m-\(id)", label: "xwOBA", value: ".330", percentile: 60,
                    category: category == .pitching ? .pitching : .hitting
                )
            ],
            standardStats: games == nil ? [] : stats,
            games: []
        )
    }

    func testCumulativeStatRequiresTenGames() {
        let qualified = batter(id: 1, name: "Regular", games: 10)
        let shortStint = batter(id: 2, name: "Callup", games: 9)

        XCTAssertTrue(StandardStatPercentileRules.qualifies(qualified, label: "HR", category: .hitting))
        XCTAssertFalse(StandardStatPercentileRules.qualifies(shortStint, label: "HR", category: .hitting))
    }

    func testRateStatDoesNotUseGamesGate() {
        let shortStint = batter(id: 3, name: "Callup", games: 1)

        XCTAssertTrue(StandardStatPercentileRules.qualifies(shortStint, label: "AVG", category: .hitting))
    }

    func testPitchingUsesPitchingGamesLineForTwoWayPlayers() {
        let player = Player(
            playerId: 4, name: "Two Way", team: "LAA", position: "TWP", handedness: "R/L",
            imageURL: nil, updatedAt: Date(), season: 2026, playerType: "two_way",
            metrics: [
                Metric(id: "hit", label: "xwOBA", value: ".330", percentile: 60, category: .hitting),
                Metric(id: "pit", label: "xERA", value: "3.50", percentile: 60, category: .pitching),
            ],
            standardStats: [
                StandardStat(id: "hit-g", label: "G", value: "100", category: .hitting),
                StandardStat(id: "pit-g", label: "G", value: "4", category: .pitching),
            ],
            games: []
        )

        XCTAssertFalse(StandardStatPercentileRules.qualifies(player, label: "IP", category: .pitching))
    }

    func testMissingGamesCannotQualifyCumulativeStat() {
        let player = batter(id: 5, name: "Legacy", games: nil)

        XCTAssertFalse(StandardStatPercentileRules.qualifies(player, label: "HR", category: .hitting))
    }
}
