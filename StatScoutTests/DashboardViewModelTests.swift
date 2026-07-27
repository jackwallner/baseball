import XCTest
@testable import Baseball_Savvy_StatScout

final class DashboardViewModelTests: XCTestCase {
    @MainActor
    func testAllMetricsKeyCollision() async throws {
        let players: [Player] = [
            Player(
                playerId: 1, name: "A", team: "NYY", position: "DH", handedness: "L/R", imageURL: nil,
                updatedAt: Date(), season: 2026,
                metrics: [
                    Metric(id: "m1", label: "xwOBA", value: ".400", percentile: 90, category: .hitting)
                ],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "NYY", position: "SP", handedness: "R/R", imageURL: nil,
                updatedAt: Date(), season: 2026,
                metrics: [
                    Metric(id: "m2", label: "xwOBA", value: ".350", percentile: 85, category: .pitching)
                ],
                standardStats: [],
                games: []
            )
        ]
        let provider = MockProvider(players: players)
        let vm = DashboardViewModel(provider: provider)
        await vm.load()
        let all = vm.allMetrics
        XCTAssertEqual(all.count, 2, "Same label in different categories should produce 2 entries")
    }

    @MainActor
    func testLoadDistinguishesErrors() async {
        let decoderProvider = MockProvider(error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")))
        let vm1 = DashboardViewModel(provider: decoderProvider)
        await vm1.load()
        XCTAssertTrue(vm1.errorMessage?.contains("format changed") == true)

        let urlProvider = MockProvider(error: URLError(.notConnectedToInternet))
        let vm2 = DashboardViewModel(provider: urlProvider)
        await vm2.load()
        XCTAssertTrue(vm2.errorMessage?.contains("connection") == true)
    }

    @MainActor
    func testLastUpdatedReturnsNilWhenEmpty() {
        let vm = DashboardViewModel(provider: MockProvider(players: []))
        XCTAssertNil(vm.lastUpdated)
    }

    @MainActor
    func testTeamFullNameReturnsCorrectFullName() {
        // City-only naming (nickname dropped in the Savant-style UI), with the
        // league in parens only where a city fields two clubs.
        XCTAssertEqual(teamFullName("NYY"), "New York (AL)")
        XCTAssertEqual(teamFullName("NYM"), "New York (NL)")
        XCTAssertEqual(teamFullName("BOS"), "Boston")
        XCTAssertEqual(teamFullName("LAD"), "Los Angeles (NL)")
        XCTAssertEqual(teamFullName("LAA"), "Los Angeles (AL)")
        // Aliases normalize before the lookup.
        XCTAssertEqual(teamFullName("CHW"), "Chicago (AL)")
        XCTAssertEqual(teamFullName("New York Yankees"), "New York (AL)")
        XCTAssertEqual(teamFullName("Unknown"), "Unknown")
    }

    @MainActor
    func testPlayersForTeamMatchesAliases() async {
        let players = [
            Player(
                playerId: 1, name: "A", team: "New York Yankees", position: "RF", handedness: "R/R", imageURL: nil,
                updatedAt: Date(), season: 2026,
                metrics: [],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "CHW", position: "1B", handedness: "L/R", imageURL: nil,
                updatedAt: Date(), season: 2026,
                metrics: [],
                standardStats: [],
                games: []
            )
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2026
        await vm.load()

        XCTAssertEqual(vm.players(forTeam: "NYY").map { $0.playerId }, [1])
        XCTAssertEqual(vm.players(forTeam: "CWS").map { $0.playerId }, [2])
    }

    @MainActor
    func testTeamCountsPopulatedAfterLoad() async {
        let players = [
            Player(playerId: 1, name: "A", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil, updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: []),
            Player(playerId: 2, name: "B", team: "NYY", position: "1B", handedness: "L/R", imageURL: nil, updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: []),
            Player(playerId: 3, name: "C", team: "BOS", position: "SS", handedness: "R/R", imageURL: nil, updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: [])
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2026
        await vm.load()
        XCTAssertEqual(vm.teamCounts["NYY"], 2)
        XCTAssertEqual(vm.teamCounts["BOS"], 1)
    }

    @MainActor
    func testCacheHydratesPlayersBeforeFetch() async {
        let cached = [
            Player(playerId: 99, name: "Cached", team: "NYY", position: "DH", handedness: "L/R", imageURL: nil, updatedAt: Date(), metrics: [], standardStats: [], games: [])
        ]
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = DashboardViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)), cache: cache)
        await vm.load()
        XCTAssertEqual(vm.players.map { $0.id }, ["99-0"], "Cached players should be shown even when refresh fails")
    }

