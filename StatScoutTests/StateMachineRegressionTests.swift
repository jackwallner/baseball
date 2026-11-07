import SwiftUI
import XCTest
@testable import Baseball_Savvy_StatScout

// Regression tests for the 2026-11-06 state machine audit (B1, B2, B3, C1).
// See project-docs/audits/state-machines-2026-11-06-fixes.md.

/// Serves a different answer per call to each endpoint, so one view model can
/// be refreshed through an overnight prune, an offline resume, and so on.
final class SequencedStatcastProvider: StatcastProviding, @unchecked Sendable {
    var currentPlayersByCall: [[Player]] = []
    var currentPlayersCalls = 0
    /// One entry per `fetchPostseasonThroughDate` call; the last entry repeats.
    var postseasonThroughByCall: [Result<Date?, Error>] = []
    var postseasonThroughCalls = 0
    /// When true every endpoint throws `URLError(.notConnectedToInternet)`.
    var offline = false

    private func failIfOffline() throws {
        if offline { throw URLError(.notConnectedToInternet) }
    }

    func fetchPlayers() async throws -> [Player] { try await fetchCurrentPlayers() }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }

    func fetchCurrentPlayers() async throws -> [Player] {
        try failIfOffline()
        defer { currentPlayersCalls += 1 }
        guard !currentPlayersByCall.isEmpty else { return [] }
        return currentPlayersByCall[min(currentPlayersCalls, currentPlayersByCall.count - 1)]
    }

    func fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, sinceDate: Date, phase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm] { [] }
    func fetchDataThroughDate(season: Int) async throws -> Date? {
        try failIfOffline()
        return nil
    }

    func fetchPostseasonThroughDate(season: Int) async throws -> Date? {
        try failIfOffline()
        defer { postseasonThroughCalls += 1 }
        guard !postseasonThroughByCall.isEmpty else { return nil }
        return try postseasonThroughByCall[min(postseasonThroughCalls, postseasonThroughByCall.count - 1)].get()
    }

    func fetchPostseasonPlayers(season: Int) async throws -> [Player] { [] }
}

