import XCTest
@testable import Baseball_Savvy_StatScout

/// Each test pins a P1 from the 2026-10-30 overnight bug hunt.
@MainActor
final class ProfileSeasonRowTests: XCTestCase {
    private func row(season: Int) -> Player {
        Player(
            playerId: 7, name: "Rookie", team: "ATH", position: "1B", handedness: "L/R", imageURL: nil,
            updatedAt: Date(), season: season,
            metrics: [Metric(id: "x", label: "xwOBA", value: ".372", percentile: 93, category: .hitting)],
            standardStats: [], games: []
        )
    }

    /// F-01: a 2025 rookie picked on 2022 showed his 2025 line under "2022".
    func testAPickedSeasonWithNoRowShowsNoRowNotAnotherYear() {
        let rookie = row(season: 2025)
        XCTAssertNil(PlayerProfileView.seasonRow(
            player: rookie, history: [rookie], selectedSeason: 2022, phase: .regular
        ))
        // History still loading: nothing for the past year yet, never the current row.
        XCTAssertNil(PlayerProfileView.seasonRow(
            player: rookie, history: [], selectedSeason: 2022, phase: .regular
        ))
    }

    func testThePickedSeasonsRowAndTheOpeningRowStillResolve() {
        let current = row(season: 2026)
        let past = row(season: 2024)
        XCTAssertEqual(PlayerProfileView.seasonRow(
            player: current, history: [past, current], selectedSeason: 2024, phase: .regular
        )?.season, 2024)
        XCTAssertEqual(PlayerProfileView.seasonRow(
            player: current, history: [], selectedSeason: 2026, phase: .regular
        )?.season, 2026)
        XCTAssertEqual(PlayerProfileView.seasonRow(
            player: current, history: [past], selectedSeason: nil, phase: .regular
        )?.season, 2026)
        XCTAssertEqual(PlayerProfileView.seasonRow(
            player: current, history: [past], selectedSeason: nil, phase: .postseason
        )?.season, 2026)
    }
}

final class HistoricalBundleCacheTests: XCTestCase {
    /// F-02: a Caches copy written by an older build shadowed the bundle, so a
    /// regenerated bundle (the next rollover) never reached existing installs.
    func testAStaleCachesCopyNeverShadowsTheBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "historical-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stale = Player(
            playerId: 1, name: "Stale", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: 2020, metrics: [], standardStats: [], games: []
        )
        let staleURL = directory.appending(path: "players-historical.plist")
        try PropertyListEncoder.statScout.encode([stale]).write(to: staleURL)

        let players = TwoTierPlayerCache(directory: directory).loadHistoricalPlayers()

        XCTAssertGreaterThan(players.count, 1)
        let seasons = Set(players.compactMap(\.season))
        XCTAssertTrue(seasons.contains(StatScoutSeason.earliest))
        XCTAssertTrue(seasons.contains(StatScoutSeason.current - 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
    }
}

/// Records which season each recent-form request asked for.
private final class SeasonRecordingProvider: StatcastProviding, @unchecked Sendable {
    private let base: MockProvider
    private let lock = NSLock()
    private var seasons: [Int] = []

    init(_ base: MockProvider) { self.base = base }

    var requestedSeasons: [Int] { lock.withLock { seasons } }

    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm] {
        lock.withLock { seasons.append(season) }
        return try await base.fetchRecentForm(season: season, windowDays: windowDays)
    }

    func fetchPlayers() async throws -> [Player] { try await base.fetchPlayers() }
    func fetchHistoricalPlayers() async throws -> [Player] { try await base.fetchHistoricalPlayers() }
    func fetchCurrentPlayers() async throws -> [Player] { try await base.fetchCurrentPlayers() }
    func fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase) async throws -> [PlayerGameLog] {
        try await base.fetchGameLogs(playerId: playerId, season: season, phase: phase)
    }
    func fetchTeamGameLogs(team: String, season: Int, sinceDate: Date, phase: SeasonPhase) async throws -> [PlayerGameLog] {
        try await base.fetchTeamGameLogs(team: team, season: season, sinceDate: sinceDate, phase: phase)
    }
    func fetchPostseasonThroughDate(season: Int) async throws -> Date? { try await base.fetchPostseasonThroughDate(season: season) }
    func fetchPostseasonPlayers(season: Int) async throws -> [Player] { try await base.fetchPostseasonPlayers(season: season) }
    func fetchDataThroughDate(season: Int) async throws -> Date? { try await base.fetchDataThroughDate(season: season) }
}

@MainActor
final class RecentFormSeasonTests: XCTestCase {
    private func form(id: Int) -> RecentForm {
        let json = """
        {
          "player_id": \(id), "season": \(StatScoutSeason.current), "player_type": "batter",
          "window_days": 15, "as_of": "2026-09-27", "team": "SEA",
          "games": 10, "plate_appearances": 40, "batted_ball_events": 20,
          "metrics": {}, "prior_metrics": {}, "delta": {}
        }
        """
        return try! JSONDecoder().decode(RecentForm.self, from: Data(json.utf8))
    }

