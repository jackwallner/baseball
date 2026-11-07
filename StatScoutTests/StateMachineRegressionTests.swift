import SwiftUI
import XCTest
@testable import Baseball_Savvy_StatScout

// Regression tests for the 2026-11-06 state machine audit (B1, B2, B3, C1).
// See project-docs/audits/state-machines-2026-11-06-fixes.md.

@MainActor
final class StateMachineRegressionTests: XCTestCase {
    private func player(_ id: Int, team: String = "NYY", season: Int = StatScoutSeason.current) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team, position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: season, metrics: [], standardStats: [], games: []
        )
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
