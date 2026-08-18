import SwiftUI

/// Which version of the seasonal card a given customer should see.
enum StretchRunCreative: Equatable {
    /// Free or lapsed: the seasonal pitch, which routes to the normal one-tap
    /// yearly CTA. No discount, no offer code, no price in the copy.
    case upgrade
    /// Already subscribed: a benefit reminder that opens Trends instead of
    /// selling something the customer already owns.
    case pro
}

struct StretchRunDecision: Equatable {
    let creative: StretchRunCreative?

    var shouldPresent: Bool { creative != nil }

    static let hidden = StretchRunDecision(creative: nil)
}

/// The 2026 stretch-run merchandising window.
///
/// Deliberately compiled rather than remote: the card's only kill reasons are
/// wrong copy or a wrong window, and both of those need a binary anyway because
/// the creative ships in the binary. A compiled window also self-expires
/// without anything having to stay up, which a remote flag does not.
///
/// The economics that originally accompanied this campaign (an App Store offer
/// code at a discounted annual price) were cancelled before launch: they were
/// priced against a $29.99 annual baseline that was never live. See
/// lpennant817.md. What survived is the timing, which needs no discount.
enum StretchRunCampaign {
    static let identifier = "stretch-run-2026"
    static let storageKey = "lastSeenStretchRun"

    /// Pacific, because the merchandising window tracks the baseball calendar
    /// and the season's last day is a Pacific-evening event.
    private static let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private static func pacific(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        // A window this campaign can't compute is a window it can't honor, so
        // fall back to a closed one rather than an open-ended one.
        return calendar.date(from: components) ?? .distantPast
    }

    /// Opens August 18, 2026, the day the build was cut. Deliberately not a
    /// future date: App Review turnaround is unknowable, and a card that opens
    /// after the release notes describing it are already live reads as a
    /// missing feature.
    static let starts = pacific(2026, 8, 18, 0, 0, 0)
    /// Closes at 11:59:59 p.m. Pacific on September 30, 2026, which is
    /// 2026-10-01T06:59:59Z. The regular season ends September 27 and the Wild
    /// Card round opens September 29, so this covers the whole run-in.
    static let ends = pacific(2026, 9, 30, 23, 59, 59)

    static func decision(
        now: Date,
        hasCompletedOnboarding: Bool,
        seenCampaign: String,
        customerStateResolved: Bool,
        isPro: Bool,
        forcePresentation: Bool = false
    ) -> StretchRunDecision {
        let creative: StretchRunCreative = isPro ? .pro : .upgrade

        if forcePresentation {
            return StretchRunDecision(creative: creative)
        }

        // `isPro` is false and `customerInfo` is nil until RevenueCat answers,
        // so rendering before then flashes an upgrade pitch at paying
        // subscribers. Wait for a real answer instead of trusting the default.
        guard customerStateResolved else { return .hidden }
        guard hasCompletedOnboarding else { return .hidden }
        // Unlike the update showcase, a user who arrives mid-onboarding is the
        // target for this card, so nothing is marked seen on the way past.
        guard seenCampaign != identifier else { return .hidden }
        guard now >= starts, now <= ends else { return .hidden }

        return StretchRunDecision(creative: creative)
    }

    static var isForced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["STATSCOUT_FORCE_STRETCH_RUN"] == "1"
        #else
        false
        #endif
    }
}

/// Inline dashboard card, not a modal. It sits in the leaderboard's scroll
/// content, so it never fights the full-screen update showcase and never costs
/// a `PaywallGate` presentation: the gate only starts counting when the sheet
/// it opens actually appears.
struct StretchRunCard: View {
    let creative: StretchRunCreative
    let onUpgrade: () -> Void
    let onOpenTrends: () -> Void
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
                Button(action: creative == .pro ? onOpenTrends : onUpgrade) {
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
        .accessibilityLabel("Stretch run")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 11, weight: .bold))
            Text("THE STRETCH RUN")
                .font(SavantType.micro)
                .tracking(1.4)
        }
        .foregroundStyle(SavantPalette.savantRed)
    }

    private var title: String {
        switch creative {
        case .upgrade: return "Know the players shaping October."
        case .pro:     return "Your stretch run toolkit is live."
        }
    }

    private var detail: String {
        switch creative {
        case .upgrade:
            return "The race is tightening. Catch who's heating up, test the matchups that decide games, and put today's run beside every season since 2015."
        case .pro:
            return "Open Trends for the league's biggest movers, or check recent form to catch a streak before the season totals do."
        }
    }

    private var ctaLabel: String {
        switch creative {
        case .upgrade: return "SCOUT THE STRETCH RUN"
        case .pro:     return "OPEN TRENDS"
        }
    }
}

#if DEBUG
#Preview("Upgrade") {
    StretchRunCard(creative: .upgrade, onUpgrade: {}, onOpenTrends: {}, onDismiss: {})
        .background(SavantPalette.canvas)
}

#Preview("Pro") {
    StretchRunCard(creative: .pro, onUpgrade: {}, onOpenTrends: {}, onDismiss: {})
        .background(SavantPalette.canvas)
}
#endif
