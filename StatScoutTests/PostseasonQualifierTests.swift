import XCTest
@testable import Baseball_Savvy_StatScout

/// Postseason boards gate on MLB's per-club qualifier: 3.1 PA (rounded) or
/// 1 IP per team game, with team games read off each club's busiest hitter.
@MainActor
final class PostseasonQualifierTests: XCTestCase {

    private func player(
        id: Int,
        team: String,
        type: String,
        stats: [(String, String, MetricCategory)]
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team, position: type == "pitcher" ? "P" : "CF",
            handedness: "R", imageURL: nil, updatedAt: Date(), season: 2026,
            playerType: type,
            metrics: [
                Metric(
                    id: "m-\(id)", label: "xwOBA", value: ".330", percentile: 100,
                    category: type == "pitcher" ? .pitching : .hitting
                )
            ],
            standardStats: stats.map { StandardStat(id: "s-\(id)-\($0.0)", label: $0.0, value: $0.1, category: $0.2) },
            games: []
        )
    }

    private func hitter(_ id: Int, team: String, games: Int, pa: Int) -> Player {
        player(id: id, team: team, type: "batter", stats: [
            ("G", String(games), .hitting), ("PA", String(pa), .hitting), ("AVG", ".300", .hitting),
        ])
    }

    private func pitcher(_ id: Int, team: String, ip: String) -> Player {
        player(id: id, team: team, type: "pitcher", stats: [
            ("G", "9", .pitching), ("IP", ip, .pitching), ("ERA", "0.00", .pitching),
        ])
    }

    func testOnePlateAppearanceCameoDoesNotQualify() {
        let regular = hitter(1, team: "NYY", games: 5, pa: 22)
        let cameo = hitter(2, team: "NYY", games: 1, pa: 1)
        let q = PostseasonQualifier(players: [regular, cameo])

        XCTAssertTrue(q.qualifies(regular, for: .hitting))
        XCTAssertFalse(q.qualifies(cameo, for: .hitting))
    }

    /// Matches MLB.com: 18 PA in 6 games misses (18.6 rounds to 19), while
    /// 6 PA in 2 games qualifies (6.2 rounds to 6).
    func testPlateAppearanceThresholdRoundsLikeMLB() {
        let sixGames = hitter(1, team: "SD", games: 6, pa: 18)
        let sixGamesEnough = hitter(2, team: "SD", games: 6, pa: 19)
        let twoGames = hitter(3, team: "BOS", games: 2, pa: 6)
        let q = PostseasonQualifier(players: [sixGames, sixGamesEnough, twoGames])

        XCTAssertFalse(q.qualifies(sixGames, for: .hitting))
        XCTAssertTrue(q.qualifies(sixGamesEnough, for: .hitting))
        XCTAssertTrue(q.qualifies(twoGames, for: .hitting))
    }

    /// Team games come from the club's position players, not from a reliever's
    /// nine appearances, and box-score thirds count as real thirds.
    func testPitchersNeedOneInningPerTeamGame() {
        let lineup = hitter(1, team: "HOU", games: 2, pa: 8)
        let starter = pitcher(2, team: "HOU", ip: "2.0")
        let opener = pitcher(3, team: "HOU", ip: "1.2")
        let q = PostseasonQualifier(players: [lineup, starter, opener])

        XCTAssertEqual(q.teamGames["HOU"], 2)
        XCTAssertTrue(q.qualifies(starter, for: .pitching))
        XCTAssertFalse(q.qualifies(opener, for: .pitching))
    }

    func testBoxScoreInnings() {
        XCTAssertEqual(PostseasonQualifier.innings(4.2), 4 + 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(PostseasonQualifier.innings(3.1), 3 + 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(PostseasonQualifier.innings(7.0), 7, accuracy: 0.0001)
    }

    func testPostseasonBoardsDropTheCameo() {
        let vm = DashboardViewModel(provider: PreviewStatcastAPI())
        vm.postseasonThrough = Date()
        vm.selectedSeason = StatScoutSeason.current
        vm.postseasonPlayers = [
            hitter(1, team: "NYY", games: 5, pa: 22),
            hitter(2, team: "NYY", games: 1, pa: 1),
        ]
        vm.selectedPhase = .postseason

        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1])
        vm.qualifierLevel = .all
        XCTAssertEqual(Set(vm.leaderboard.map(\.playerId)), [1, 2])
    }
}

final class BaseballNumberStyleTests: XCTestCase {
    func testThreePlaceRatesDropTheLeadingZero() {
        XCTAssertEqual(BaseballNumberStyle.display("0.282"), ".282")
        XCTAssertEqual(BaseballNumberStyle.display("1.000"), "1.000")
        XCTAssertEqual(BaseballNumberStyle.display("0.00"), "0.00")
        XCTAssertEqual(BaseballNumberStyle.display("0.5%"), "0.5%")
        XCTAssertEqual(BaseballNumberStyle.display("12"), "12")
    }

    func testDecodedStatsUseBaseballStyle() throws {
        let json = #"[{"id":"a","label":"AVG","value":"0.282","category":"hitting"}]"#
        let stats = try JSONDecoder().decode([StandardStat].self, from: Data(json.utf8))
        XCTAssertEqual(stats.first?.value, ".282")
        let metric = #"{"id":"m","label":"xwOBA","value":"0.442","percentile":99,"category":"Hitting"}"#
        XCTAssertEqual(try JSONDecoder().decode(Metric.self, from: Data(metric.utf8)).value, ".442")
    }
}

final class GameLogTeamCodeTests: XCTestCase {
    /// Game logs file the A's and D-backs under MLB's ATH and AZ.
    func testRelocatedAndRenamedClubsQueryEverySpelling() {
        XCTAssertEqual(StatcastAPI.gameLogTeamCodes("OAK"), ["OAK", "ATH"])
        XCTAssertEqual(StatcastAPI.gameLogTeamCodes("ARI"), ["ARI", "AZ"])
        XCTAssertEqual(StatcastAPI.gameLogTeamCodes("SEA"), ["SEA"])
    }
}

@MainActor
final class StaleRecentFormTests: XCTestCase {
    private func form(id: Int, asOf: String) -> RecentForm {
        let json = """
        {
          "player_id": \(id), "season": 2026, "player_type": "batter",
          "window_days": 15, "as_of": "\(asOf)", "team": "SEA",
          "games": 10, "plate_appearances": 40, "batted_ball_events": 20,
          "metrics": {}, "prior_metrics": {}, "delta": {}
        }
        """
        return try! JSONDecoder().decode(RecentForm.self, from: Data(json.utf8))
    }

    /// A window left over from July must not rank beside September's.
    func testOnlyWindowsOnTheNewestAnchorLoad() async {
        let provider = MockProvider(recentForm: [
            form(id: 1, asOf: "2026-09-27"),
            form(id: 2, asOf: "2026-07-25"),
        ])
        let vm = DashboardViewModel(provider: provider)
        vm.selectedSeason = 2026
        await vm.loadRecentFormIfNeeded(window: .fortnight)

        XCTAssertNotNil(vm.recentForm(for: 1, window: .fortnight))
        XCTAssertNil(vm.recentForm(for: 2, window: .fortnight))
    }
}
