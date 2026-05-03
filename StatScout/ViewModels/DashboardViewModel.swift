import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let provider: StatcastProviding
    private let cache: PlayerCaching?

    var players: [Player] = []
    var playerHistories: [Int: [Player]] = [:]
    var searchText = ""
    var selectedCategory: MetricCategory? = .hitting
    var sortDescending = true

    // Label shown in the sort button - reflects primary sort metric
    var sortLabel: String {
        guard let category = selectedCategory else { return "Overall" }
        switch category {
        case .hitting:
            return "xwOBA"
        case .pitching:
            return "Barrel%"  // Most commonly available pitching metric
        case .fielding:
            return "OAA"
        case .running:
            return "Sprint Speed"
        }
    }
    var isLoading = false
    var errorMessage: String?
    var lastFetchFailed = false
    var teamCounts: [String: Int] = [:]

    var lastUpdated: Date? {
        players.map(\.updatedAt).max()
    }

    var freshnessText: String? {
        guard let lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Through \(formatter.string(from: lastUpdated))"
    }

    init(provider: StatcastProviding = PreviewStatcastAPI(), cache: PlayerCaching? = nil) {
        self.provider = provider
        self.cache = cache
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

    // Baseball Savant-style sorting: use key metric for each category
    var leaderboard: [Player] {
        filteredPlayers.sorted { p1, p2 in
            let p1Score = keyMetricPercentile(for: p1)
            let p2Score = keyMetricPercentile(for: p2)
            return sortDescending ? p1Score > p2Score : p1Score < p2Score
        }
    }

    // Get the key metric percentile for sorting - Baseball Savant style
    private func keyMetricPercentile(for player: Player) -> Int {
        guard let category = selectedCategory else {
            return player.overallPercentile
        }

        // Find the first available priority metric for this player
        for metricLabel in priorityMetrics(for: category) {
            if let metric = player.metrics.first(where: { $0.label == metricLabel && $0.category == category }) {
                return metric.percentile
            }
        }

        // Fall back to category average or overall
        return player.percentile(for: category) ?? player.overallPercentile
    }

    // Baseball Savant priority metrics for each category
    private func priorityMetrics(for category: MetricCategory) -> [String] {
        switch category {
        case .hitting:
            return ["xwOBA", "xSLG", "xBA"]
        case .pitching:
            // xERA has minimum thresholds (25 PA) - use more commonly available metrics first
            return ["Barrel%", "xwOBA", "K%", "Whiff%", "Chase%"]
        case .fielding:
            return ["OAA", "Range (OAA)", "Arm Strength"]
        case .running:
            return ["Sprint Speed"]
        }
    }

    // Returns the actual metric being used for sorting (for display purposes)
    func actualSortMetric(for player: Player? = nil) -> String {
        guard let category = selectedCategory else { return "Overall" }

        // If we have a specific player, show what metric THEY are sorted by
        if let player = player {
            for metricLabel in priorityMetrics(for: category) {
                if player.metrics.contains(where: { $0.label == metricLabel && $0.category == category }) {
                    return metricLabel
                }
            }
            return "Pitching Avg"  // Fallback for pitchers
        }

        // Default label shows first priority metric
        let priorities = priorityMetrics(for: category)
        return priorities.first ?? "Overall"
    }

    var allTeams: [String] {
        Array(Set(players.map { normalizedTeamAbbreviation($0.team) })).sorted()
    }

    func players(forTeam team: String) -> [Player] {
        let normalized = normalizedTeamAbbreviation(team)
        return players.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { $0.overallPercentile > $1.overallPercentile }
    }

    var allMetrics: [(label: String, category: MetricCategory, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)] = []

    private func updateAllMetrics() {
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
        allMetrics = metricMap.map { (key, data) in
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

    private func updateDerivedState() {
        updateAllMetrics()
        teamCounts = Dictionary(grouping: players) { normalizedTeamAbbreviation($0.team) }
            .mapValues(\.count)
    }

    func load() async {
        if players.isEmpty, let cached = try? cache?.loadPlayers(), !cached.isEmpty {
            players = cached
            updateDerivedState()
        }
        isLoading = players.isEmpty
        errorMessage = nil
        lastFetchFailed = false
        do {
            let fetched = try await provider.fetchPlayers()
            guard !fetched.isEmpty else {
                errorMessage = "No players found for this season."
                lastFetchFailed = true
                isLoading = false
                return
            }

            let grouped = Dictionary(grouping: fetched, by: \.playerId)
            var latestPlayers: [Player] = []
            var histories: [Int: [Player]] = [:]

            for (playerId, history) in grouped {
                // Sort by season descending, with nil seasons at the end
                let sortedHistory = history.sorted {
                    guard let s1 = $0.season, let s2 = $1.season else {
                        // If both nil, keep original order; if one nil, put it last
                        if $0.season == nil && $1.season == nil { return false }
                        return $0.season != nil // non-nil comes first
                    }
                    return s1 > s2
                }
                histories[playerId] = sortedHistory
                if let latest = sortedHistory.first {
                    latestPlayers.append(latest)
                }
            }

            self.playerHistories = histories
            self.players = latestPlayers

            updateDerivedState()
            try? cache?.savePlayers(fetched)
        } catch is DecodingError {
            errorMessage = "Data format changed — app may need an update."
            lastFetchFailed = true
        } catch _ as URLError {
            errorMessage = players.isEmpty ? "Can't reach data feed. Check your connection." : "Showing saved data. Pull to refresh when your connection improves."
            lastFetchFailed = true
        } catch {
            errorMessage = players.isEmpty ? "Something went wrong loading player data." : "Showing saved data. Pull to refresh to try again."
            lastFetchFailed = true
        }
        isLoading = false
    }
}
