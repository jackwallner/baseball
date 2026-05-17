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
    var selectedCategory: MetricCategory? = .hitting {
        didSet {
            if oldValue != selectedCategory { applyDefaultSortDirection() }
        }
    }
    // Tracks whether the user has manually flipped direction since the last
    // metric/category change. When nil, sortDescending follows the metric's
    // default ("best first"); once toggled it pins until the user switches
    // metric or category again.
    private var userToggledDirection = false
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
        applyDefaultSortDirection()
    }

    /// Call when the user explicitly flips direction (header tap / menu item)
    /// so the auto-default doesn't stomp their preference until they change
    /// the active metric or category.
    func toggleSortDirection() {
        sortDescending.toggle()
        userToggledDirection = true
    }

    /// Reset direction to "best first" for the active metric. Triggered by
    /// category changes and by picking a new sort metric — but only when the
    /// user hasn't manually pinned a direction in this session.
    private func applyDefaultSortDirection() {
        userToggledDirection = false
        sortDescending = Self.defaultSortDescending(label: currentSortMetric, category: selectedCategory)
    }
    // Mirrors StoreService.isPro. Set by the view layer so season gating and
    // selectedSeason clamping stay consistent without the VM depending on the store.
    var isPro: Bool = false

    func isSeasonLocked(_ season: Int) -> Bool {
        !isPro && season != StatScoutSeason.free
    }

    /// Push Pro state in from the view and re-clamp the selected season so a free
    /// user can never land on (and silently render) a locked past season.
    func applyProState(_ pro: Bool) {
        isPro = pro
        clampSelectedSeason()
    }

    private func clampSelectedSeason() {
        guard isSeasonLocked(selectedSeason) else { return }
        let target = availableSeasons.first(where: { !isSeasonLocked($0) }) ?? StatScoutSeason.free
        if selectedSeason != target { selectedSeason = target }
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
        case any = "Min Sample"
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

        /// Short caption explaining the active threshold. Shown next to the picker
        /// so "All" and "Min Sample" don't look like synonyms.
        var description: String {
            switch self {
            case .all: return "No minimum"
            case .any: return "10+ PA / 5+ IP"
            case .qualified: return "Savant qualifier"
            }
        }
    }

    var qualifierLevel: QualifierLevel = .qualified

    var minPlateAppearances: Int { qualifierLevel.minPA }
    var minInningsPitched: Double { qualifierLevel.minIP }

    func isQualified(_ player: Player, for category: MetricCategory?) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            // Savant only assigns percentiles to players who meet its qualification thresholds,
            // so "has a percentile in this category" is the authoritative signal.
            if let category {
                return player.metrics.contains { $0.category == category }
            }
            return !player.metrics.isEmpty
        case .any:
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

    // Sort by the raw stat value, not the percentile — percentile-sorting
    // produced ties (two players at 95) and made the "PCTL" header look
    // disconnected from the xwOBA values shown per row. Players missing the
    // exact metric are partitioned to the end so blank-value rows never
    // interleave above genuinely-ranked players.
    var leaderboard: [Player] {
        let sortLabel = currentSortMetric
        guard let category = selectedCategory, let label = sortLabel else {
            return filteredPlayers.sorted { p1, p2 in
                let v1 = Self.rawNumeric(p1.metrics.first(where: { $0.label == "xwOBA" })?.value ?? "") ?? -.infinity
                let v2 = Self.rawNumeric(p2.metrics.first(where: { $0.label == "xwOBA" })?.value ?? "") ?? -.infinity
                return sortDescending ? v1 > v2 : v1 < v2
            }
        }

        func rawValue(_ p: Player) -> Double? {
            guard let m = p.metrics.first(where: { $0.label == label && $0.category == category }) else { return nil }
            return Self.rawNumeric(m.value)
        }

        let ranked = filteredPlayers.filter { rawValue($0) != nil }
            .sorted { p1, p2 in
                let v1 = rawValue(p1) ?? 0
                let v2 = rawValue(p2) ?? 0
                return sortDescending ? v1 > v2 : v1 < v2
            }
        let tail = filteredPlayers.filter { rawValue($0) == nil }
            .sorted { (p1, p2) in
                (p1.percentile(for: category) ?? 0) > (p2.percentile(for: category) ?? 0)
            }
        return ranked + tail
    }

    /// Parse a leading numeric value from a metric's display string.
    /// Handles ".345", "8.2%", "98.5 mph", "28.5 ft/s", "25.3°", "-1.2".
    static func rawNumeric(_ value: String) -> Double? {
        var s = value.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix(".") { s = "0" + s }
        if s.hasPrefix("-.") { s = "-0" + s.dropFirst() }
        let scanner = Scanner(string: s)
        scanner.charactersToBeSkipped = nil
        return scanner.scanDouble()
    }

    /// Metrics where a lower raw value is the better outcome. Drives the
    /// default sort direction (so pitcher xwOBA lists best pitchers first
    /// instead of worst) and Best/Lowest selection on MetricLeadersView.
    /// Hitter xwOBA / Barrel% high = good; pitcher xwOBA / Barrel% low = good.
    static func lowerIsBetter(label: String, category: MetricCategory) -> Bool {
        switch category {
        case .pitching:
            return ["xwOBA", "xBA", "xSLG", "xERA", "ERA", "WHIP", "BB%",
                    "Barrel%", "HardHit%", "EV", "LA", "GB%", "FB%"].contains(label)
        case .hitting:
            return ["K%"].contains(label)
        case .fielding, .running:
            return false
        }
    }

    /// Default sort direction for a metric — descending (highest first) unless
    /// the metric reads better when lower. Used to keep "best player first" as
    /// the initial ordering even after switching to raw-value sorting.
    static func defaultSortDescending(label: String?, category: MetricCategory?) -> Bool {
        guard let label, let category else { return true }
        return !lowerIsBetter(label: label, category: category)
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
        // Sort by raw xwOBA value to match the leaderboard convention.
        // Pitchers (where lower xwOBA is better) sort to the bottom, then by
        // ascending xwOBA — gives a sane "best hitters first, best pitchers
        // last" team roster ordering.
        let normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { p0, p1 in
                let isPitcher0 = p0.playerType?.lowercased() == "pitcher"
                let isPitcher1 = p1.playerType?.lowercased() == "pitcher"
                if isPitcher0 != isPitcher1 { return !isPitcher0 }
                let v0 = Self.rawNumeric(p0.metrics.first(where: { $0.label == "xwOBA" })?.value ?? "") ?? -.infinity
                let v1 = Self.rawNumeric(p1.metrics.first(where: { $0.label == "xwOBA" })?.value ?? "") ?? -.infinity
                return isPitcher0 ? v0 < v1 : v0 > v1
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
            let label = key.split(separator: "|").first.map(String.init) ?? key
            // Rank Best/Lowest by raw value with direction awareness so
            // "Lowest" actually means "worst" for the metric — pitcher xwOBA
            // best = lowest raw value, hitter xwOBA best = highest.
            let lowerBetter = Self.lowerIsBetter(label: label, category: data.category)
            let ascending = data.values.sorted { lhs, rhs in
                let a = Self.rawNumeric(lhs.actualValue) ?? 0
                let b = Self.rawNumeric(rhs.actualValue) ?? 0
                return a < b
            }
            let best = lowerBetter ? ascending.first : ascending.last
            let worst = lowerBetter ? ascending.last : ascending.first
            return (
                label: label,
                category: data.category,
                best: best,
                worst: worst
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
                // No current data (offseason / cold cache / offline). Fall back to
                // bundled historical so the app is usable instead of trapped on an
                // empty state; season gating still applies via isSeasonLocked.
                let historicalFallback: [Player] = await Task.detached { [cache] in
                    if let cache = cache as? TwoTierPlayerCache {
                        return cache.loadHistoricalPlayers()
                    }
                    return (try? cache?.loadPlayers()) ?? []
                }.value
                if !historicalFallback.isEmpty {
                    ingestPlayers(historicalFallback)
                } else {
                    errorMessage = "No players found."
                    lastFetchFailed = true
                }
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
           let mostRecentUnlocked = seasonsWithData.sorted(by: >).first(where: { !isSeasonLocked($0) }) {
            // Only auto-jump to a season the user can actually view; a free user
            // with no current-season data stays on the free season (honest empty
            // state) rather than silently rendering locked past-season data.
            selectedSeason = mostRecentUnlocked
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
