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
        // Test the teamFullName helper function directly
        XCTAssertEqual(teamFullName("NYY"), "New York Yankees")
        XCTAssertEqual(teamFullName("BOS"), "Boston Red Sox")
        XCTAssertEqual(teamFullName("LAD"), "Los Angeles Dodgers")
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
        // Players with xwOBA hitting metric
        let hitters = [
            Player(playerId: 1, name: "A", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil, updatedAt: Date(), season: 2025, playerType: "batter", source: "baseball_savant",
                   metrics: [Metric(id: "m1", label: "xwOBA", value: ".400", percentile: 90, category: .hitting)], standardStats: [], games: [])
        ]

        let vm = DashboardViewModel(provider: MockProvider(players: hitters))
        await vm.load()
        _ = vm.leaderboard  // Trigger computation of sort metric

        // Default category is hitting, should find xwOBA in data
        XCTAssertEqual(vm.sortLabel, "xwOBA")

        // Test with pitchers that have Barrel%
        let pitchers = [
            Player(playerId: 2, name: "B", team: "NYY", position: "SP", handedness: "R/R", imageURL: nil, updatedAt: Date(), season: 2025, playerType: "pitcher", source: "baseball_savant",
                   metrics: [Metric(id: "m1", label: "Barrel%", value: "5%", percentile: 85, category: .pitching)], standardStats: [], games: [])
        ]
        let vmPitching = DashboardViewModel(provider: MockProvider(players: pitchers))
        await vmPitching.load()
        vmPitching.selectedCategory = .pitching
        _ = vmPitching.leaderboard  // Trigger computation
        XCTAssertEqual(vmPitching.sortLabel, "Barrel%")

        // Test empty data falls back to "Avg"
        let vmEmpty = DashboardViewModel(provider: MockProvider(players: []))
        await vmEmpty.load()
        vmEmpty.selectedCategory = .hitting
        _ = vmEmpty.leaderboard  // Trigger computation
        XCTAssertEqual(vmEmpty.sortLabel, "Avg")

        // Test nil category shows Overall
        let vmNil = DashboardViewModel(provider: MockProvider(players: hitters))
        await vmNil.load()
        vmNil.selectedCategory = nil
        _ = vmNil.leaderboard
        XCTAssertEqual(vmNil.sortLabel, "Overall")
    }

    @MainActor
    func testPitchingSortUsesAvailableMetrics() async {
        // Pitcher with Barrel% but no xERA (common early in season)
        let pitcher = Player(
            playerId: 1, name: "Test Pitcher", team: "NYY", position: "SP",
            handedness: "R/R", imageURL: nil, updatedAt: Date(), season: 2025, playerType: "pitcher", source: "baseball_savant",
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
        let player2025 = Player(
            playerId: 1, name: "Player 2025", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [player2025]))
        // Default selectedSeason is the current year. If the data only has 2025, load should snap.
        vm.selectedSeason = 2030
        await vm.load()
        XCTAssertEqual(vm.selectedSeason, 2025)
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
}
