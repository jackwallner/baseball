import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let provider: StatcastProviding

    var players: [Player] = []
    var searchText = ""
    var selectedCategory: MetricCategory? = nil
    var isLoading = false
    var errorMessage: String?

    var lastUpdated: Date {
        players.map(\.updatedAt).max() ?? Date()
    }

    init(provider: StatcastProviding = PreviewStatcastAPI()) {
        self.provider = provider
    }

    var searchIsTeamQuery: Bool {
        let teams = Set(players.map(\.team))
        return teams.contains(searchText.uppercased())
    }

    var filteredPlayers: [Player] {
        players.filter { player in
            let matchesSearch = searchText.isEmpty || player.name.localizedCaseInsensitiveContains(searchText) || player.team.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || player.metrics.contains { $0.category == selectedCategory }
            return matchesSearch && matchesCategory
        }
    }

    var leaderboard: [Player] {
        filteredPlayers.sorted { $0.overallPercentile > $1.overallPercentile }
    }

    var featuredPlayers: [Player] {
        Array(leaderboard.prefix(5))
    }

    var randomPlayer: Player? {
        players.randomElement()
    }

    var allTeams: [String] {
        Array(Set(players.map(\.team))).sorted()
    }

    func players(forTeam team: String) -> [Player] {
        players.filter { $0.team == team }.sorted { $0.overallPercentile > $1.overallPercentile }
    }

    var allMetrics: [(label: String, category: MetricCategory, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)] {
        var metricMap: [String: (category: MetricCategory, values: [(player: Player, value: Int)])] = [:]
        for player in players {
            for metric in player.metrics {
                if metricMap[metric.label] == nil {
                    metricMap[metric.label] = (category: metric.category, values: [])
                }
                metricMap[metric.label]?.values.append((player: player, value: metric.percentile))
            }
        }
        return metricMap.map { (label, data) in
            let sorted = data.values.sorted { $0.value > $1.value }
            return (
                label: label,
                category: data.category,
                best: sorted.first,
                worst: sorted.last
            )
        }.sorted { $0.label < $1.label }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            players = try await provider.fetchPlayers()
        } catch {
            errorMessage = "Using sample data until the nightly feed is connected."
            players = SampleData.players
        }
        isLoading = false
    }
}
