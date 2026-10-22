import XCTest
@testable import Baseball_Savvy_StatScout

/// Time budgets for the paths a StatScout+ user hits on open and while
/// scrolling, against a worst-case history built in code: every season since
/// 2015, about 800 hitters and 700 pitchers each. That is more rows than the
/// bundled plist carries, so a pass here is a pass on the real thing with room
/// to spare.
///
/// Guards the board stutter fixed in 8252c5a and earlier (every read rescanned
/// every row of every season). Budgets are about five times the time measured
/// on the simulator (floored at 0.5 s), so a loaded machine does not trip them but an accidental
/// rescan per read does.
final class PerformanceBudgetTests: XCTestCase {
    private static let teams = [
        "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
        "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "ATH",
        "PHI", "PIT", "SD", "SF", "SEA", "STL", "TB", "TEX", "TOR", "WSH",
    ]
    private static let positions = ["C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH"]
    private static let firstNames = ["Aaron", "Juan", "Jose", "Judge", "Mookie", "Shohei", "Paul", "Corey", "Julio", "Bobby"]
    private static let lastNames = (0..<60).map { "Surname\($0)" }
    private static let hitterCount = 800
    private static let pitcherCount = 700

    private static let hitterLabels: [(String, MetricCategory)] = [
        ("xwOBA", .hitting), ("xBA", .hitting), ("xSLG", .hitting), ("Barrel%", .hitting),
        ("Hard-Hit%", .hitting), ("EV", .hitting), ("K%", .hitting), ("BB%", .hitting),
        ("Whiff%", .hitting), ("Chase%", .hitting), ("Bat Speed", .hitting),
        ("Range (OAA)", .fielding), ("Arm Strength", .fielding), ("Sprint Speed", .running),
    ]
    private static let pitcherLabels: [(String, MetricCategory)] = [
        ("xwOBA", .pitching), ("xERA", .pitching), ("K%", .pitching), ("BB%", .pitching),
        ("Whiff%", .pitching), ("Chase%", .pitching), ("Barrel%", .pitching),
        ("Hard-Hit%", .pitching), ("Fastball Velo", .pitching), ("Fastball Spin", .pitching),
    ]

    private static func variants(_ labels: [(String, MetricCategory)]) -> [[Metric]] {
        (0..<32).map { variant in
            labels.enumerated().map { index, entry in
                let percentile = (variant * 7 + index * 13) % 100
                return Metric(
                    id: "\(entry.0)-\(variant)", label: entry.0,
                    value: String(format: "%.3f", Double(percentile) / 300),
                    percentile: percentile, category: entry.1
                )
            }
        }
    }

    static func buildHistory(throughSeason last: Int) -> [Player] {
        let hitterMetrics = variants(hitterLabels)
        let pitcherMetrics = variants(pitcherLabels)
        let hitterStats = [StandardStat(id: "pa", label: "PA", value: "540"), StandardStat(id: "avg", label: "AVG", value: "0.271")]
        let pitcherStats = [StandardStat(id: "ip", label: "IP", value: "150.1"), StandardStat(id: "era", label: "ERA", value: "3.80")]
        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        var players: [Player] = []
        players.reserveCapacity((last - StatScoutSeason.earliest + 1) * (hitterCount + pitcherCount))
        for season in StatScoutSeason.earliest...last {
            for slot in 0..<hitterCount {
                let id = (slot + season * 3) % (hitterCount + 60)
                players.append(Player(
                    playerId: id,
                    name: "\(firstNames[id % firstNames.count]) \(lastNames[(id / 7) % lastNames.count])",
                    team: teams[(id + season) % teams.count],
                    position: positions[id % positions.count], handedness: "R/R", imageURL: nil,
                    updatedAt: updated, season: season, playerType: "batter",
                    metrics: hitterMetrics[(slot + season) % 32], standardStats: hitterStats, games: []
                ))
            }
            for slot in 0..<pitcherCount {
                let id = 100_000 + (slot + season * 3) % (pitcherCount + 60)
                players.append(Player(
                    playerId: id,
                    name: "\(firstNames[id % firstNames.count]) \(lastNames[(id / 7) % lastNames.count])",
                    team: teams[(id + season) % teams.count],
                    position: "P", handedness: "R/R", imageURL: nil,
                    updatedAt: updated, season: season, playerType: "pitcher",
                    metrics: pitcherMetrics[(slot + season) % 32], standardStats: pitcherStats, games: []
                ))
            }
        }
        return players
    }