    /// F-04: Trends followed the Stats tab's year and asked for a past
    /// season's rollup, which does not exist.
    func testTrendsAsksForTheLiveSeasonWhateverTheStatsTabShows() async {
        let provider = SeasonRecordingProvider(MockProvider(recentForm: [form(id: 1)]))
        let vm = DashboardViewModel(provider: provider)
        vm.selectSeason(2024)
        await vm.loadRecentFormIfNeeded()

        XCTAssertEqual(provider.requestedSeasons, [StatScoutSeason.current])
        XCTAssertNotNil(vm.recentForm(for: 1))
    }

    /// F-04: a team page on a past season evicted the live windows Trends held.
    func testAPastSeasonDoesNotEvictTheLiveWindows() async {
        let provider = SeasonRecordingProvider(MockProvider(recentForm: [form(id: 1)]))
        let vm = DashboardViewModel(provider: provider)
        vm.selectSeason(StatScoutSeason.current)
        await vm.loadRecentFormIfNeeded(window: .fortnight)
        vm.selectSeason(2024)
        await vm.loadRecentFormIfNeeded(window: .fortnight)

        XCTAssertEqual(provider.requestedSeasons, [StatScoutSeason.current])
        XCTAssertNotNil(vm.recentForm(for: 1, window: .fortnight))
    }

    /// F-03: an empty answer left the team roster spinning, with no state
    /// saying the fetch had finished.
    func testAnEmptyAnswerIsATerminalStateForTheWindow() async {
        let vm = DashboardViewModel(provider: MockProvider(recentForm: []))
        await vm.loadRecentFormIfNeeded(window: .fortnight)

        XCTAssertFalse(vm.recentFormLoadingWindows.contains(15))
        XCTAssertTrue(vm.recentFormEmptyWindows.contains(15))
        XCTAssertNil(vm.recentFormByWindow[15])
    }

    /// F-03: a failed fetch reports an error the roster can show with a retry.
    func testAFailedFetchSetsTheError() async {
        let vm = DashboardViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)))
        await vm.loadRecentFormIfNeeded(window: .fortnight)

        XCTAssertFalse(vm.recentFormLoadingWindows.contains(15))
        XCTAssertNotNil(vm.recentFormError)
    }
}

@MainActor
final class TeamInningsTests: XCTestCase {
    private func pitcher(_ id: Int, ip: String, era: String) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: "ARI", position: "P", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: 2026, playerType: "pitcher", metrics: [],
            standardStats: [
                StandardStat(id: "ip", label: "IP", value: ip, category: .pitching),
                StandardStat(id: "era", label: "ERA", value: era, category: .pitching),
            ],
            games: []
        )
    }

    /// F-18: 162.1 + 100.2 innings is 263 innings, not 262.3.
    func testBoxScoreThirdsSumAsThirds() {
        let line = TeamAggregate.standardLine(
            roster: [pitcher(1, ip: "162.1", era: "3.00"), pitcher(2, ip: "100.2", era: "6.00")],
            category: .pitching
        )
        XCTAssertEqual(line["IP"].map { TeamAggregate.formatStandard("IP", $0) }, "263.0")
        // ERA weighted by real innings: (3 * 162.333 + 6 * 100.667) / 263.
        XCTAssertEqual(line["ERA"] ?? 0, (3 * (162 + 1.0 / 3) + 6 * (100 + 2.0 / 3)) / 263, accuracy: 0.0001)
    }

    func testBoxScoreRoundTrips() {
        XCTAssertEqual(PostseasonQualifier.boxScore(PostseasonQualifier.innings(1484.1)), 1484.1, accuracy: 0.0001)
        XCTAssertEqual(PostseasonQualifier.boxScore(PostseasonQualifier.innings(4.2)), 4.2, accuracy: 0.0001)
        XCTAssertEqual(PostseasonQualifier.boxScore(263), 263, accuracy: 0.0001)
    }
}

/// A recent-form provider whose requests take a while and honor cancellation,
/// so a test can hold a fetch in flight. Counts requests per window.
private final class SlowRecentFormProvider: StatcastProviding, @unchecked Sendable {
    private let base: MockProvider
    private let lock = NSLock()
    private var requests: [Int] = []
    private var rollupAsOf: String
    private var coverage: Date?

    init(_ base: MockProvider, asOf: String, delay: UInt64 = 400_000_000) {
        self.base = base
        self.rollupAsOf = asOf
        self.delay = delay
    }

    private let delay: UInt64

