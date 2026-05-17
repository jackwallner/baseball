import SwiftUI

/// Single home for every league-wide stat view. Folds the old Leaders,
/// Box Score, and StatScout-Best/Worst tabs into one place behind a top
/// segmented toggle so there's one obvious place to "look at stats" instead
/// of three competing tabs. Each mode's heavy data is only built when its
/// branch is selected (the `switch` doesn't instantiate the others), which
/// preserves the lazy-load behavior the old per-tab `selection ==` guards had.
struct StatsView: View {
    let viewModel: DashboardViewModel

    private enum Mode: String, CaseIterable {
        case leaders = "Leaders"
        case boxScore = "Box Score"
        case bestWorst = "Best/Worst"
    }

    @State private var mode: String = Mode.leaders.rawValue

    var body: some View {
        VStack(spacing: 0) {
            SavantTabs(tabs: Mode.allCases.map(\.rawValue), selected: $mode)

            switch Mode(rawValue: mode) ?? .leaders {
            case .leaders:
                DashboardView(viewModel: viewModel)
            case .boxScore:
                StandardStatsLeadersView(players: viewModel.qualifiedSeasonPlayers)
            case .bestWorst:
                MetricLeadersView(metrics: viewModel.allMetrics)
            }
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StatsView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