    private static let fixture: [Player] = buildHistory(throughSeason: StatScoutSeason.current - 1)

    @MainActor
    private func openedViewModel() async -> DashboardViewModel {
        let vm = DashboardViewModel(
            provider: MockProvider(players: []),
            cache: InMemoryPlayerCache(seed: Self.fixture)
        )
        vm.isPro = true
        await vm.loadHistoricalIfNeeded()
        return vm
    }

    private func measure(_ label: String, _ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        print("PERF \(label): \(Int(elapsed * 1000)) ms")
        return elapsed
    }

    func testFixtureBuildsQuickly() {
        let start = Date()
        let rows = Self.buildHistory(throughSeason: StatScoutSeason.current - 1)
        let elapsed = Date().timeIntervalSince(start)
        print("PERF fixture build (\(rows.count) rows): \(Int(elapsed * 1000)) ms")
        XCTAssertGreaterThan(rows.count, 15_000)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// Opening a past season: group, sort and index every row, then derive
    /// the team table. The main-actor part of what the StatScout+ user waits on.
    @MainActor
    func testIngestingFullHistoryStaysWithinBudget() async {
        let vm = DashboardViewModel(
            provider: MockProvider(players: []),
            cache: InMemoryPlayerCache(seed: Self.fixture)
        )
        vm.isPro = true
        let start = Date()
        await vm.loadHistoricalIfNeeded()
        let elapsed = Date().timeIntervalSince(start)
        print("PERF ingest full history: \(Int(elapsed * 1000)) ms")
        XCTAssertTrue(vm.hasLoadedHistorical)
        XCTAssertGreaterThan(vm.playerHistories.count, 1_000)
        XCTAssertLessThan(elapsed, 0.5)  // measured 61 ms
    }

    /// Flipping through every season on every board, reading what one render
    /// reads: the "scroll through the season menu" path.
    @MainActor
    func testSeasonAndCategorySwitchingStaysWithinBudget() async {
        let vm = await openedViewModel()
        let seasons = vm.availableSeasons
        XCTAssertGreaterThan(seasons.count, 10)
        let elapsed = measure("switch \(seasons.count) seasons x 4 categories") {
            for season in seasons {
                vm.selectSeason(season)
                for category in MetricCategory.allCases {
                    vm.selectedCategory = category
                    _ = vm.sortLabel
                    _ = vm.currentSortMetric
                    _ = vm.availableSortMetrics
                    for _ in 0..<3 { _ = vm.leaderboard }
                    _ = vm.availablePositionFilters
                    _ = vm.teamsWithData
                }
            }
        }
        vm.selectedCategory = .hitting
        XCTAssertFalse(vm.leaderboard.isEmpty)
        XCTAssertLessThan(elapsed, 8.5)  // measured 1.7 s
    }

    /// Typing in search on the busiest board, then Best/Worst and the
    /// qualified list.
    @MainActor
    func testSearchAndLeaderBoardsStayWithinBudget() async {
        let vm = await openedViewModel()
        vm.selectSeason(StatScoutSeason.current - 1)
        vm.selectedCategory = .hitting
        let typing = measure("search typing, hitting") {
            for query in ["", "j", "ju", "jud", "judg", "jud", "ju", "j", "", "surname1", ""] {
                vm.searchText = query
                _ = vm.leaderboard
                _ = vm.searchedTeams
            }
        }
        XCTAssertLessThan(typing, 0.5)  // measured 93 ms

        vm.searchText = ""
        let boards = measure("best/worst + qualified") {
            for _ in 0..<10 {
                _ = vm.allMetrics
                _ = vm.qualifiedSeasonPlayers
            }
        }
        XCTAssertFalse(vm.allMetrics.isEmpty)
        XCTAssertLessThan(boards, 0.6)  // measured 109 ms
    }

    /// Team pages and profiles resolve players by team and by season for
    /// every club, every time they open.
    @MainActor
    func testTeamAndSeasonLookupsStayWithinBudget() async {
        let vm = await openedViewModel()
        vm.selectSeason(StatScoutSeason.current - 1)
        let elapsed = measure("30 team rosters + 11 season rosters") {
            for team in Self.teams {
                _ = vm.players(forTeam: team)
                _ = vm.teamScore(team)
            }
            for season in StatScoutSeason.earliest..<StatScoutSeason.current {
                _ = vm.players(forSeason: season)
            }
        }
        XCTAssertLessThan(elapsed, 0.5)  // measured 30 ms
    }
}
