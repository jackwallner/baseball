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
    var selectedSeason: Int = Calendar.current.component(.year, from: Date())

    // Label shown in the sort button - reflects actual metric being used
    var sortLabel: String {
        guard selectedCategory != nil else { return "Overall" }
        // Use the dynamically determined metric, or fall back to generic label
        return currentSortMetricLabel ?? "Avg"
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

    // All available seasons (2015-2026 based on data availability)
    var availableSeasons: [Int] {
        Array(2015...2026).sorted(by: >)
    }

    // Players filtered by selected season - pull from histories to get all years
    var seasonPlayers: [Player] {
        // Get all players for the selected season from histories
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter { $0.season == selectedSeason }
        // If no players found for this season, fall back to the current players list
        guard !allSeasonPlayers.isEmpty else { return players }
        // Remove duplicates by playerId (keep first occurrence)
        var seenIds = Set<Int>()
        return allSeasonPlayers.filter { seenIds.insert($0.playerId).inserted }
    }

    var filteredPlayers: [Player] {
        seasonPlayers.filter { player in
            let matchesSearch = searchText.isEmpty
                || player.name.localizedCaseInsensitiveContains(searchText)
                || player.team.localizedCaseInsensitiveContains(searchText)
                || teamFullName(player.team).localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || player.metrics.contains { $0.category == selectedCategory }
            return matchesSearch && matchesCategory
        }
    }

    // The metric label currently used for sorting all players (determined by availability)
    private var currentSortMetricLabel: String?

    // Baseball Savant-style sorting: use consistent key metric for ALL players
    var leaderboard: [Player] {
        // Determine which metric to use based on what's available in the filtered set
        let sortLabel = determineSortMetricLabel()
        currentSortMetricLabel = sortLabel

        return filteredPlayers.sorted { p1, p2 in
            let p1Score = playerSortScore(player: p1, metricLabel: sortLabel)
            let p2Score = playerSortScore(player: p2, metricLabel: sortLabel)
            return sortDescending ? p1Score > p2Score : p1Score < p2Score
        }
    }

    // Determine which metric label to use for consistent sorting across all players
    private func determineSortMetricLabel() -> String? {
        guard let category = selectedCategory else { return nil }

        // Find the first priority metric that ANY player in the filtered set has
        for metricLabel in priorityMetrics(for: category) {
            let hasMetric = filteredPlayers.contains { player in
                player.metrics.contains { $0.label == metricLabel && $0.category == category }
            }
            if hasMetric {
                return metricLabel
            }
        }
        return nil
    }

    // Get the sort score for a player using a specific metric label
    private func playerSortScore(player: Player, metricLabel: String?) -> Int {
        guard let category = selectedCategory else {
            return player.overallPercentile
        }
        guard let label = metricLabel else {
            return player.percentile(for: category) ?? player.overallPercentile
        }

        // Use the specific metric if available, otherwise fall back
        if let metric = player.metrics.first(where: { $0.label == label && $0.category == category }) {
            return metric.percentile
        }
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
            // Backend uses "Range (OAA)" as the label
            return ["Range (OAA)", "Arm Strength", "Arm Value"]
        case .running:
            return ["Sprint Speed"]
        }
    }

    // Expose the current sort metric for row display
    var currentSortMetricForDisplay: (label: String?, category: MetricCategory?) {
        (currentSortMetricLabel, selectedCategory)
    }

    var allTeams: [String] {
        Array(Set(seasonPlayers.map { normalizedTeamAbbreviation($0.team) })).sorted()
    }

    func players(forTeam team: String) -> [Player] {
        let normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { $0.overallPercentile > $1.overallPercentile }
    }

    var allMetrics: [(label: String, category: MetricCategory, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)] = []

    private func updateAllMetrics() {
        var metricMap: [String: (category: MetricCategory, values: [(player: Player, value: Int)])] = [:]
        for player in seasonPlayers {
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
        teamCounts = Dictionary(grouping: seasonPlayers) { normalizedTeamAbbreviation($0.team) }
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