    @MainActor
    func testSortLabelReflectsCategory() async {
        // Fixtures sit on the current season: past seasons are StatScout+ gated,
        // so a non-Pro VM would never snap `selectedSeason` onto them and
        // `seasonPlayers` (and everything downstream) would come back empty.
        let hitters = [
            Player(playerId: 1, name: "A", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil, updatedAt: Date(), season: StatScoutSeason.current, playerType: "batter", source: "baseball_savant",
                   metrics: [Metric(id: "m1", label: "xwOBA", value: ".400", percentile: 90, category: .hitting)], standardStats: [], games: [])
        ]

        let vm = DashboardViewModel(provider: MockProvider(players: hitters))
        await vm.load()
        _ = vm.leaderboard  // Trigger computation of sort metric

        // Default category is hitting, should find xwOBA in data
        XCTAssertEqual(vm.sortLabel, "xwOBA")

        // Test with pitchers that have Barrel%
        let pitchers = [
            Player(playerId: 2, name: "B", team: "NYY", position: "SP", handedness: "R/R", imageURL: nil, updatedAt: Date(), season: StatScoutSeason.current, playerType: "pitcher", source: "baseball_savant",
                   metrics: [Metric(id: "m1", label: "Barrel%", value: "5%", percentile: 85, category: .pitching)], standardStats: [], games: [])
        ]
        let vmPitching = DashboardViewModel(provider: MockProvider(players: pitchers))
        await vmPitching.load()
        vmPitching.selectedCategory = .pitching
        _ = vmPitching.leaderboard  // Trigger computation
        XCTAssertEqual(vmPitching.sortLabel, "Barrel%")

        // Test empty data falls back to "Top Category"
        let vmEmpty = DashboardViewModel(provider: MockProvider(players: []))
        await vmEmpty.load()
        vmEmpty.selectedCategory = .hitting
        _ = vmEmpty.leaderboard  // Trigger computation
        XCTAssertEqual(vmEmpty.sortLabel, "Top Category")

        // Test nil category shows xwOBA
        let vmNil = DashboardViewModel(provider: MockProvider(players: hitters))
        await vmNil.load()
        vmNil.selectedCategory = nil
        _ = vmNil.leaderboard
        XCTAssertEqual(vmNil.sortLabel, "xwOBA")
    }

    @MainActor
    func testPitchingSortUsesAvailableMetrics() async {
        // Pitcher with Barrel% but no xwOBA/K% (common early in season)
        let pitcher = Player(
            playerId: 1, name: "Test Pitcher", team: "NYY", position: "SP",
            handedness: "R/R", imageURL: nil, updatedAt: Date(), season: StatScoutSeason.current, playerType: "pitcher", source: "baseball_savant",
            metrics: [
                Metric(id: "m1", label: "Barrel%", value: "5.2%", percentile: 85, category: .pitching),
                Metric(id: "m2", label: "Whiff%", value: "28%", percentile: 70, category: .pitching)
            ],
            standardStats: [],
            games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [pitcher]))
        await vm.load()
        vm.selectedCategory = .pitching

