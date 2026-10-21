#if DEBUG
import Foundation

/// Launch with `-PaywallSnapshot trial|monthly|yearly|lifetime` to render paywall
/// surfaces for portfolio screenshot capture (see `capture-portfolio-paywall-screenshots.sh`).
enum PaywallScreenshotMode: String {
    case trial
    case monthly
    case yearly
    case lifetime

    static var current: PaywallScreenshotMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PaywallSnapshot"),
              index + 1 < arguments.count else { return nil }
        return PaywallScreenshotMode(rawValue: arguments[index + 1])
    }

    static var isActive: Bool { current != nil }
}
#endif

#if DEBUG
import SwiftUI

extension Notification.Name {
    static let duoRoute = Notification.Name("statscout.duoRoute")
    /// Object: the two `Player`s the Compare tab should open side by side.
    static let duoCompare = Notification.Name("statscout.duoCompare")
}

/// Seeded launch for iPhone Duo screenshot runs: `-DuoSeed` uses the bundled
/// history (no Supabase, no RevenueCat), skips onboarding and the update
/// showcase, and unlocks Pro in the view model only.
///
/// Routes arrive as `statscout://duo/<route>` or from `-DuoTour`: `stats`,
/// `pitching`, `trends`, `teams`, `team` (a team page), `compare`, `player`.
enum DuoScreenshotMode {
    static var isSeeded: Bool { ProcessInfo.processInfo.arguments.contains("-DuoSeed") }

    /// Set from the app's init, the clock `-DuoTour` offsets count from.
    private(set) static var launchedAt = Date()

    static func prepareIfSeeded() {
        guard isSeeded else { return }
        launchedAt = Date()
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(UpdateShowcaseCampaign.identifier, forKey: UpdateShowcaseCampaign.storageKey)
        defaults.removeObject(forKey: "favoriteTeam")
        // A followed Judge, Soto and Skubal, so stars and "Your players" read
        // like a real fan's app.
        defaults.set([592450, 665742, 669373], forKey: "favorites.playerIds")
    }

    static func handle(_ url: URL) {
        guard url.scheme == "statscout", url.host == "duo" else { return }
        let route = url.lastPathComponent
        NotificationCenter.default.post(name: .duoRoute, object: route)
    }
}
#endif
