import SwiftUI

/// Which version of the postseason card a given customer should see.
enum PostseasonCreative: Equatable {
    /// Free or lapsed: the pitch, routed to the ordinary one-tap yearly CTA.
    /// No discount, no offer code, no price in the copy.
    case upgrade
    /// Already subscribed: an announcement that the postseason boards exist,
    /// which opens them instead of selling something already owned.
    case pro
}

struct PostseasonDecision: Equatable {
    let creative: PostseasonCreative?

    var shouldPresent: Bool { creative != nil }

    static let hidden = PostseasonDecision(creative: nil)
}

/// When the postseason card is allowed to appear.
///
/// This replaced a compiled calendar window, and the difference is the whole
/// point. The stretch-run card it succeeds could hardcode its dates because it
/// sold features that already existed. This one announces *data*, and the
/// pipeline closes out a day once, overnight: the first Wild Card game is not
/// readable in the app until the following morning. A date-triggered card would
/// therefore spend the first day of the playoffs pointing at an empty board, on
/// the one day it most wants to be right.
///
/// So the trigger is the data itself. `postseasonThrough` is the newest playoff
/// game the backend actually holds, and the card wakes when that arrives and
/// needs no release to switch on. Ship it dormant in September and it turns
/// itself on.
enum PostseasonCampaign {
    /// Bumping this re-shows the card to everyone who dismissed the last one,
    /// which is what a new season needs and a redraw of the same one does not.
    static let identifier = "postseason-2026"
    static let storageKey = "lastSeenPostseasonCard"

    static func decision(
        postseasonThrough: Date?,
        hasCompletedOnboarding: Bool,
        seenCampaign: String,
        customerStateResolved: Bool,
        isPro: Bool
    ) -> PostseasonDecision {
        guard postseasonThrough != nil else { return .hidden }
        guard hasCompletedOnboarding else { return .hidden }
        // Rendering before the customer state resolves flashes an upgrade pitch
        // at someone who already pays.
        guard customerStateResolved else { return .hidden }
        guard seenCampaign != identifier else { return .hidden }
        return PostseasonDecision(creative: isPro ? .pro : .upgrade)
    }
}

/// Inline dashboard card, not a modal. It sits in the leaderboard's scroll
/// content, so it never fights the full-screen update showcase and never costs
/// a `PaywallGate` presentation: the gate only starts counting when the sheet
/// it opens actually appears.
struct PostseasonCard: View {
    let creative: PostseasonCreative
    let onUpgrade: () -> Void
    let onOpenPostseason: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(title)
                .font(SavantType.cardTitle)
                .foregroundStyle(SavantPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: creative == .pro ? onOpenPostseason : onUpgrade) {
                    Text(ctaLabel)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SavantPalette.savantRed)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Not now")
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SavantGeo.padCard)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: SavantGeo.hairline)
        )
        .padding(.horizontal, SavantGeo.padPage)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Postseason")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .bold))
            Text("THE POSTSEASON")
                .font(SavantType.micro)
                .tracking(1.4)
        }
        .foregroundStyle(SavantPalette.savantRed)
    }

    // Copy sells what the postseason data actually is. Savant publishes no
    // postseason percentile leaderboards, so nothing here may promise a
    // percentile: the boards behind this card are game logs, form and standard
    // lines, and a card that oversold them would land on an empty bar chart.
    private var title: String {
        switch creative {
        case .upgrade: return "October is live."
        case .pro:     return "Postseason boards are live."
        }
    }

    private var detail: String {
        switch creative {
        case .upgrade:
            return "Every playoff game, tracked the way the regular season is. See who is actually hitting the ball hard in October, not who did it in June."
        case .pro:
            return "Switch any board to Postseason from the season menu to see playoff game logs and how each roster is performing right now."
        }
    }

    private var ctaLabel: String {
        switch creative {
        case .upgrade: return "SCOUT THE POSTSEASON"
        case .pro:     return "SEE THE POSTSEASON"
        }
    }
}

#if DEBUG
#Preview("Upgrade") {
    PostseasonCard(creative: .upgrade, onUpgrade: {}, onOpenPostseason: {}, onDismiss: {})
        .background(SavantPalette.canvas)
}

#Preview("Pro") {
    PostseasonCard(creative: .pro, onUpgrade: {}, onOpenPostseason: {}, onDismiss: {})
        .background(SavantPalette.canvas)
}
#endif
