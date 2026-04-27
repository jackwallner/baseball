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
    var lastFetchFailed = false

    var lastUpdated: Date? {
        players.map(\.updatedAt).max()
    }

    init(provider: StatcastProviding = PreviewStatcastAPI()) {
        self.provider = provider
    }

    var filteredPlayers: [Player] {
        players.filter { player in
            let matchesSearch = searchText.isEmpty
                || player.name.localizedCaseInsensitiveContains(searchText)
                || player.team.localizedCaseInsensitiveContains(searchText)
                || teamFullName(player.team).localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || player.metrics.contains { $0.category == selectedCategory }
            return matchesSearch && matchesCategory
        }
    }

    var leaderboard: [Player] {
        filteredPlayers.sorted { $0.overallPercentile > $1.overallPercentile }
    }

    var biggestRisers: [Player] {
        players.filter { $0.weeklyDelta > 0 }
            .sorted { $0.weeklyDelta > $1.weeklyDelta }
            .prefix(3)
            .map { $0 }
    }

    var biggestFallers: [Player] {
        players.filter { $0.weeklyDelta < 0 }
            .sorted { $0.weeklyDelta < $1.weeklyDelta }
            .prefix(3)
            .map { $0 }
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
                let compositeKey = "\(metric.label)|\(metric.category.rawValue)"
                if metricMap[compositeKey] == nil {
                    metricMap[compositeKey] = (category: metric.category, values: [])
                }
                metricMap[compositeKey]?.values.append((player: player, value: metric.percentile))
            }
        }
        return metricMap.map { (key, data) in
            let sorted = data.values.sorted { $0.value > $1.value }
            let label = key.split(separator: "|").first.map(String.init) ?? key
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
        lastFetchFailed = false
        do {
            let fetched = try await provider.fetchPlayers()
            guard !fetched.isEmpty else {
                errorMessage = "No players found for this season."
                lastFetchFailed = true
                #if DEBUG
                players = SampleData.players
                #endif
                return
            }
            players = fetched
        } catch is DecodingError {
            errorMessage = "Data format changed — app may need an update."
            lastFetchFailed = true
            #if DEBUG
            players = SampleData.players
            #endif
        } catch let urlError as URLError {
            errorMessage = "Can't reach data feed. Check your connection."
            lastFetchFailed = true
            #if DEBUG
            players = SampleData.players
            #endif
        } catch {
            errorMessage = "Something went wrong loading player data."
            lastFetchFailed = true
            #if DEBUG
            players = SampleData.players
            #endif
        }
        isLoading = false
    }
}