        // Should find the pitcher in filtered list
        XCTAssertEqual(vm.filteredPlayers.count, 1)
        // Should sort by Barrel% since that's the first available priority metric
        XCTAssertEqual(vm.currentSortMetric, "Barrel%")
        XCTAssertEqual(vm.leaderboard.first?.playerId, 1)
    }

    @MainActor
    func testSeasonPlayersReturnsPlayersForSelectedSeason() async {
        // Create players with different seasons
        let player2025 = Player(
            playerId: 1, name: "Player 2025", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )
        let player2024 = Player(
            playerId: 2, name: "Player 2024", team: "BOS", position: "1B", handedness: "L/R", imageURL: nil,
            updatedAt: Date(), season: 2024, metrics: [], standardStats: [], games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [player2025, player2024]))
        await vm.load()

        // Set season to 2025
        vm.selectedSeason = 2025
        XCTAssertEqual(vm.seasonPlayers.count, 1)
        XCTAssertEqual(vm.seasonPlayers.first?.playerId, 1)

        // Set season to 2024
        vm.selectedSeason = 2024
        XCTAssertEqual(vm.seasonPlayers.count, 1)
        XCTAssertEqual(vm.seasonPlayers.first?.playerId, 2)
    }

    @MainActor
    func testSeasonPlayersIsEmptyWhenSeasonHasNoData() async {
        // Players only have 2025 data
        let player2025 = Player(
            playerId: 1, name: "Player 2025", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [player2025]))
        await vm.load()

        // Select 2024 which has no data — should report empty (no stale fallback).
        vm.selectedSeason = 2024
        XCTAssertTrue(vm.seasonPlayers.isEmpty)
    }

    @MainActor
    func testLoadSnapsSelectedSeasonToAvailableData() async {
        let currentPlayer = Player(
            playerId: 1, name: "Current", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: StatScoutSeason.current, metrics: [], standardStats: [], games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [currentPlayer]))
        // Selected season has no data at all — load should snap onto the season that does.
        vm.selectedSeason = 2030
        await vm.load()
        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.current)
    }

    @MainActor
    func testLoadSnapsToPastSeasonOnlyWhenUnlocked() async {
        let pastSeason = StatScoutSeason.current - 1
        let pastPlayer = Player(
            playerId: 1, name: "Past", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: pastSeason, metrics: [], standardStats: [], games: []
        )

        // Pro: past seasons are unlocked, so load snaps onto the only season with data.
        let proVM = DashboardViewModel(provider: MockProvider(players: [pastPlayer]))
        proVM.applyProState(true)
        proVM.selectedSeason = 2030
        await proVM.load()
        XCTAssertEqual(proVM.selectedSeason, pastSeason)

        // Free: the only season with data is gated, so load must not silently
        // drop the user onto locked past-season data.
        let freeVM = DashboardViewModel(provider: MockProvider(players: [pastPlayer]))
        freeVM.selectedSeason = 2030
        await freeVM.load()
        XCTAssertNotEqual(freeVM.selectedSeason, pastSeason)
        XCTAssertTrue(freeVM.seasonPlayers.isEmpty)
    }

    @MainActor
    func testSeasonIndicatorCanBeFormatted() async {
        // Test that season can be displayed correctly (no commas, just the year)
        let season: Int = 2026

        // Swift string interpolation should not add commas
        let formatted = "\(season)"
        XCTAssertEqual(formatted, "2026")
        XCTAssertFalse(formatted.contains(","), "Season should not contain comma separators")
    }
}

final class InMemoryPlayerCache: PlayerCaching, @unchecked Sendable {
    private var stored: [Player]
    init(seed: [Player] = []) { self.stored = seed }
    func loadPlayers() throws -> [Player] { stored }
    func savePlayers(_ players: [Player]) throws { stored = players }
}

struct MockProvider: StatcastProviding, @unchecked Sendable {
    let players: [Player]?
    let error: Error?

    init(players: [Player]? = nil, error: Error? = nil) {
        self.players = players
        self.error = error
    }

    func fetchPlayers() async throws -> [Player] {
        if let error { throw error }
        return players ?? []
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        if let error { throw error }
        return (players ?? []).filter { ($0.season ?? 0) < 2026 }
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        if let error { throw error }
        return players ?? []
    }

    func fetchGameLogs(playerId: Int, season: Int) async throws -> [PlayerGameLog] {
        if let error { throw error }
        return []
    }

    func fetchTeamGameLogs(team: String, season: Int, sinceDate: Date) async throws -> [PlayerGameLog] {
        if let error { throw error }
        return []
    }

    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm] {
        if let error { throw error }
        return []
    }
}
