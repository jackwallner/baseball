import XCTest
import SwiftUI
@testable import Baseball_Savvy_StatScout

/// The standard leaderboards' playing-time gate.
///
/// A rate stat on a tiny sample is the single most obviously-wrong thing a
/// leaderboard can show, and the AVG board was topped by a hitter with nine
/// plate appearances. These pin both halves of the fix: the flat games floor
/// every board carries, and MLB's own qualifier on the boards whose value is a
/// rate.
@MainActor
final class StandardStatsQualifierTests: XCTestCase {

    private func batter(
        id: Int,
        name: String,
        avg: String,
        pa: Int,
        games: Int?,
        hr: Int = 5
    ) -> Player {
        var stats: [StandardStat] = [
            StandardStat(id: "std-hit-AVG-\(id)", label: "AVG", value: avg, category: .hitting),
            StandardStat(id: "std-hit-PA-\(id)", label: "PA", value: String(pa), category: .hitting),
            StandardStat(id: "std-hit-AB-\(id)", label: "AB", value: String(pa), category: .hitting),
            StandardStat(id: "std-hit-HR-\(id)", label: "HR", value: String(hr), category: .hitting),
        ]
        if let games {
            stats.append(StandardStat(id: "std-hit-G-\(id)", label: "G", value: String(games), category: .hitting))
        }
        return Player(
            playerId: id, name: name, team: "SEA", position: "CF",
            handedness: "R", imageURL: nil, updatedAt: Date(), season: 2026,
            playerType: "batter",
            metrics: [
                Metric(id: "m-\(id)", label: "xwOBA", value: ".330", percentile: 60, category: .hitting)
            ],
            standardStats: stats,
            games: []
        )
    }

    private func board(
        players: [Player],
        stat: String,
        category: MetricCategory = .hitting
    ) -> StandardStatsLeadersView {
        StandardStatsLeadersView(
            players: players,
            selectedStat: .constant(stat),
            selectedCategory: .constant(category),
            sortDescending: .constant(true)
        )
    }

    /// A full-season pool: one everyday player sets the ruler, so "3.1 PA per
    /// team game" resolves to a real number.
    private func leaguePool() -> [Player] {
        [
            batter(id: 1, name: "Everyday Regular", avg: "0.300", pa: 500, games: 111),
            batter(id: 2, name: "Second Regular", avg: "0.290", pa: 460, games: 108),
        ]
    }

    func testGamesFloorDropsAShortStint() {
        let pool = leaguePool() + [
            batter(id: 3, name: "Cup Of Coffee", avg: "0.556", pa: 9, games: 4)
        ]
        let names = board(players: pool, stat: "HR").filteredPlayers.map(\.name)
        XCTAssertFalse(names.contains("Cup Of Coffee"))
        XCTAssertTrue(names.contains("Everyday Regular"))
    }

    /// The case that started this: a games floor alone is not enough, because a
    /// part-timer clears ten games and still posts a .417 on 25 trips.
    func testRateBoardAppliesTheMLBQualifierOnTopOfTheGamesFloor() {
        let pool = leaguePool() + [
            batter(id: 4, name: "Hot Bench Bat", avg: "0.417", pa: 25, games: 14)
        ]
        let avgNames = board(players: pool, stat: "AVG").filteredPlayers.map(\.name)
        XCTAssertFalse(avgNames.contains("Hot Bench Bat"))

        // …and the same player is welcome on a counting board, where a small
        // sample can't produce a misleading leader.
        let hrNames = board(players: pool, stat: "HR").filteredPlayers.map(\.name)
        XCTAssertTrue(hrNames.contains("Hot Bench Bat"))
    }

    func testQualifiedRegularSurvivesTheRateQualifier() {
        let names = board(players: leaguePool(), stat: "AVG").filteredPlayers.map(\.name)
        XCTAssertEqual(Set(names), ["Everyday Regular", "Second Regular"])
    }

    /// Bundled historical seasons predate the batting "G", so the floor has to
    /// fall back to plate appearances rather than emptying the board.
    func testMissingGamesFallsBackToPlateAppearances() {
        let pool = [
            batter(id: 5, name: "No Games Column", avg: "0.300", pa: 500, games: nil),
            batter(id: 6, name: "Tiny Sample", avg: "0.500", pa: 8, games: nil),
        ]
        let names = board(players: pool, stat: "HR").filteredPlayers.map(\.name)
        XCTAssertTrue(names.contains("No Games Column"))
        XCTAssertFalse(names.contains("Tiny Sample"))
    }
}
