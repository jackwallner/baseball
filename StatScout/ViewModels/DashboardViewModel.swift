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

    init(provider: StatcastProviding = PreviewStatcastAPI()) {
        self.provider = provider
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
