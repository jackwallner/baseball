import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let provider: StatcastProviding
    private let cache: PlayerCaching?

    var players: [Player] = []
    var playerHistories: [Int: [Player]] = [:] {
        didSet { rebuildSeasonIndex() }
    }

    /// One season's unique players, keyed by season.
    ///
    /// Every board reads one season, and with history loaded the histories
    /// hold every row since 2015. Scanning all of them on each
    /// read, several times per render, is what made search and category
    /// switches stutter. Built once whenever the histories change.
    private var seasonIndex: [Int: [Player]] = [:]
    /// Bumped with every rebuild of `seasonIndex`, so memoized board reads
    /// know when the rows under them changed without comparing them.
    private var historyGeneration = 0

    private func rebuildSeasonIndex() {
        var index: [Int: [Player]] = [:]
        var seen: [Int: Set<Int>] = [:]
        for history in playerHistories.values {
            for player in history {
                guard let season = player.season else { continue }
                guard seen[season, default: []].insert(player.playerId).inserted else { continue }
                index[season, default: []].append(player)
            }
        }
        seasonIndex = index
        historyGeneration += 1
    }

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
    var selectedSeason: Int = StatScoutSeason.calendarYear() {
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

    /// Postseason player lines, loaded on demand the first time the phase is
    /// switched. The backend maps percentile bars to the current regular-season
    /// curves because Savant publishes no postseason percentile leaderboards.
    /// An empty result after a successful request is a real no-data state.
    var postseasonPlayers: [Player] = [] {
        didSet {
            postseasonQualifier = PostseasonQualifier(players: postseasonPlayers)
            uniquePostseasonPlayers = uniquePlayers(postseasonPlayers)
            postseasonGeneration += 1
        }
    }
    /// `postseasonPlayers` with one row per player, what every postseason
    /// board reads.
    private var uniquePostseasonPlayers: [Player] = []
    /// Bumped with every postseason load, for the memoized board reads.
    private var postseasonGeneration = 0
    /// Built once per postseason load rather than per row: the club game
    /// counts it holds are a league-wide fact.
    private(set) var postseasonQualifier = PostseasonQualifier(players: [])
    var isLoadingPostseason = false
    var postseasonErrorMessage: String?
    private var hasLoadedPostseason = false

    /// A successful empty response is different from a request that has not
    /// completed. The former needs an actionable refresh state on the boards,
    /// because the game log can land before the MLB standard line does.
    var postseasonLoadCompleted: Bool { hasLoadedPostseason }

    /// Covers the short interval between selecting Postseason and the task
    /// starting, as well as the request itself, so the UI never flashes a
    /// generic "no data" message for a phase the user just selected.
    var postseasonLoadPending: Bool {
        postseasonAvailable && !hasLoadedPostseason && postseasonErrorMessage == nil
    }

    func loadPostseasonIfNeeded() async {
        guard postseasonAvailable, !hasLoadedPostseason, !isLoadingPostseason else { return }
        isLoadingPostseason = true
        postseasonErrorMessage = nil
        defer { isLoadingPostseason = false }
        do {
            let players = try await provider.fetchPostseasonPlayers(season: StatScoutSeason.current)
            postseasonPlayers = players
            hasLoadedPostseason = true
        } catch {
            if !isTaskCancellation(error) {
                postseasonErrorMessage = String(localized: "Couldn't load postseason data. Check your connection and try again.")
            }
        }
    }

    func reloadPostseason() async {
        guard postseasonAvailable else { return }
        hasLoadedPostseason = false
        postseasonErrorMessage = nil
        await loadPostseasonIfNeeded()
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
        return currentSortMetric ?? String(localized: "Top Category")
    }

    // Resolved sort metric: user override (if still available) or auto-priority pick.
    var currentSortMetric: String? {
        guard let category = selectedCategory else { return nil }
        if let user = userSortMetricByCategory[category],
           availableSortMetrics.contains(user) {
            return user
        }
        return board.autoSortLabel
    }

    private struct SortMenuKey: Equatable {
        let slice: BoardSliceKey
        let category: MetricCategory?
    }

    @ObservationIgnored private var sortMenuCache: (key: SortMenuKey, labels: [String])?

    // All metric labels available for the current category, priority metrics first.
    // Every board read goes through here (the sort label alone reads it
    // twice), so it is built once per season, phase and category.
    var availableSortMetrics: [String] {
        let key = SortMenuKey(slice: currentSliceKey, category: selectedCategory)
        if let cached = sortMenuCache, cached.key == key { return cached.labels }
        let labels = buildAvailableSortMetrics()
        sortMenuCache = (key, labels)
        return labels
    }

    private func buildAvailableSortMetrics() -> [String] {
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
        // A deferred purchase can resume its year before this mirror updates.
        if pro, selectedSeason < StatScoutSeason.current, !hasLoadedHistorical, !isHistoricalLoading {
            Task { await loadHistoricalIfNeeded() }
        }
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
    var loadingMessage = String(localized: "Starting up…")
    var loadingProgress = 0.05
    var errorMessage: String?
    var lastFetchFailed = false
    private var hasStartedLoading = false

    var isReady: Bool { !players.isEmpty }

    // Filled lazily from inside view reads, so ignored by observation: writing
    // an observed property mid-render schedules another render. Readers still
    // track the season and generation the key is built from.
    @ObservationIgnored private var _teamScores: [String: Double] = [:]
    @ObservationIgnored private var _teamsWithData: [String] = []
    @ObservationIgnored private var _teamCacheKey: TeamCacheKey?

    /// Teams come from the regular-season rows whatever the phase, as they
    /// always have, so the key leaves the phase out.
    private struct TeamCacheKey: Equatable {
        let generation: Int
        let season: Int
    }

    private var currentTeamCacheKey: TeamCacheKey {
        TeamCacheKey(generation: historyGeneration, season: selectedSeason)
    }

    var teamScores: [String: Double] {
        if _teamCacheKey != currentTeamCacheKey { recomputeTeamCache() }
        return _teamScores
    }

    var teamsWithData: [String] {
        if _teamCacheKey != currentTeamCacheKey { recomputeTeamCache() }
        return _teamsWithData
    }

    /// Everything a board's rows depend on below the user's own filters: the
    /// rows themselves, which season, and which phase.
    private struct BoardSliceKey: Equatable {
        let historyGeneration: Int
        let postseasonGeneration: Int
        let season: Int
        let postseason: Bool
    }

    private var currentSliceKey: BoardSliceKey {
        BoardSliceKey(
            historyGeneration: historyGeneration,
            postseasonGeneration: postseasonGeneration,
            season: selectedSeason,
            postseason: isPostseasonActive
        )
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
        let stamp = formatter.string(from: lastUpdated)
        return String(localized: "Updated \(stamp)")
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
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        phase requestedPhase: SeasonPhase? = nil
    ) async throws -> [PlayerGameLog] {
        let phase = requestedPhase ?? (season == StatScoutSeason.current ? selectedPhase : .regular)
        return try await provider.fetchGameLogs(playerId: playerId, season: season, phase: phase)
    }

    /// Team-scoped game logs since `sinceDate`. The TeamRankingsCard caps at 30
    /// days so we don't pull the whole season for an aggregate we only ever
    /// slice into 7/15/30 day windows.
    func fetchTeamGameLogs(
        team: String,
        season: Int,
        sinceDate: Date,
        phase requestedPhase: SeasonPhase? = nil
    ) async throws -> [PlayerGameLog] {
        let phase = requestedPhase ?? (season == StatScoutSeason.current ? selectedPhase : .regular)
        // Callers ask for "the last N days" measured from today, and the cards
        // then anchor their windows on the newest game they get back. Once the
        // slate stops (the regular season ends, an off day, a late Savant
        // drop) today runs ahead of the data, so slide the lower bound back by
        // the gap, or by November the request would ask for October games of a
        // season that ended in September and the card would come back empty.
        let anchor = phase == .postseason ? postseasonThrough : dataThrough
        let since = season == StatScoutSeason.current
            ? Self.slidWindowStart(sinceDate, anchor: anchor, now: .now)
            : sinceDate
        return try await provider.fetchTeamGameLogs(
            team: team,
            season: season,
            sinceDate: since,
            phase: phase
        )
    }

    /// `since` slid back by however far `now` has run ahead of the newest game
    /// in the data, so the window keeps its full length.
    nonisolated static func slidWindowStart(_ since: Date, anchor: Date?, now: Date) -> Date {
        guard let anchor, anchor < now else { return since }
        return since.addingTimeInterval(-now.timeIntervalSince(anchor))
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
        // One root for every board: the leaderboard, the sort menu, best/worst
        // and the standard line all derive from this, so switching the source
        // here is what makes the whole Stats tab phase-aware at once rather
        // than in four places that could disagree.
        players(forSeason: selectedSeason, phase: selectedPhase)
    }

    /// What the postseason percentile bars are measured against, for the header
    /// that has to say so. The bars are not Savant postseason figures, which do
    /// not exist: they are this season's regular-season curve, with an October
    /// value looked up on it.
    var postseasonReferenceNote: String {
        String(localized: "Percentiles vs. \(String(StatScoutSeason.current)) regular season")
    }

    // MARK: - Recent form

    /// Rolling windows keyed by length, so flipping between 7 / 15 / 30
    /// doesn't refetch what's already in hand.
    ///
    /// Always the live season, whatever the Stats tab is showing. The rollup
    /// only exists for it, and a window is a "right now" read: following
    /// `selectedSeason` left Trends empty on every past year and let a team
    /// page on 2024 evict the live windows Trends was holding.
    var recentFormByWindow: [Int: [Int: RecentForm]] = [:]
    var recentFormLoadingWindows: Set<Int> = []
    /// Windows whose last fetch came back with no rows. Not cached as data
    /// (the next ask fetches again), but terminal for the caller that asked,
    /// so a roster waiting on it stops spinning.
    var recentFormEmptyWindows: Set<Int> = []
    var recentFormError: String?
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
        guard recentFormByWindow[target.rawValue] == nil else { return }

        // Join the fetch that's already running rather than returning as if
        // this request had been served. The caller awaits real data either way.
        if let inFlight = recentFormTasks[target.rawValue] {
            await inFlight.value
            return
        }

        recentFormLoadingWindows.insert(target.rawValue)
        recentFormEmptyWindows.remove(target.rawValue)
        recentFormError = nil
        let season = StatScoutSeason.current
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
                // Only the windows built on the newest anchor date. The rollup
                // used to leave a player's last window behind when he stopped
                // playing, so a July "last 7 days" could rank on a board headed
                // "Through Sep 27".
                let newest = rows.compactMap(\.asOf).max()
                let current = rows.filter { newest == nil || $0.asOf == newest }
                // A two-way player has a row per side; the leaderboard keys by
                // player, so keep whichever side has the larger sample.
                var byPlayer: [Int: RecentForm] = [:]
                for row in current {
                    if let existing = byPlayer[row.playerId],
                       existing.plateAppearances >= row.plateAppearances { continue }
                    byPlayer[row.playerId] = row
                }
                // An empty answer isn't cached. Early in a season the rollup
                // genuinely has nothing yet, and caching that would pin the
                // board to "no movement" for the rest of the launch.
                guard !byPlayer.isEmpty else {
                    self.recentFormEmptyWindows.insert(target.rawValue)
                    return
                }
                self.recentFormByWindow[target.rawValue] = byPlayer
                // Keep the Settings coverage line and the Trends "Through …"
                // header reading off the same answer once a window has landed.
                if let asOf = byPlayer.values.compactMap(\.asOf).max() {
                    self.dataThrough = asOf
                }
            } catch {
                // A window the user has already flipped away from cancels its
                // own fetch. Reporting that as a failure is how tapping quickly
                // around the Trends board produced an error on a board that was
                // fine.
                if !isTaskCancellation(error) {
                    self.recentFormError = String(localized: "Couldn't load recent form.")
                }
            }
        }
        recentFormTasks[target.rawValue] = task
        await task.value
    }

    /// Unique players for an arbitrary season, not just the selected one.
    /// Drill-down leaderboards opened from a player profile need the season
    /// that profile is showing, which can differ from `selectedSeason`.
    func players(forSeason season: Int, phase: SeasonPhase = .regular) -> [Player] {
        if phase == .postseason && season == StatScoutSeason.current {
            return uniquePostseasonPlayers
        }
        return seasonIndex[season] ?? []
    }

    private func uniquePlayers(_ players: [Player]) -> [Player] {
        var seen = Set<Int>()
        return players.filter { seen.insert($0.playerId).inserted }
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
            case .all: return String(localized: "Pos")
            case .infield: return "IF"
            case .outfield: return "OF"
            default: return rawValue
            }
        }

        var label: String {
            switch self {
            case .all: return String(localized: "All positions")
            case .infield: return String(localized: "Infield")
            case .outfield: return String(localized: "Outfield")
            case .catcher: return String(localized: "Catcher")
            case .firstBase: return String(localized: "First base")
            case .secondBase: return String(localized: "Second base")
            case .thirdBase: return String(localized: "Third base")
            case .shortstop: return String(localized: "Shortstop")
            case .leftField: return String(localized: "Left field")
            case .centerField: return String(localized: "Center field")
            case .rightField: return String(localized: "Right field")
            case .designatedHitter: return String(localized: "Designated hitter")
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
    @ObservationIgnored private var positionFiltersCache: (key: SortMenuKey, filters: [PositionFilter])?

    var availablePositionFilters: [PositionFilter] {
        let key = SortMenuKey(slice: currentSliceKey, category: selectedCategory)
        if let cached = positionFiltersCache, cached.key == key { return cached.filters }
        let filters = buildAvailablePositionFilters()
        positionFiltersCache = (key, filters)
        return filters
    }

    private func buildAvailablePositionFilters() -> [PositionFilter] {
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

    var filteredPlayers: [Player] { board.filtered }

    /// The filtered board and the sort metric picked from it. The sort label
    /// alone walks the filtered set once per priority metric, and the view
    /// reads both several times per render, so they are built once per change
    /// of anything they depend on.
    private struct Board {
        let filtered: [Player]
        let autoSortLabel: String?
    }

    private struct BoardKey: Equatable {
        let slice: BoardSliceKey
        let searchText: String
        let category: MetricCategory?
        let qualifierLevel: QualifierLevel
        let positionFilter: PositionFilter
    }

    @ObservationIgnored private var boardCache: (key: BoardKey, board: Board)?

    private var currentBoardKey: BoardKey {
        BoardKey(
            slice: currentSliceKey,
            searchText: searchText,
            category: selectedCategory,
            qualifierLevel: qualifierLevel,
            positionFilter: positionFilter
        )
    }

    private var board: Board {
        let key = currentBoardKey
        if let cached = boardCache, cached.key == key { return cached.board }
        let filtered = buildFilteredPlayers()
        let board = Board(filtered: filtered, autoSortLabel: determineSortMetricLabel(in: filtered))
        boardCache = (key, board)
        return board
    }

    private func buildFilteredPlayers() -> [Player] {
        let applyPosition = positionFilterApplies && positionFilter != .all
        let positionFilter = positionFilter
        let category = selectedCategory
        let query = searchText
        // Thirty clubs, a thousand-odd players: each team is matched once.
        var teamMatches: [String: Bool] = [:]
        // Cheapest tests first; the search and qualifier checks only run on
        // players still in the running.
        return seasonPlayers.filter { player in
            guard player.matchesPlayerType(for: category),
                  !applyPosition || positionFilter.matches(player),
                  category == nil || player.metrics.contains(where: { $0.category == category })
            else { return false }
            // Team search covers the nickname as well as the abbreviation and
            // the city: the field says "players or teams", and typing "Yankees"
            // or "Red Sox" used to return nothing because the only team strings
            // it compared were "NYY" and "New York (AL)".
            if !query.isEmpty, !player.name.localizedCaseInsensitiveContains(query) {
                let teamMatch = teamMatches[player.team] ?? teamMatchesQuery(player.team, query: query)
                teamMatches[player.team] = teamMatch
                guard teamMatch else { return false }
            }
            return isQualified(player, for: category)
        }
    }

    enum QualifierLevel: String, CaseIterable, Identifiable {
        case all = "All"
        case any = "Min Sample"
        case qualified = "Qualified"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .any: return String(localized: "Min Sample")
            case .qualified: return String(localized: "Qualified")
            }
        }

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
            case .all: return String(localized: "No minimum")
            case .any: return String(localized: "10+ PA / 5+ IP")
            case .qualified: return String(localized: "Savant qualifier")
            }
        }
    }

    var qualifierLevel: QualifierLevel = .qualified

    var minPlateAppearances: Int { qualifierLevel.minPA }
    var minInningsPitched: Double { qualifierLevel.minIP }

    /// True when the boards are reading the postseason slate.
    var isPostseasonActive: Bool {
        selectedPhase == .postseason && selectedSeason == StatScoutSeason.current
    }

    func isQualified(_ player: Player, for category: MetricCategory?) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            // Every October player carries a percentile (they're looked up on
            // the regular-season curve with no sample gate), so "has one" is
            // no qualifier at all there. MLB's per-club rule stands in.
            if isPostseasonActive {
                return postseasonQualifier.qualifies(player, for: category ?? .hitting)
            }
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
        return PostseasonQualifier.innings(Double(stat.value.trimmingCharacters(in: .whitespaces)) ?? 0)
    }

    private static let paLabels: Set<String> = ["PA", "AB"]
    private static let ipLabels: Set<String> = ["IP"]

    // Sort by the raw stat value, not the percentile, percentile-sorting
    // produced ties (two players at 95) and made the "PCTL" header look
    // disconnected from the xwOBA values shown per row. Players missing the
    // exact metric are partitioned to the end so blank-value rows never
    // interleave above genuinely-ranked players.
    private struct LeaderboardKey: Equatable {
        let board: BoardKey
        let sortMetric: String?
        let sortDescending: Bool
    }

    @ObservationIgnored private var leaderboardCache: (key: LeaderboardKey, players: [Player])?

    /// The ranked board. The view reads it several times per render, and
    /// every loading-progress tick re-renders, so it is sorted once per change
    /// of anything it depends on.
    var leaderboard: [Player] {
        let key = LeaderboardKey(board: currentBoardKey, sortMetric: currentSortMetric, sortDescending: sortDescending)
        if let cached = leaderboardCache, cached.key == key { return cached.players }
        let players = buildLeaderboard()
        leaderboardCache = (key, players)
        return players
    }

    private func buildLeaderboard() -> [Player] {
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
    private func determineSortMetricLabel(in filteredPlayers: [Player]) -> String? {
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
        teamScores[normalizedTeamAbbreviation(abbr)] ?? 0
    }

    private struct QualifierKey: Equatable {
        let slice: BoardSliceKey
        let qualifierLevel: QualifierLevel
    }

    private var currentQualifierKey: QualifierKey {
        QualifierKey(slice: currentSliceKey, qualifierLevel: qualifierLevel)
    }

    @ObservationIgnored private var qualifiedCache: (key: QualifierKey, players: [Player])?

    /// Players who meet the active qualifier for at least one category they appear in.
    /// Used to filter the StatScout leaders and Box Score so unqualified samples don't pollute results.
    var qualifiedSeasonPlayers: [Player] {
        let key = currentQualifierKey
        if let cached = qualifiedCache, cached.key == key { return cached.players }
        let players = buildQualifiedSeasonPlayers()
        qualifiedCache = (key, players)
        return players
    }

    private func buildQualifiedSeasonPlayers() -> [Player] {
        seasonPlayers.filter { player in
            let categories = Set(player.metrics.map(\.category))
            if categories.isEmpty { return isQualified(player, for: nil) }
            return categories.contains { isQualified(player, for: $0) }
        }
    }

    @ObservationIgnored private var metricLeadersCache: (key: QualifierKey, entries: [MetricLeaderEntry])?

    /// Best and worst on every metric. Walks every metric of every player in
    /// the season, so it is built once per change rather than per render.
    var allMetrics: [MetricLeaderEntry] {
        let key = currentQualifierKey
        if let cached = metricLeadersCache, cached.key == key { return cached.entries }
        let entries = buildAllMetrics()
        metricLeadersCache = (key, entries)
        return entries
    }

    private func buildAllMetrics() -> [MetricLeaderEntry] {
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
        loadingMessage = players.isEmpty ? String(localized: "Loading saved players…") : String(localized: "Refreshing player data…")
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

        loadingMessage = String(localized: "Checking for updates…")
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
                    errorMessage = String(localized: "No players found.")
                    lastFetchFailed = true
                }
                isLoading = false
                loadingProgress = 1
                return
            }

            loadingMessage = String(localized: "Preparing leaderboard…")
            loadingProgress = 0.85
            ingestPlayers(allPlayers)
            try? cache?.savePlayers(current)

        } catch is DecodingError {
            errorMessage = String(localized: "Data format changed. The app may need an update.")
            lastFetchFailed = true
        } catch _ as URLError {
            errorMessage = players.isEmpty ? String(localized: "Can't reach data feed. Check your connection.") : String(localized: "Showing saved data. Pull to refresh when your connection improves.")
            lastFetchFailed = true
        } catch {
            errorMessage = players.isEmpty ? String(localized: "Something went wrong loading player data.") : String(localized: "Showing saved data. Pull to refresh to try again.")
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
            if cacheIsStale {
                await refreshCachedRecentFormWindows()
            }
        }

        // Same treatment: one row, after first paint, and a failure just leaves
        // the postseason out rather than failing the load.
        postseasonThrough = try? await provider.fetchPostseasonThroughDate(
            season: StatScoutSeason.current
        )
        if !offersPhaseChoice { selectedPhase = .regular }
        if offersPhaseChoice, selectedPhase == .postseason {
            await reloadPostseason()
        }
    }

    func loadHistoricalIfNeeded() async {
        guard !hasLoadedHistorical, !isHistoricalLoading else { return }
        isHistoricalLoading = true
        loadingMessage = String(localized: "Loading past seasons…")
        loadingProgress = 0.12

        let historical: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return cache.loadHistoricalPlayers()
            }
            return ((try? cache?.loadPlayers()) ?? []).filter { ($0.season ?? 0) < StatScoutSeason.current }
        }.value

        loadingMessage = String(localized: "Preparing season history…")
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

        let seasonsWithData = Set(seasonIndex.keys)
        if !seasonsWithData.contains(selectedSeason),
           let mostRecentUnlocked = seasonsWithData.sorted(by: >).first(where: { !isSeasonLocked($0) }) {
            // Only auto-jump to a season the user can actually view; a free user
            // with no current-season data stays on the free season (honest empty
            // state) rather than silently rendering locked past-season data.
            selectedSeason = mostRecentUnlocked
        }
    }

    private func recomputeTeamCache() {
        let uniquePlayers = seasonIndex[selectedSeason] ?? []

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
        _teamCacheKey = currentTeamCacheKey
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
