import XCTest
@testable import Baseball_Savvy_StatScout

/// Timings against the real bundled history, the load a StatScout+ user
/// carries once they open any past season. Each board read used to rescan
/// every row of every season several times over, which is what made typing in
/// search and switching category stutter.
final class BoardPerformanceTests: XCTestCase {
    @MainActor
    private func loadedViewModel() async throws -> DashboardViewModel {
        let cache = TwoTierPlayerCache()
        // The first read may seed the on-disk cache from the bundle; the second
        // is what every later session pays.
        let seedStart = Date()
        _ = cache.loadHistoricalPlayers()
        print("PERF first history read: \(Int(Date().timeIntervalSince(seedStart) * 1000)) ms")

        let vm = DashboardViewModel(provider: MockProvider(players: []), cache: cache)
        vm.isPro = true
        let start = Date()
        await vm.loadHistoricalIfNeeded()
        print("PERF historical load: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        let rows = vm.playerHistories.values.reduce(0) { $0 + $1.count }
        try XCTSkipIf(rows < 10_000, "bundled history missing")
        return vm
    }

    @MainActor
    func testBoardReadsStayCheapWithFullHistory() async throws {
        let vm = try await loadedViewModel()
        let season = StatScoutSeason.current - 1
        vm.selectSeason(season)

        // One Stats tab body pass reads these, in about this mix.
        let start = Date()
        for query in ["", "j", "ju", "jud", "judg", "jud", "ju", "j", ""] {
            vm.searchText = query
            for category in [MetricCategory.hitting, .pitching] {
                vm.selectedCategory = category
                _ = vm.sortLabel
                _ = vm.currentSortMetric
                _ = vm.currentSortMetricForDisplay
                _ = vm.availableSortMetrics
                for _ in 0..<4 { _ = vm.leaderboard }
                _ = vm.seasonPlayers
                _ = vm.availableSeasons
                _ = vm.availablePositionFilters
                _ = vm.searchedTeams
                _ = vm.teamsWithData
                for _ in 0..<3 { _ = vm.players(forSeason: season) }
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        print("PERF 18 board passes: \(Int(elapsed * 1000)) ms")
        XCTAssertFalse(vm.leaderboard.isEmpty)
        XCTAssertLessThan(elapsed, 1.0, "18 board passes should take well under a second")
    }

    /// The index has to hand back exactly what the full scan did, in the same
    /// order, and the live postseason still reads its own slate.
    @MainActor
    func testSeasonIndexMatchesFullScan() async throws {
        let vm = try await loadedViewModel()
        for season in StatScoutSeason.earliest...StatScoutSeason.current {
            var seen = Set<Int>()
            let scanned = vm.playerHistories.values.flatMap { $0 }
                .filter { $0.season == season }
                .filter { seen.insert($0.playerId).inserted }
            XCTAssertEqual(vm.players(forSeason: season).map(\.id), scanned.map(\.id), "season \(season)")
        }

        let october = Array(vm.players(forSeason: StatScoutSeason.current - 1).prefix(3))
        vm.postseasonPlayers = october + october
        let live = vm.players(forSeason: StatScoutSeason.current, phase: .postseason)
        XCTAssertEqual(live.map(\.playerId), october.map(\.playerId))
        // A past year's postseason request falls back to its regular season.
        XCTAssertEqual(
            vm.players(forSeason: StatScoutSeason.current - 1, phase: .postseason).map(\.id),
            vm.players(forSeason: StatScoutSeason.current - 1).map(\.id)
        )
    }

    /// The Best/Worst and standard boards re-render on every loading tick too.
    @MainActor
    func testLeaderBoardsStayCheapWithFullHistory() async throws {
        let vm = try await loadedViewModel()
        vm.selectSeason(StatScoutSeason.current - 1)

        let start = Date()
        for _ in 0..<10 {
            _ = vm.allMetrics
            _ = vm.qualifiedSeasonPlayers
        }
        let elapsed = Date().timeIntervalSince(start)
        print("PERF 10 leader board passes: \(Int(elapsed * 1000)) ms")
        XCTAssertFalse(vm.allMetrics.isEmpty)
        XCTAssertLessThan(elapsed, 0.5, "10 leader board passes should take well under half a second")
    }
}