    func requestCount(window: Int) -> Int { lock.withLock { requests.filter { $0 == window }.count } }
    func moveRollup(to asOf: String, coverage: Date) {
        lock.withLock { rollupAsOf = asOf; self.coverage = coverage }
    }

    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm] {
        let asOf = lock.withLock { () -> String in requests.append(windowDays); return rollupAsOf }
        try await Task.sleep(nanoseconds: delay)
        let json = """
        {
          "player_id": 1, "season": \(season), "player_type": "batter",
          "window_days": \(windowDays), "as_of": "\(asOf)", "team": "SEA",
          "games": 10, "plate_appearances": 40, "batted_ball_events": 20,
          "metrics": {}, "prior_metrics": {}, "delta": {}
        }
        """
        return [try JSONDecoder().decode(RecentForm.self, from: Data(json.utf8))]
    }

    func fetchDataThroughDate(season: Int) async throws -> Date? { lock.withLock { coverage } }
    func fetchPlayers() async throws -> [Player] { try await base.fetchPlayers() }
    func fetchHistoricalPlayers() async throws -> [Player] { try await base.fetchHistoricalPlayers() }
    func fetchCurrentPlayers() async throws -> [Player] { try await base.fetchCurrentPlayers() }
    func fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase) async throws -> [PlayerGameLog] {
        try await base.fetchGameLogs(playerId: playerId, season: season, phase: phase)
    }
    func fetchTeamGameLogs(team: String, season: Int, sinceDate: Date, phase: SeasonPhase) async throws -> [PlayerGameLog] {
        try await base.fetchTeamGameLogs(team: team, season: season, sinceDate: sinceDate, phase: phase)
    }
    func fetchPostseasonThroughDate(season: Int) async throws -> Date? { try await base.fetchPostseasonThroughDate(season: season) }
    func fetchPostseasonPlayers(season: Int) async throws -> [Player] { try await base.fetchPostseasonPlayers(season: season) }
}

@MainActor
final class RecentFormTaskOwnershipTests: XCTestCase {
    private let player = Player(
        playerId: 1, name: "Live", team: "SEA", position: "RF", handedness: "R/R", imageURL: nil,
        updatedAt: Date(), season: StatScoutSeason.current, metrics: [], standardStats: [], games: []
    )

    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), what)
    }

    /// B5 (2026-11-20 audit): a reload cancels the running fetch and starts
    /// another. The cancelled one unwound afterwards and cleared the loading
    /// flag of the fetch that replaced it, so the board said "No movement to
    /// rank yet" while the new request was still running.
    func testReloadWhileFetchingKeepsTheWindowMarkedLoading() async {
        let provider = SlowRecentFormProvider(MockProvider(), asOf: "2026-09-27")
        let vm = DashboardViewModel(provider: provider)
        let first = Task { await vm.loadRecentFormIfNeeded(window: .fortnight) }
        await waitUntil("first request started") { provider.requestCount(window: 15) == 1 }
        let second = Task { await vm.reloadRecentForm(window: .fortnight) }
        await waitUntil("second request started") { provider.requestCount(window: 15) == 2 }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(vm.recentFormLoadingWindows.contains(15), "the replacement is still running")
        XCTAssertTrue(vm.isRecentFormLoading)

        await first.value
        await second.value
        XCTAssertFalse(vm.recentFormLoadingWindows.contains(15))
        XCTAssertNotNil(vm.recentForm(for: 1, window: .fortnight))
    }

    /// B5: a caller arriving while the replacement runs joins it instead of
    /// starting a third request.
    func testJoiningARunningRecentFormFetchAfterAReloadDoesNotDuplicateIt() async {
        let provider = SlowRecentFormProvider(MockProvider(), asOf: "2026-09-27")
        let vm = DashboardViewModel(provider: provider)
        let first = Task { await vm.loadRecentFormIfNeeded(window: .fortnight) }
        await waitUntil("first request started") { provider.requestCount(window: 15) == 1 }
        let second = Task { await vm.reloadRecentForm(window: .fortnight) }
        await waitUntil("second request started") { provider.requestCount(window: 15) == 2 }
        try? await Task.sleep(nanoseconds: 100_000_000)

        await vm.loadRecentFormIfNeeded(window: .fortnight)

        XCTAssertEqual(provider.requestCount(window: 15), 2)
        await first.value
        await second.value
    }

    /// B7: a foreground refresh that finds newer coverage cancelled every
    /// running window fetch but only re-asked for the windows already held, so
    /// a window opened a moment earlier ended with no data and no request.
    func testRefreshRestartsAWindowThatWasStillLoading() async {
        let provider = SlowRecentFormProvider(MockProvider(players: [player]), asOf: "2026-09-26", delay: 150_000_000)
        let vm = DashboardViewModel(provider: provider)
        await vm.loadRecentFormIfNeeded(window: .fortnight)
        XCTAssertNotNil(vm.recentForm(for: 1, window: .fortnight))

        provider.moveRollup(to: "2026-09-27", coverage: Date.fromPostgresDate("2026-09-27")!)
        let month = Task { await vm.loadRecentFormIfNeeded(window: .month) }
        await waitUntil("30 day request started") { provider.requestCount(window: 30) == 1 }
        await vm.load()
        await month.value

        XCTAssertNotNil(vm.recentForm(for: 1, window: .month), "the 30 day window was restarted, not dropped")
        XCTAssertNotNil(vm.recentForm(for: 1, window: .fortnight))
        XCTAssertTrue(vm.recentFormLoadingWindows.isEmpty)
        XCTAssertFalse(vm.recentFormEmptyWindows.contains(30))
    }
}
