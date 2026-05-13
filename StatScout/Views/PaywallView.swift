import SwiftUI
import RevenueCatUI

enum PaywallTrigger: Identifiable {
    var id: Self { self }

    case pastSeason
    case yearCompare
    case playerComparison
    case onboarding
    case upgrade
    case pastSeasonsLoad
    case teamView

    var icon: String {
        switch self {
        case .pastSeason:        return "calendar.badge.clock"
        case .yearCompare:       return "arrow.left.arrow.right.circle.fill"
        case .playerComparison:  return "person.2.fill"
        case .onboarding:        return "crown.fill"
        case .upgrade:           return "crown.fill"
        case .pastSeasonsLoad:   return "clock.arrow.circlepath"
        case .teamView:          return "shield.lefthalf.filled"
        }
    }

    var title: String {
        switch self {
        case .pastSeason:        return "Unlock Past Seasons"
        case .yearCompare:       return "Year-over-Year Comparison"
        case .playerComparison:  return "Player Comparison"
        case .onboarding:        return "Go Pro"
        case .upgrade:           return "StatScout Pro"
        case .pastSeasonsLoad:   return "Load Past Seasons"
        case .teamView:          return "Team Insights"
        }
    }

    var subtitle: String {
        switch self {
        case .pastSeason:
            return "See how your favorite players ranked in previous seasons. Track the trends that tell the full story."
        case .yearCompare:
            return "Compare a player's percentile rankings across any two seasons. See what changed, what held, and where they're headed."
        case .playerComparison:
            return "Compare any two players side by side across every metric. Find who leads in xwOBA, Barrel%, Sprint Speed, and more."
        case .onboarding:
            return "Current season is free. Pro unlocks historical seasons, year-over-year comparisons, and head-to-head player matchups."
        case .upgrade:
            return "Unlock historical seasons and year-over-year comparisons."
        case .pastSeasonsLoad:
            return "Load historical data to explore past seasons, year-over-year trends, and more."
        case .teamView:
            return "Get full team rosters, player breakdowns, and side-by-side comparisons for every squad."
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    let trigger: PaywallTrigger

    init(trigger: PaywallTrigger = .upgrade) {
        self.trigger = trigger
    }

    var body: some View {
        VStack(spacing: 0) {
            triggerHeader

            Group {
                if let offering = store.currentOffering {
                    RevenueCatUI.PaywallView(offering: offering)
                } else {
                    RevenueCatUI.PaywallView()
                }
            }
        }
        .task {
            if store.currentOffering == nil {
                await store.fetchProducts()
            }
        }
    }

    private var triggerHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: trigger.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(trigger.title)
                    .font(SavantType.smallBold)
            }
            .foregroundStyle(SavantPalette.savantRed)

            Text(trigger.subtitle)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let trialLabel = trialLabel {
                Text(trialLabel)
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(SavantPalette.savantRed)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surfaceAlt)
    }

    private var trialLabel: String? {
        let yearlyTrial = store.products
            .first(where: { $0.productKind == .yearly })?
            .introOfferLabel
        guard let yearlyTrial else { return nil }
        return "Yearly plan includes a \(yearlyTrial) — cancel anytime before it ends."
    }
}
