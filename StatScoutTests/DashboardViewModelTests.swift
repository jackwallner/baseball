import XCTest
@testable import Baseball_Savvy_StatScout

final class DashboardViewModelTests: XCTestCase {
    @MainActor
    func testAllMetricsKeyCollision() async throws {
        let players: [Player] = [
            Player(
                id: 1, name: "A", team: "NYY", position: "DH", handedness: "L/R", imageURL: nil,
                updatedAt: Date(),
                metrics: [
                    Metric(id: "m1", label: "xwOBA", value: ".400", percentile: 90, category: .hitting)
                ],
                standardStats: [],
                games: []
            ),
            Player(
                id: 2, name: "B", team: "NYY", position: "SP", handedness: "R/R", imageURL: nil,
                updatedAt: Date(),
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
    func testSearchMatchesFullTeamName() async {
        let player = Player(
            id: 1, name: "Aaron Judge", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(),
            metrics: [],
            standardStats: [],
            games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [player]))
        await vm.load()
        vm.searchText = "Yankees"

        XCTAssertEqual(vm.filteredPlayers.map(\.id), [1])
    }

    @MainActor
    func testPlayersForTeamMatchesAliases() async {
        let players = [
            Player(
                id: 1, name: "A", team: "New York Yankees", position: "RF", handedness: "R/R", imageURL: nil,
                updatedAt: Date(),
                metrics: [],
                standardStats: [],
                games: []
            ),
            Player(
                id: 2, name: "B", team: "CHW", position: "1B", handedness: "L/R", imageURL: nil,
                updatedAt: Date(),
                metrics: [],
                standardStats: [],
                games: []
            )
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        await vm.load()

        XCTAssertEqual(vm.players(forTeam: "NYY").map(\.id), [1])
        XCTAssertEqual(vm.players(forTeam: "CWS").map(\.id), [2])
    }

    @MainActor
    func testTeamCountsPopulatedAfterLoad() async {
        let players = [
            Player(id: 1, name: "A", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil, updatedAt: Date(), metrics: [], standardStats: [], games: []),
            Player(id: 2, name: "B", team: "NYY", position: "1B", handedness: "L/R", imageURL: nil, updatedAt: Date(), metrics: [], standardStats: [], games: []),
            Player(id: 3, name: "C", team: "BOS", position: "SS", handedness: "R/R", imageURL: nil, updatedAt: Date(), metrics: [], standardStats: [], games: [])
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        await vm.load()
        XCTAssertEqual(vm.teamCounts["NYY"], 2)
        XCTAssertEqual(vm.teamCounts["BOS"], 1)
    }

    @MainActor
    func testCacheHydratesPlayersBeforeFetch() async {
        let cached = [
            Player(id: 99, name: "Cached", team: "NYY", position: "DH", handedness: "L/R", imageURL: nil, updatedAt: Date(), metrics: [], standardStats: [], games: [])
        ]
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = DashboardViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)), cache: cache)
        await vm.load()
        XCTAssertEqual(vm.players.map(\.id), [99], "Cached players should be shown even when refresh fails")
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
