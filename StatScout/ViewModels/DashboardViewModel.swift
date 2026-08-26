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
    var selectedSeason: Int = Calendar.current.component(.year, from: Date()) {
        didSet {
            guard oldValue != selectedSeason else { return }
            // Past seasons live in the bundled historical cache, which loads
            // lazily. Pull it in on demand so picking a year just works,
            // Pro users used to have to tap a separate "Load past seasons"
            // row first, which read as a bug more than a feature.
            if selectedSeason < StatScoutSeason.current, isPro, !hasLoadedHistorical, !isHistoricalLoading {
                Task { await loadHistoricalIfNeeded() }
            }
        }
    }
    /// Which slate the phase-aware boards are showing.
    ///
    /// Orthogonal to `selectedSeason`, and it never survives leaving the current
    /// season: only the season being played has a postseason the pipeline is
    /// collecting, so landing on a past year has to snap back to the regular
    /// season rather than render an empty playoff board.
    var selectedPhase: SeasonPhase = .regular

    /// The newest postseason game the backend holds, or nil when the playoffs
    /// haven't started (or last night's run hasn't landed them yet).
    ///
    /// Everything postseason keys off this rather than off the calendar. The
    /// pipeline closes out a day once, overnight, so a date-triggered control
    /// would offer a board that is still empty for most of the first day of the
    /// playoffs, which is the one day it most wants to be right.
    var postseasonThrough: Date?

    var postseasonAvailable: Bool { postseasonThrough != nil }

    /// Postseason standard lines, loaded on demand the first time the phase is
    /// switched. Empty `metrics` is not a loading state: Savant publishes no
    /// postseason percentile leaderboards, so these players will never have a
    /// percentile and the boards that rank by one must not offer October.
    var postseasonPlayers: [Player] = []
    var isLoadingPostseason = false
    private var hasLoadedPostseason = false

    func loadPostseasonIfNeeded() async {
        guard postseasonAvailable, !hasLoadedPostseason, !isLoadingPostseason else { return }
        isLoadingPostseason = true
        defer { isLoadingPostseason = false }
        if let players = try? await provider.fetchPostseasonPlayers(season: StatScoutSeason.current) {
            postseasonPlayers = players
            hasLoadedPostseason = true
        }
    }

    /// True when a phase control should appear at all: the postseason exists and
    /// we're looking at the season that has one.
    var offersPhaseChoice: Bool {
        postseasonAvailable && selectedSeason == StatScoutSeason.current
    }

    /// Push a season change through the phase rules. Anything that sets
    /// `selectedSeason` for the user should go through here.
    func selectSeason(_ season: Int) {
        selectedSeason = season
        if season != StatScoutSeason.current { selectedPhase = .regular }
    }

    func selectPhase(_ phase: SeasonPhase) {
        guard phase == .regular || offersPhaseChoice else { return }
        selectedPhase = phase
        if phase == .postseason {
            Task { await loadPostseasonIfNeeded() }
        }
    }

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
    /// category changes and by picking a new sort metric, but only when the
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

    /// The last game day the data actually covers, as opposed to when the rows
    /// were written.
    ///
    /// These come apart whenever Savant publishes a slate late: the overnight
    /// refresh runs, rewrites every row (so `lastUpdated` is today) and closes
    /// out no new games. Settings reported the write stamp alone and so claimed
    /// fresh data while the Trends board correctly said "Through Jul 27".
    var dataThrough: Date?

    var freshnessText: String? {
        guard let lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    /// Fetch per-game logs for a single player. Powers the Recent Form card,
    /// the VM is just a passthrough so the card can stay UI-only and we don't
    /// have to thread the provider through every PlayerProfileView caller.
    /// Game logs for the phase the boards are currently on.
    ///
    /// Phase is read here rather than passed in by each caller so a screen can
    /// never fetch one slate while its heading names the other. Only the season
    /// being played has a postseason, so any other year is regular season
    /// whatever the picker last said.
    func fetchGameLogs(playerId: Int, season: Int) async throws -> [PlayerGameLog] {
        let phase = season == StatScoutSeason.current ? selectedPhase : .regular
        return try await provider.fetchGameLogs(playerId: playerId, season: season, phase: phase)
    }

    /// Team-scoped game logs since `sinceDate`. The TeamRankingsCard caps at 30
    /// days so we don't pull the whole season for an aggregate we only ever
    /// slice into 7/15/30 day windows.
    func fetchTeamGameLogs(team: String, season: Int, sinceDate: Date) async throws -> [PlayerGameLog] {
        try await provider.fetchTeamGameLogs(team: team, season: season, sinceDate: sinceDate)
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

    /// Every season the app can show, newest first, a fixed range, not a
    /// reflection of what's currently loaded.
    ///
    /// This used to derive from `playerHistories`, which only holds the current
    /// season until historical data is explicitly loaded. The effect was that a
    /// free user opened the season picker and saw a single year plus a generic
    /// "past seasons require StatScout+" row: the thing they were being sold
    /// was invisible. Listing the real years and marking the locked ones lets
    /// someone reach for the specific season they came for.
    var availableSeasons: [Int] {
        Array(StatScoutSeason.earliest...StatScoutSeason.current).reversed()
    }

    // Players filtered by selected season - pull from histories to get all years.
    // Returns empty when the selected season has no data so callers render an empty state
    // instead of falling back to a stale "latest snapshot" set.
    var seasonPlayers: [Player] {
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter { $0.season == selectedSeason }
        var seenIds = Set<Int>()
        return allSeasonPlayers.filter { seenIds.insert($0.playerId).inserted }
    }

    // MARK: - Recent form

    /// Rolling windows keyed by length, cached per season so flipping between
    /// 7 / 15 / 30 doesn't refetch what's already in hand.
    var recentFormByWindow: [Int: [Int: RecentForm]] = [:]
    var recentFormLoadingWindows: Set<Int> = []
    var recentFormError: String?
    private var recentFormSeason: Int?
    /// In-flight fetches, keyed by window, owned by the model rather than by
    /// the `.task` that asked for them.
    ///
    /// This is the fix for a Trends board that launched empty and stayed empty.
    /// The old code marked a window "loading" in a `Set` and had every later
    /// caller return early on it. SwiftUI cancels a `.task` whenever its id
    /// changes, and HotColdView's id carries `store.isPro`, which flips as soon
    /// as RevenueCat answers. The replacement task then hit the in-flight guard,
    /// did nothing, and the cancelled one cleared the flag with no data and no
    /// error, so the board had no rows, no spinner and no way back. Because
    /// every tab stays alive in the root ZStack, that `.task` never runs a
    /// second time either: tabbing over ran nothing at all.
    ///
    /// An unstructured `Task` doesn't inherit its creator's cancellation, so
    /// the fetch now outlives whichever view kicked it off, and a second caller
    /// awaits the same task instead of dropping its request on the floor.
    private var recentFormTasks: [Int: Task<Void, Never>] = [:]

    /// The window the Stats leaderboard and trend arrows read from.
    var recentWindow: RecentWindow = .fortnight

    func recentForm(for playerId: Int, window: RecentWindow? = nil) -> RecentForm? {
        recentFormByWindow[(window ?? recentWindow).rawValue]?[playerId]
    }

    var isRecentFormLoading: Bool {
        recentFormLoadingWindows.contains(recentWindow.rawValue)
    }

    /// The last game date covered by the loaded window, for honest labelling.
    var recentFormAsOf: Date? {
        recentFormByWindow[recentWindow.rawValue]?.values.compactMap(\.asOf).max()
    }

    /// The coverage date every cached window was built from.
    private var cachedRecentFormAsOf: Date? {
        recentFormByWindow.values.flatMap(\.values).compactMap(\.asOf).max()
    }

    /// Drops every cached rolling window and refetches the ones that were held.
    ///
    /// The windows are cached for the life of the process, which is fine for a
    /// session but wrong across a refresh: the app spends most of its life
    /// suspended, and coming back after the overnight run left the Trends board
    /// (and its "Through …" header) sitting on yesterday's rollup while the
    /// season line Settings reports had already moved on. That is the whole of
    /// "the Trends side is a day behind".
    private func refreshCachedRecentFormWindows() async {
        let held = Set(recentFormByWindow.keys)
        guard !held.isEmpty else { return }
        for task in recentFormTasks.values { task.cancel() }
        recentFormTasks.removeAll()
        recentFormLoadingWindows.removeAll()
        recentFormByWindow.removeAll()
        for days in held {
            guard let window = RecentWindow(rawValue: days) else { continue }
            await loadRecentFormIfNeeded(window: window)
        }
    }

    /// Drops the cached window and fetches it again. What the Trends board's
    /// "Try Again" calls: `loadRecentFormIfNeeded` returns early on a window
    /// it's already holding, which after a failure is nothing at all.
    func reloadRecentForm(window: RecentWindow? = nil) async {
        let target = window ?? recentWindow
        recentFormTasks[target.rawValue]?.cancel()
        recentFormTasks.removeValue(forKey: target.rawValue)
        recentFormByWindow.removeValue(forKey: target.rawValue)
        recentFormError = nil
        await loadRecentFormIfNeeded(window: target)
    }

    func loadRecentFormIfNeeded(window: RecentWindow? = nil) async {
        let target = window ?? recentWindow
        // Season changed under us, the cache describes a different year.
        if recentFormSeason != selectedSeason {
            for task in recentFormTasks.values { task.cancel() }
            recentFormTasks.removeAll()
            recentFormLoadingWindows.removeAll()
            recentFormByWindow.removeAll()
            recentFormSeason = selectedSeason
        }
        guard recentFormByWindow[target.rawValue] == nil else { return }

        // Join the fetch that's already running rather than returning as if
        // this request had been served. The caller awaits real data either way.
        if let inFlight = recentFormTasks[target.rawValue] {
            await inFlight.value
            return
        }

        recentFormLoadingWindows.insert(target.rawValue)
        recentFormError = nil
        let season = selectedSeason
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.recentFormLoadingWindows.remove(target.rawValue)
                self.recentFormTasks.removeValue(forKey: target.rawValue)
            }
            do {
                let rows = try await self.provider.fetchRecentForm(
                    season: season,
                    windowDays: target.rawValue
                )
                // The season can move under a long fetch (the loader lands on
                // the newest year with data). Dropping a stale answer is better
                // than caching last year's board under this year's key.
                guard season == self.selectedSeason else { return }
                // A two-way player has a row per side; the leaderboard keys by
                // player, so keep whichever side has the larger sample.
                var byPlayer: [Int: RecentForm] = [:]
                for row in rows {
                    if let existing = byPlayer[row.playerId],
                       existing.plateAppearances >= row.plateAppearances { continue }
                    byPlayer[row.playerId] = row
                }
                // An empty answer isn't cached. Early in a season the rollup
                // genuinely has nothing yet, and caching that would pin the
                // board to "no movement" for the rest of the launch.
                guard !byPlayer.isEmpty else { return }
                self.recentFormByWindow[target.rawValue] = byPlayer
                // Keep the Settings coverage line and the Trends "Through …"
                // header reading off the same answer once a window has landed.
                if season == StatScoutSeason.current,
                   let asOf = byPlayer.values.compactMap(\.asOf).max() {
                    self.dataThrough = asOf
                }
            } catch {
                // A window the user has already flipped away from cancels its
                // own fetch. Reporting that as a failure is how tapping quickly
                // around the Trends board produced an error on a board that was
                // fine.
                if !isTaskCancellation(error) {
                    self.recentFormError = "Couldn't load recent form."
                }
            }
        }
        recentFormTasks[target.rawValue] = task
        await task.value
    }

    /// Unique players for an arbitrary season, not just the selected one.
    /// Drill-down leaderboards opened from a player profile need the season
    /// that profile is showing, which can differ from `selectedSeason`.
    func players(forSeason season: Int) -> [Player] {
        let all = playerHistories.values.flatMap { $0 }.filter { $0.season == season }
        var seen = Set<Int>()
        return all.filter { seen.insert($0.playerId).inserted }
    }

    /// Position filter for the hitter / fielder / runner boards.
    ///
    /// "Who are the best hitters" and "who are the best-hitting catchers" are
    /// different questions, and the second is the one a fan comparing his own
    /// team's holes actually asks. Groups sit above the individual spots so the
    /// common ask (infield, outfield) is one tap rather than four.
    enum PositionFilter: String, CaseIterable, Identifiable {
        case all
        case infield
        case outfield
        case catcher = "C"
        case firstBase = "1B"
        case secondBase = "2B"
        case thirdBase = "3B"
        case shortstop = "SS"
        case leftField = "LF"
        case centerField = "CF"
        case rightField = "RF"
        case designatedHitter = "DH"

        var id: String { rawValue }

        /// Short form for the chip; the menu row spells it out.
        var chipLabel: String {
            switch self {
            case .all: return "Pos"
            case .infield: return "IF"
            case .outfield: return "OF"
            default: return rawValue
            }
        }

        var label: String {
            switch self {
            case .all: return "All positions"
            case .infield: return "Infield"
            case .outfield: return "Outfield"
            case .catcher: return "Catcher"
            case .firstBase: return "First base"
            case .secondBase: return "Second base"
            case .thirdBase: return "Third base"
            case .shortstop: return "Shortstop"
            case .leftField: return "Left field"
            case .centerField: return "Center field"
            case .rightField: return "Right field"
            case .designatedHitter: return "Designated hitter"
            }
        }

        /// Position codes this filter accepts. "OF" appears in the outfield set
        /// because a handful of snapshots carry the generic code rather than a
        /// corner.
        var positionCodes: Set<String> {
            switch self {
            case .all: return []
            case .infield: return ["1B", "2B", "3B", "SS"]
            case .outfield: return ["LF", "CF", "RF", "OF"]
            default: return [rawValue]
            }
        }

        func matches(_ player: Player) -> Bool {
            guard self != .all else { return true }
            return positionCodes.contains(
                player.displayPosition.trimmingCharacters(in: .whitespaces).uppercased()
            )
        }
    }

    var positionFilter: PositionFilter = .all

    /// Pitching boards are every-player-is-P, so the control would offer a
    /// single option; it's hidden there and the filter is skipped.
    var positionFilterApplies: Bool { selectedCategory != .pitching }

    /// Only the filters that would leave something on the board, so the menu
    /// can't hand the user an empty list.
    var availablePositionFilters: [PositionFilter] {
        let present = Set(
            seasonPlayers
                .filter { $0.matchesPlayerType(for: selectedCategory) }
                .map { $0.displayPosition.trimmingCharacters(in: .whitespaces).uppercased() }
        )
        return PositionFilter.allCases.filter { filter in
            filter == .all || !filter.positionCodes.isDisjoint(with: present)
        }
    }

    /// Clubs the current search names, so "mariners" can open Seattle's page
    /// instead of only filtering the board down to Seattle's players. Empty
    /// unless something is typed.
    var searchedTeams: [String] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let present = Set(seasonPlayers.map { normalizedTeamAbbreviation($0.team) })
        return present
            .filter { teamMatchesQuery($0, query: searchText) }
            .sorted { teamDisplayName($0) < teamDisplayName($1) }
    }

    var filteredPlayers: [Player] {
        let applyPosition = positionFilterApplies && positionFilter != .all
        return seasonPlayers.filter { player in
            // Team search covers the nickname as well as the abbreviation and
            // the city: the field says "players or teams", and typing "Yankees"
            // or "Red Sox" used to return nothing because the only team strings
            // it compared were "NYY" and "New York (AL)".
            let matchesSearch = searchText.isEmpty
                || player.name.localizedCaseInsensitiveContains(searchText)
                || teamMatchesQuery(player.team, query: searchText)
            let matchesCategory = selectedCategory == nil || player.metrics.contains { $0.category == selectedCategory }
            let matchesType = player.matchesPlayerType(for: selectedCategory)
            let qualifies = isQualified(player, for: selectedCategory)
            let matchesPosition = !applyPosition || positionFilter.matches(player)
            return matchesSearch && matchesCategory && matchesType && qualifies && matchesPosition
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

    // Sort by the raw stat value, not the percentile, percentile-sorting
    // produced ties (two players at 95) and made the "PCTL" header look
    // disconnected from the xwOBA values shown per row. Players missing the
    // exact metric are partitioned to the end so blank-value rows never
    // interleave above genuinely-ranked players.
    var leaderboard: [Player] {
        guard let category = selectedCategory, let label = currentSortMetric else {
            return filteredPlayers.sorted(
                by: Self.metricComparator(label: "xwOBA", category: .hitting, descending: sortDescending)
            )
        }
        return filteredPlayers.sorted(
            by: Self.metricComparator(label: label, category: category, descending: sortDescending)
        )
    }

    /// Orders players by one metric, percentile first and raw value only as a
    /// tiebreak.
    ///
    /// Ranking by the parsed value string was wrong: 14.5% of historical metric
    /// rows carry a valid Savant percentile and an *empty* value (Arm Strength
    /// and Squared-Up% are blank 100% of the time, pitching xISO/xOBP/Chase%/
    /// Whiff% around two thirds), and `rawNumeric("")` is nil, so those players
    /// were swept into a tail below everyone who happened to have a printable
    /// number, however much worse they were. Percentile is always present and
    /// already direction-corrected by the backend (a pitcher allowing 6.6%
    /// Barrel% is the 66th percentile, not the 34th).
    ///
    /// `descending` still describes the *raw value*, because that's what the
    /// sort chip says and what the user flips. For a lower-is-better metric
    /// that's the opposite of the percentile direction, hence the XOR.
    static func metricComparator(
        label: String,
        category: MetricCategory,
        descending: Bool
    ) -> (Player, Player) -> Bool {
        let percentileDescending = descending != lowerIsBetter(label: label, category: category)
        return { p1, p2 in
            let m1 = p1.metrics.first { $0.label == label && $0.category == category }
            let m2 = p2.metrics.first { $0.label == label && $0.category == category }

            // A player without the metric at all sorts last in either direction.
            switch (m1, m2) {
            case (nil, nil): return p1.name < p2.name
            case (nil, _): return false
            case (_, nil): return true
            default: break
            }
            guard let m1, let m2 else { return false }

            if m1.percentile != m2.percentile {
                return percentileDescending
                    ? m1.percentile > m2.percentile
                    : m1.percentile < m2.percentile
            }
            // Same percentile bucket: the printed value breaks the tie when both
            // players have one, so the board doesn't reshuffle arbitrarily.
            if let v1 = rawNumeric(m1.value), let v2 = rawNumeric(m2.value), v1 != v2 {
                return descending ? v1 > v2 : v1 < v2
            }
            return p1.name < p2.name
        }
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
    /// Labels here had drifted off what the backend emits: the pitching set
    /// asked for "HardHit%", "EV", "LA", "GB%" and "FB%", none of which exist,
    /// so the real `Hard-Hit%`, `Avg EV Against`, `Max EV Against`, `xISO` and
    /// `xOBP` fell through to "highest first" and opened those boards with the
    /// worst pitchers at rank 1. Hitting was missing `Chase%` and `Whiff%`,
    /// which `TrendMetric` already signs correctly on the Trends tab.
    /// `DashboardViewModelTests` pins every string here to a real label.
    static func lowerIsBetter(label: String, category: MetricCategory) -> Bool {
        switch category {
        case .pitching:
            // Contact allowed and free baserunners: less of each is better.
            return ["xwOBA", "xBA", "xSLG", "xISO", "xOBP", "xERA", "ERA", "WHIP",
                    "BB%", "Barrel%", "Hard-Hit%", "Avg EV Against",
                    "Max EV Against"].contains(label)
        case .hitting:
            // Swinging at balls and missing them are the hitter's own failures.
            return ["K%", "Whiff%", "Chase%"].contains(label)
        case .fielding, .running:
            return false
        }
    }

    /// Default sort direction for a metric, descending (highest first) unless
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
            // xwOBA against parallels the hitter xwOBA, it folds in K/BB and contact quality,
            // so it's the right primary rank. xERA has a 25 PA minimum, so it stays out.
            return ["xwOBA", "K%", "Barrel%", "Whiff%", "Chase%"]
        case .fielding:
            // Backend uses "Range (OAA)" as the label
            return ["Range (OAA)", "Arm Strength", "Arm Value"]
        case .running:
            return ["Sprint Speed"]
        }
    }

    // Expose the current sort metric for row display. When no category is
    // active the leaderboard sorts by raw xwOBA; surface that label (with
    // nil category) so LeaderboardTableRow matches by label alone and shows
    // each player's xwOBA value instead of a percentile fallback.
    var currentSortMetricForDisplay: (label: String?, category: MetricCategory?) {
        if let label = currentSortMetric { return (label, selectedCategory) }
        return ("xwOBA", nil)
    }

    /// Hitters first (best xwOBA down), then pitchers (best xwOBA-against down).
    /// Both halves rank by percentile for the same reason the leaderboard does,
    /// and because percentile is already signed per side, the two halves need
    /// the same comparator direction rather than opposite ones.
    func players(forTeam team: String) -> [Player] {
        let normalized = normalizedTeamAbbreviation(team)
        let hittingOrder = Self.metricComparator(label: "xwOBA", category: .hitting, descending: true)
        let pitchingOrder = Self.metricComparator(label: "xwOBA", category: .pitching, descending: false)
        return seasonPlayers.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { p0, p1 in
                let isPitcher0 = p0.playerType?.lowercased() == "pitcher"
                let isPitcher1 = p1.playerType?.lowercased() == "pitcher"
                if isPitcher0 != isPitcher1 { return !isPitcher0 }
                return isPitcher0 ? pitchingOrder(p0, p1) : hittingOrder(p0, p1)
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
        return metricMap.compactMap { (key, data) -> MetricLeaderEntry? in
            let label = key.split(separator: "|").first.map(String.init) ?? key
            // Rank Best/Worst by Savant percentile, NOT by parsing the value
            // string. Roughly half of xISO / xOBP / Hard-Hit% (and 100% of
            // Arm Strength / Squared-Up%) ship a valid percentile but a blank
            // value; rawNumeric("") collapsed them all to 0, every player tied,
            // and the sort returned the same player (e.g. Ohtani) for both
            // ends with empty cells. Percentile is Savant's normalized
            // goodness, already direction-correct (it inverts for pitchers),
            // so highest = best, lowest = worst with no per-metric polarity
            // table needed.
            let byPercentile = data.values.sorted { $0.percentile < $1.percentile }
            guard let best = byPercentile.last else { return nil }
            let worst = byPercentile.first
            // Single qualifier (or every qualifier tied): the same player can't
            // be both Best and Worst, drop the duplicate so the row reads
            // "Best: X / Only qualifier" instead of "X is also the worst".
            let dedupedWorst = (worst?.player.id == best.player.id) ? nil : worst
            return (
                label: label,
                category: data.category,
                best: best,
                worst: dedupedWorst
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
            errorMessage = "Data format changed. The app may need an update."
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

        // Off the critical path on purpose: one tiny row that only Settings
        // reads, fetched after the leaderboard is already on screen. A failure
        // here leaves the coverage line blank rather than failing the load.
        if let coverage = try? await provider.fetchDataThroughDate(season: StatScoutSeason.current) {
            // A coverage date newer than what the cached windows were built from
            // is the signal that the rollup moved while we were backgrounded.
            let cacheIsStale = cachedRecentFormAsOf.map { coverage > $0 } ?? false
            dataThrough = coverage
            if cacheIsStale, selectedSeason == StatScoutSeason.current {
                await refreshCachedRecentFormWindows()
            }
        }

        // Same treatment: one row, after first paint, and a failure just leaves
        // the postseason out rather than failing the load.
        postseasonThrough = try? await provider.fetchPostseasonThroughDate(
            season: StatScoutSeason.current
        )
        if !offersPhaseChoice { selectedPhase = .regular }
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
            return ((try? cache?.loadPlayers()) ?? []).filter { ($0.season ?? 0) < StatScoutSeason.current }
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
