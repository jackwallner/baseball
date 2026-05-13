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
    // Defaults to current year, but `load()` will reset to the most recent season
    // that actually has data once the cache/network resolves so first paint isn't an empty state.
    var selectedSeason: Int = Calendar.current.component(.year, from: Date())
    // User-selected sort metric per category. Overrides the auto-priority pick when present
    // and still valid for the current season's data.
    var userSortMetricByCategory: [MetricCategory: String] = [:]

    // Label shown in the sort button - reflects actual metric being used
    var sortLabel: String {
        guard selectedCategory != nil else { return "xwOBA" }
        return currentSortMetric ?? "Top Category"
    }

    // Resolved sort metric: user override (if still available) or auto-priority pick.
    var currentSortMetric: String? {
        guard let category = selectedCategory else { return nil }
        if let user = userSortMetricByCategory[category],
           availableSortMetrics.contains(user) {
            return user
        }
        return determineSortMetricLabel()
    }

    // All metric labels available for the current category, priority metrics first.
    var availableSortMetrics: [String] {
        guard let category = selectedCategory else { return [] }
        var allLabels = Set<String>()
        for player in seasonPlayers {
            for metric in player.metrics where metric.category == category {
                allLabels.insert(metric.label)
            }
        }
        var seen = Set<String>()
        var ordered: [String] = []
        for label in priorityMetrics(for: category) where allLabels.contains(label) {
            if seen.insert(label).inserted {
                ordered.append(label)
            }
        }
        for label in allLabels.sorted() where seen.insert(label).inserted {
            ordered.append(label)
        }
        return ordered
    }

    func setUserSortMetric(_ label: String?) {
        guard let category = selectedCategory else { return }
        if let label {
            userSortMetricByCategory[category] = label
        } else {
            userSortMetricByCategory.removeValue(forKey: category)
        }
    }
    // Start true so the very first frame shows a spinner, not a "No data for 2026" empty state
    // before saved players or the network feed resolves.
    var isLoading = true
    var isHistoricalLoading = false
    var hasLoadedHistorical = false
    var loadingMessage = "Starting up…"
    var loadingProgress = 0.05
    var errorMessage: String?
    var lastFetchFailed = false
    private var hasStartedLoading = false

    var isReady: Bool { !players.isEmpty }

    private var _teamScores: [String: Double] = [:]
    private var _teamsWithData: [String] = []
    private var _teamCacheSeason: Int?

    var teamScores: [String: Double] {
        if _teamCacheSeason != selectedSeason { recomputeTeamCache() }
        return _teamScores
    }

    var teamsWithData: [String] {
        if _teamCacheSeason != selectedSeason { recomputeTeamCache() }
        return _teamsWithData
    }

    var teamCounts: [String: Int] {
        Dictionary(grouping: seasonPlayers) { normalizedTeamAbbreviation($0.team) }
            .mapValues(\.count)
    }

    var lastUpdated: Date? {
        players.map(\.updatedAt).max()
    }

    var freshnessText: String? {
        guard let lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    init(provider: StatcastProviding, cache: PlayerCaching? = nil) {
        self.provider = provider
        self.cache = cache
    }

    #if DEBUG
    convenience init() {
        self.init(provider: PreviewStatcastAPI())
    }
    #endif

    // Seasons present in fetched data, descending. Falls back to the current year while loading.
    var availableSeasons: [Int] {
        let seasons = Set(playerHistories.values.flatMap { $0 }.compactMap(\.season))
        guard !seasons.isEmpty else {
            return [Calendar.current.component(.year, from: Date())]
        }
        return seasons.sorted(by: >)
    }

    // Players filtered by selected season - pull from histories to get all years.
    // Returns empty when the selected season has no data so callers render an empty state
    // instead of falling back to a stale "latest snapshot" set.
    var seasonPlayers: [Player] {
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter { $0.season == selectedSeason }
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
            let matchesType = player.matchesPlayerType(for: selectedCategory)
            let qualifies = isQualified(player, for: selectedCategory)
            return matchesSearch && matchesCategory && matchesType && qualifies
        }
    }

    enum QualifierLevel: String, CaseIterable, Identifiable {
        case all = "All"
        case any = "Any PA/IP"
        case qualified = "Qualified"

        var id: String { rawValue }

        var minPA: Int {
            switch self {
            case .all: return 0
            case .any: return 10
            case .qualified: return 50
            }
        }

        var minIP: Double {
            switch self {
            case .all: return 0
            case .any: return 5
            case .qualified: return 20
            }
        }
    }

    var qualifierLevel: QualifierLevel = .qualified

    var minPlateAppearances: Int { qualifierLevel.minPA }
    var minInningsPitched: Double { qualifierLevel.minIP }

    func isQualified(_ player: Player, for category: MetricCategory?) -> Bool {
        guard qualifierLevel != .all else { return true }
        let stats = player.standardStats ?? []
        switch category {
        case .pitching:
            return ipValue(in: stats) >= minInningsPitched
        case .hitting, .running, .none:
            if player.playerType == "pitcher" {
                return ipValue(in: stats) >= minInningsPitched
            }
            return paValue(in: stats) >= minPlateAppearances
        case .fielding:
            return paValue(in: stats) >= minPlateAppearances
                || ipValue(in: stats) >= minInningsPitched
        }
    }

    private func paValue(in stats: [StandardStat]) -> Int {
        guard let stat = stats.first(where: { Self.paLabels.contains($0.label.uppercased()) }) else { return 0 }
        return Int(stat.value.filter { $0.isNumber }) ?? 0
    }

    private func ipValue(in stats: [StandardStat]) -> Double {
        guard let stat = stats.first(where: { Self.ipLabels.contains($0.label.uppercased()) }) else { return 0 }
        return Double(stat.value.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static let paLabels: Set<String> = ["PA", "AB"]
    private static let ipLabels: Set<String> = ["IP"]

    // Baseball Savant-style sorting: use consistent key metric for ALL players
    var leaderboard: [Player] {
        let sortLabel = currentSortMetric
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
            return player.metrics.first(where: { $0.label == "xwOBA" })?.percentile ?? 0
        }
        guard let label = metricLabel else {
            return player.percentile(for: category) ?? 0
        }

        // Use the specific metric if available, otherwise fall back
        if let metric = player.metrics.first(where: { $0.label == label && $0.category == category }) {
            return metric.percentile
        }
        return player.percentile(for: category) ?? 0
    }

    // Baseball Savant priority metrics for each category
    private func priorityMetrics(for category: MetricCategory) -> [String] {
        switch category {
        case .hitting:
            return ["xwOBA", "xSLG", "xBA"]
        case .pitching:
            // xwOBA against parallels the hitter xwOBA — it folds in K/BB and contact quality,
            // so it's the right primary rank. xERA has a 25 PA minimum, so it stays out.
            return ["xwOBA", "K%", "Barrel%", "Whiff%", "Chase%"]
        case .fielding:
            // Backend uses "Range (OAA)" as the label
            return ["Range (OAA)", "Arm Strength", "Arm Value"]
        case .running:
            return ["Sprint Speed"]
        }
    }

    // Expose the current sort metric for row display
    var currentSortMetricForDisplay: (label: String?, category: MetricCategory?) {
        (currentSortMetric, selectedCategory)
    }

    func players(forTeam team: String) -> [Player] {
        let normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { p0, p1 in
                let s0 = p0.metrics.first(where: { $0.label == "xwOBA" })?.percentile ?? 0
                let s1 = p1.metrics.first(where: { $0.label == "xwOBA" })?.percentile ?? 0
                return s0 > s1
            }
    }

    func teamScore(_ abbr: String) -> Double {
        _teamScores[normalizedTeamAbbreviation(abbr)] ?? 0
    }

    /// Players who meet the active qualifier for at least one category they appear in.
    /// Used to filter the StatScout leaders and Box Score so unqualified samples don't pollute results.
    var qualifiedSeasonPlayers: [Player] {
        seasonPlayers.filter { player in
            let categories = Set(player.metrics.map(\.category))
            if categories.isEmpty { return isQualified(player, for: nil) }
            return categories.contains { isQualified(player, for: $0) }
        }
    }

    var allMetrics: [(label: String, category: MetricCategory, best: (player: Player, percentile: Int, actualValue: String)?, worst: (player: Player, percentile: Int, actualValue: String)?)] {
        var metricMap: [String: (category: MetricCategory, values: [(player: Player, percentile: Int, actualValue: String)])] = [:]
        for player in seasonPlayers {
            for metric in player.metrics {
                guard isQualified(player, for: metric.category) else { continue }
                let compositeKey = "\(metric.label)|\(metric.category.rawValue)"
                if metricMap[compositeKey] == nil {
                    metricMap[compositeKey] = (category: metric.category, values: [])
                }
                metricMap[compositeKey]?.values.append((player: player, percentile: metric.percentile, actualValue: metric.value))
            }
        }
        return metricMap.map { (key, data) in
            let sorted = data.values.sorted { $0.percentile > $1.percentile }
            let label = key.split(separator: "|").first.map(String.init) ?? key
            return (
                label: label,
                category: data.category,
                best: sorted.first,
                worst: sorted.last
            )
        }.sorted { $0.label < $1.label }
    }

    func loadIfNeeded() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        await load()
    }

    func load() async {
        hasStartedLoading = true
        isLoading = players.isEmpty
        loadingMessage = players.isEmpty ? "Loading saved players…" : "Refreshing player data…"
        loadingProgress = players.isEmpty ? 0.12 : 0.2

        let cached: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return (try? cache.loadCurrentPlayers()) ?? []
            }
            return (try? cache?.loadPlayers()) ?? []
        }.value

        if players.isEmpty, !cached.isEmpty {
            ingestPlayers(cached)
        }

        loadingMessage = "Checking for updates…"
        loadingProgress = 0.45
        isLoading = players.isEmpty
        errorMessage = nil
        lastFetchFailed = false

        do {
            let current = try await provider.fetchCurrentPlayers()
            let fallbackPlayers = cached.isEmpty ? playerHistories.values.flatMap { $0 } : cached
            let allPlayers = current.isEmpty ? fallbackPlayers : mergePlayers(replacing: current)

            guard !allPlayers.isEmpty else {
                errorMessage = "No players found."
                lastFetchFailed = true
                isLoading = false
                loadingProgress = 1
                return
            }

            loadingMessage = "Preparing leaderboard…"
            loadingProgress = 0.85
            ingestPlayers(allPlayers)
            try? cache?.savePlayers(current)

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
        loadingProgress = 1
    }

    func loadHistoricalIfNeeded() async {
        guard !hasLoadedHistorical, !isHistoricalLoading else { return }
        isHistoricalLoading = true
        loadingMessage = "Loading past seasons…"
        loadingProgress = 0.12

        let historical: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return cache.loadHistoricalPlayers()
            }
            return ((try? cache?.loadPlayers()) ?? []).filter { ($0.season ?? 0) < 2026 }
        }.value

        loadingMessage = "Preparing season history…"
        loadingProgress = 0.78

        if !historical.isEmpty {
            ingestPlayers(mergePlayers(replacing: historical))
            hasLoadedHistorical = true
        }

        isHistoricalLoading = false
        loadingProgress = 1
    }

    private func ingestPlayers(_ players: [Player]) {
        let grouped = Dictionary(grouping: players, by: \.playerId)
        var latestPlayers: [Player] = []
        var histories: [Int: [Player]] = [:]

        for (playerId, history) in grouped {
            let sortedHistory = history.sorted {
                guard let s1 = $0.season, let s2 = $1.season else {
                    if $0.season == nil && $1.season == nil { return false }
                    return $0.season != nil
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

        let seasonsWithData = Set(histories.values.flatMap { $0 }.compactMap(\.season))
        if !seasonsWithData.contains(selectedSeason),
           let mostRecent = seasonsWithData.sorted(by: >).first {
            selectedSeason = mostRecent
        }

        recomputeTeamCache()
    }

    private func recomputeTeamCache() {
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter { $0.season == selectedSeason }
        var seenIds = Set<Int>()
        let uniquePlayers = allSeasonPlayers.filter { seenIds.insert($0.playerId).inserted }

        var teams = Set<String>()
        var teamScoresAccum: [String: (sum: Int, count: Int)] = [:]

        for player in uniquePlayers {
            let abbr = normalizedTeamAbbreviation(player.team)
            teams.insert(abbr)
            if let score = player.metrics.first(where: { $0.label == "xwOBA" })?.percentile {
                var entry = teamScoresAccum[abbr] ?? (0, 0)
                entry.sum += score
                entry.count += 1
                teamScoresAccum[abbr] = entry
            }
        }

        _teamsWithData = teams.sorted()
        _teamScores = teamScoresAccum.mapValues { Double($0.sum) / Double($0.count) }
        _teamCacheSeason = selectedSeason
    }

    private func mergePlayers(replacing replacements: [Player]) -> [Player] {
        var merged: [String: Player] = [:]
        for player in playerHistories.values.flatMap({ $0 }) {
            merged[player.id] = player
        }
        for player in replacements {
            merged[player.id] = player
        }
        return Array(merged.values)
    }
}
