import SwiftUI
import XCTest
@testable import Baseball_Savvy_StatScout

// State machine audit repro suite, 2026-11-06. Failing tests are expected: each
// one asserts the promised behaviour. Every test asserts its own preconditions
// first, and each failing claim has a passing control beside it.

// MARK: - Provider fake

/// Serves a different answer per call to each endpoint, so one view model can be
/// refreshed through an overnight prune, an offline resume, and so on.
final class ReproProvider: StatcastProviding, @unchecked Sendable {
    var currentPlayersByCall: [[Player]] = []
    var currentPlayersCalls = 0
    /// One entry per `fetchPostseasonThroughDate` call; nil entry means "throw".
    var postseasonThroughByCall: [Date?] = []
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
        return postseasonThroughByCall[min(postseasonThroughCalls, postseasonThroughByCall.count - 1)]
    }

    func fetchPostseasonPlayers(season: Int) async throws -> [Player] { [] }
}

// MARK: - Suite

@MainActor
final class StateMachineAuditRepro: XCTestCase {
    private func player(_ id: Int, team: String = "NYY") -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team, position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: StatScoutSeason.current, metrics: [], standardStats: [], games: []
        )
    }

    // MARK: SM-A1: a refresh keeps current-season rows the server pruned

    /// The pipeline prunes players who fall below the qualifier
    /// (backend/ingest.py:1778-1805, "an upsert-only refresh leaves their old
    /// (now stale) row behind forever"). The app's refresh must show the feed.
    func testRefreshDropsAPlayerTheServerPruned() async {
        let p = ReproProvider()
        p.currentPlayersByCall = [[player(1), player(2)], [player(1)]]
        let vm = DashboardViewModel(provider: p)
        vm.selectedSeason = StatScoutSeason.current

        await vm.load()
        // Preconditions: first load shows both, second feed has one, no error path.
        XCTAssertEqual(vm.seasonPlayers.map(\.playerId).sorted(), [1, 2])
        await vm.load()
        XCTAssertEqual(p.currentPlayersCalls, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.lastFetchFailed)

        XCTAssertEqual(vm.seasonPlayers.map(\.playerId).sorted(), [1],
                       "player 2 was pruned from the feed but is still on the board")
    }

    /// Control: a row still in the feed is replaced by its newer values.
    func testControlRefreshReplacesARowThatIsStillInTheFeed() async {
        let p = ReproProvider()
        p.currentPlayersByCall = [[player(1, team: "NYY")], [player(1, team: "BOS")]]
        let vm = DashboardViewModel(provider: p)
        vm.selectedSeason = StatScoutSeason.current
        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.map(\.team), ["NYY"])
        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.map(\.team), ["BOS"])
    }

    // MARK: SM-A2: a failed refresh unsets the postseason phase

    private func postseasonVM(_ p: ReproProvider) async -> DashboardViewModel {
        p.currentPlayersByCall = [[player(1)]]
        p.postseasonThroughByCall = [Date()]
        let vm = DashboardViewModel(provider: p)
        vm.selectedSeason = StatScoutSeason.current
        await vm.load()
        return vm
    }

    /// The user is on the Postseason board, backgrounds the app, and resumes
    /// with no connection (ContentView reloads on willEnterForeground).
    func testOfflineResumeKeepsTheSelectedPostseasonBoard() async {
        let p = ReproProvider()
        let vm = await postseasonVM(p)
        XCTAssertTrue(vm.offersPhaseChoice)
        vm.selectPhase(.postseason)
        XCTAssertEqual(vm.selectedPhase, .postseason)

        p.offline = true
        await vm.load()
        XCTAssertTrue(vm.lastFetchFailed, "precondition: the refresh did fail")

        XCTAssertEqual(vm.selectedPhase, .postseason,
                       "an offline resume must not change the board the user picked")
        XCTAssertTrue(vm.offersPhaseChoice, "the Postseason choice vanished from the season menu")
    }

    /// Control: the same resume with a working connection keeps the board.
    func testControlOnlineResumeKeepsTheSelectedPostseasonBoard() async {
        let p = ReproProvider()
        let vm = await postseasonVM(p)
        vm.selectPhase(.postseason)
        XCTAssertEqual(vm.selectedPhase, .postseason)

        await vm.load()
        XCTAssertFalse(vm.lastFetchFailed)
        XCTAssertEqual(vm.selectedPhase, .postseason)
        XCTAssertTrue(vm.offersPhaseChoice)
    }

    // MARK: SM-A3: pop-back to a profile counts as another profile open

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

    /// PlayerProfileView.swift:339-345 promises the pitch waits for the second
    /// profile open; AGENTS.md says the review ask follows the 3rd+ profile
    /// open. One profile, two drill-downs to a metric board and back, is one
    /// profile.
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

    /// Control: leaving the profile entirely and opening it again is a second
    /// open and must count (proves the harness sees onAppear).
    func testControlOpeningTheProfileTwiceCountsTwice() async {
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
