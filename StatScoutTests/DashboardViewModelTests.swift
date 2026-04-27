import XCTest
@testable import StatScout

final class DashboardViewModelTests: XCTestCase {
    @MainActor
    func testAllMetricsKeyCollision() async throws {
        let players: [Player] = [
            Player(
                id: 1, name: "A", team: "NYY", position: "DH", handedness: "L/R", imageURL: nil,
                updatedAt: Date(),
                metrics: [
                    Metric(id: "m1", label: "xwOBA", value: ".400", percentile: 90, direction: .flat, category: .hitting)
                ],
                games: []
            ),
            Player(
                id: 2, name: "B", team: "NYY", position: "SP", handedness: "R/R", imageURL: nil,
                updatedAt: Date(),
                metrics: [
                    Metric(id: "m2", label: "xwOBA", value: ".350", percentile: 85, direction: .flat, category: .pitching)
                ],
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
            games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [player]))
        await vm.load()
        vm.searchText = "Yankees"

        XCTAssertEqual(vm.filteredPlayers.map(\.id), [1])
    }

    @MainActor
    func testBiggestMoversOrdering() async {
        let now = Date()
        let players = [
            mover(id: 1, delta: 4, date: now),
            mover(id: 2, delta: 12, date: now),
            mover(id: 3, delta: -7, date: now),
            mover(id: 4, delta: -2, date: now)
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        await vm.load()

        XCTAssertEqual(vm.biggestRisers.map(\.id), [2, 1])
        XCTAssertEqual(vm.biggestFallers.map(\.id), [3, 4])
    }

    private func mover(id: Int, delta: Int, date: Date) -> Player {
        Player(
            id: id, name: "Player \(id)", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: date,
            metrics: [],
            games: [
                GameTrend(id: "\(id)-game", date: date, opponent: "BOS", summary: "", percentileDelta: delta, keyMetric: "xwOBA")
            ]
        )
    }
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