@MainActor
final class StateMachineRegressionTests: XCTestCase {
    private func player(_ id: Int, team: String = "NYY", season: Int = StatScoutSeason.current) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team, position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: season, metrics: [], standardStats: [], games: []
        )
    }

    // MARK: B2: a refresh keeps current-season rows the server pruned

    func testRefreshDropsAPlayerTheServerPruned() async {
        let p = SequencedStatcastProvider()
        p.currentPlayersByCall = [[player(1), player(2)], [player(1)]]
        let vm = DashboardViewModel(provider: p)
        vm.selectedSeason = StatScoutSeason.current

        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.map(\.playerId).sorted(), [1, 2])
        await vm.load()
        XCTAssertEqual(p.currentPlayersCalls, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.lastFetchFailed)

        XCTAssertEqual(vm.seasonPlayers.map(\.playerId).sorted(), [1],
                       "player 2 was pruned from the feed but is still on the board")
    }

    func testRefreshStillReplacesARowThatIsInTheFeed() async {
        let p = SequencedStatcastProvider()
        p.currentPlayersByCall = [[player(1, team: "NYY")], [player(1, team: "BOS")]]
        let vm = DashboardViewModel(provider: p)
        vm.selectedSeason = StatScoutSeason.current
        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.map(\.team), ["NYY"])
        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.map(\.team), ["BOS"])
    }

    /// Upgrade path: an existing install's saved current-season file (written
    /// by the previous build) still loads, a pruned row leaves on the first
    /// cold launch rather than the second, and past seasons are untouched.
    func testColdLaunchFromAnExistingCacheDropsThePrunedRowAndKeepsPastSeasons() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TwoTierPlayerCache(directory: directory)
        try cache.savePlayers([player(1), player(2)])
        XCTAssertEqual(try cache.loadCurrentPlayers().map(\.playerId).sorted(), [1, 2], "precondition: saved file reads back")
        let pastSeasonIds = Set(cache.loadHistoricalPlayers().map(\.id))

        let p = SequencedStatcastProvider()
        p.currentPlayersByCall = [[player(1)]]
        let vm = DashboardViewModel(provider: p, cache: cache)
        vm.selectedSeason = StatScoutSeason.current
        await vm.load()

        XCTAssertFalse(vm.lastFetchFailed)
        XCTAssertEqual(vm.seasonPlayers.map(\.playerId).sorted(), [1],
                       "a pruned row must not survive the first cold launch")
        XCTAssertEqual(try cache.loadCurrentPlayers().map(\.playerId), [1])
        if !pastSeasonIds.isEmpty {
            await vm.loadHistoricalIfNeeded()
            let loadedIds = Set(vm.playerHistories.values.flatMap { $0 }.map(\.id))
            XCTAssertTrue(pastSeasonIds.isSubset(of: loadedIds), "past seasons must be kept")
        }
    }

    func testRefreshKeepsPastSeasonRowsTheCurrentFeedDoesNotCarry() async {
        let past = StatScoutSeason.current - 1
        let p = SequencedStatcastProvider()
        p.currentPlayersByCall = [[player(1)]]
        let vm = DashboardViewModel(provider: p, cache: InMemoryPlayerCache(seed: [player(3, season: past), player(1)]))
        vm.selectedSeason = StatScoutSeason.current
        await vm.load()
        await vm.load()
        XCTAssertNotNil(vm.playerHistories[3]?.first { $0.season == past }, "a past-season row is not the feed's to prune")
    }

    // MARK: B3: a failed refresh unsets the postseason phase

    private func postseasonVM(_ p: SequencedStatcastProvider) async -> DashboardViewModel {
        p.currentPlayersByCall = [[player(1)]]
        let vm = DashboardViewModel(provider: p)
        vm.selectedSeason = StatScoutSeason.current
        await vm.load()
        vm.selectPhase(.postseason)
        return vm
    }

    func testOfflineResumeKeepsTheSelectedPostseasonBoard() async {
        let p = SequencedStatcastProvider()
        p.postseasonThroughByCall = [.success(Date())]
        let vm = await postseasonVM(p)
        XCTAssertTrue(vm.offersPhaseChoice)
        XCTAssertEqual(vm.selectedPhase, .postseason)

        p.offline = true
        await vm.load()
        XCTAssertTrue(vm.lastFetchFailed, "precondition: the refresh did fail")
        XCTAssertEqual(vm.selectedPhase, .postseason, "an offline resume must not change the board the user picked")
        XCTAssertTrue(vm.offersPhaseChoice, "the Postseason choice vanished from the season menu")
    }

    /// The quiet variant: the feed succeeds, only the through-date request
    /// times out, and no banner would explain a flip.
    func testThroughDateTimeoutKeepsTheSelectedPostseasonBoard() async {
        let p = SequencedStatcastProvider()
        p.postseasonThroughByCall = [.success(Date()), .failure(URLError(.timedOut))]
        let vm = await postseasonVM(p)
        XCTAssertEqual(vm.selectedPhase, .postseason)

        await vm.load()
        XCTAssertEqual(p.postseasonThroughCalls, 2)
        XCTAssertFalse(vm.lastFetchFailed)
        XCTAssertEqual(vm.selectedPhase, .postseason)
        XCTAssertTrue(vm.offersPhaseChoice)
    }

    /// Control: a successful answer of "no postseason" still clears the phase.
    func testThroughDateOfNilStillHidesThePostseason() async {
        let p = SequencedStatcastProvider()
        p.postseasonThroughByCall = [.success(Date()), .success(nil)]
        let vm = await postseasonVM(p)
        XCTAssertEqual(vm.selectedPhase, .postseason)

        await vm.load()
        XCTAssertEqual(vm.selectedPhase, .regular)
        XCTAssertFalse(vm.offersPhaseChoice)
    }

    // MARK: B1: pop-back to a profile counts as another profile open

    @MainActor
    final class Nav: ObservableObject {
        @Published var path = NavigationPath()
    }

    enum Dest: Hashable { case profile, metric }

    struct Host: View {
        @ObservedObject var nav: Nav
        let player: Player
        var body: some View {
            NavigationStack(path: $nav.path) {
                Text("root")
                    .navigationDestination(for: Dest.self) { dest in
                        switch dest {
                        case .profile: PlayerProfileView(player: player, history: [player])
                        case .metric: Text("metric leaders")
                        }
                    }
            }
            .environmentObject(StoreService.shared)
        }
    }

    private func spin(_ seconds: Double = 1.0) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func mount(_ nav: Nav) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: Host(nav: nav, player: player(1)))
        window.makeKeyAndVisible()
        return window
    }

    private let openKey = "profileOpenCount"

    private func isolateProfileCounters() -> () -> Void {
        let d = UserDefaults.standard
        let savedOpens = d.object(forKey: openKey)
        let savedMoments = ReviewPromptTracker.positiveMomentCount
        let savedPending = ReviewPromptTracker.hasPendingPositiveMoment
        d.set(0, forKey: openKey)
        ReviewPromptTracker.positiveMomentCount = 0
        ReviewPromptTracker.hasPendingPositiveMoment = false
        // Keep the 2-per-session pitch sheet from presenting over the host.
        PaywallGate.shared.markPresented(.playerScouting)
        PaywallGate.shared.markPresented(.playerScouting)
        return {
            if let savedOpens { d.set(savedOpens, forKey: self.openKey) } else { d.removeObject(forKey: self.openKey) }
            ReviewPromptTracker.positiveMomentCount = savedMoments
            ReviewPromptTracker.hasPendingPositiveMoment = savedPending
        }
    }

    func testReturningToOneProfileFromADrillDownIsNotANewProfileOpen() async {
        let restore = isolateProfileCounters()
        defer { restore() }
        XCTAssertFalse(StoreService.shared.isPro, "precondition: free user")
        let nav = Nav()
        let window = mount(nav)
        defer { window.isHidden = true }

        nav.path.append(Dest.profile)
        await spin()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 1, "precondition: first open counted once")

        for _ in 0..<2 {
            nav.path.append(Dest.metric)
            await spin(0.7)
            nav.path.removeLast()
            await spin(0.7)
        }
        XCTAssertEqual(nav.path.count, 1, "precondition: still on the same single profile")

        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 1,
                       "one profile opened once, but the counter says more")
        XCTAssertEqual(ReviewPromptTracker.positiveMomentCount, 0,
                       "no third profile was opened, so no review moment is due")
    }

    /// Control: leaving the profile and opening it again is a second open.
    func testOpeningTheProfileTwiceCountsTwice() async {
        let restore = isolateProfileCounters()
        defer { restore() }
        let nav = Nav()
        let window = mount(nav)
        defer { window.isHidden = true }

        nav.path.append(Dest.profile)
        await spin()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 1)
        nav.path.removeLast()
        await spin(0.7)
        nav.path.append(Dest.profile)
        await spin()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 2)
    }
}
