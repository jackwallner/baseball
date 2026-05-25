import SwiftUI

/// Single home for every league-wide stat view. Folds the old Leaders,
/// Box Score, and StatScout-Best/Worst tabs into one place. The mode lives in
/// the nav-bar title as a dropdown (Weather-app style) and the season selector
/// sits in the leading toolbar slot, so both apply across every mode and the
/// scroll content keeps its full height. Each mode's heavy data is only built
/// when its branch is selected (the `switch` doesn't instantiate the others),
/// which preserves the lazy-load behavior the old per-tab guards had.
struct StatsView: View {
    let viewModel: DashboardViewModel
    @EnvironmentObject private var store: StoreService

    private enum Mode: String, CaseIterable, Identifiable {
        case leaders = "Leaders"
        case boxScore = "Box Score"
        case bestWorst = "Best/Worst"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .leaders
    @State private var paywallTrigger: PaywallTrigger?

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .leaders:
                DashboardView(viewModel: viewModel)
            case .boxScore:
                StandardStatsLeadersView(players: viewModel.qualifiedSeasonPlayers)
            case .bestWorst:
                MetricLeadersView(metrics: viewModel.allMetrics)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SavantPalette.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { seasonMenu }
            ToolbarItem(placement: .principal) { modeMenu }
        }
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
    }

    // Nav-title dropdown that swaps between Leaders / Box Score / Best-Worst.
    // Replaces the old full-width segmented tab row.
    private var modeMenu: some View {
        Menu {
            ForEach(Mode.allCases) { option in
                Button {
                    mode = option
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if option == mode {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(mode.rawValue)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .menuOrder(.fixed)
        .accessibilityLabel("View")
        .accessibilityValue(mode.rawValue)
    }

    // Compact season selector for the leading toolbar slot. Sits on the navy
    // nav bar, so it reads as a red pill with the year only.
    private var seasonMenu: some View {
        Menu {
            if viewModel.isHistoricalLoading {
                Label("Loading past seasons…", systemImage: "hourglass")
            } else if !viewModel.hasLoadedHistorical {
                Button {
                    if store.isPro {
                        Task { await viewModel.loadHistoricalIfNeeded() }
                    } else if PaywallGate.shared.shouldPresent(.pastSeasonsLoad) {
                        paywallTrigger = .pastSeasonsLoad
                    }
                } label: {
                    Label(store.isPro ? "Load past seasons" : "Past seasons require Pro", systemImage: store.isPro ? "clock.arrow.circlepath" : "crown.fill")
                }
            }
            ForEach(viewModel.availableSeasons, id: \.self) { season in
                let isLocked = viewModel.isSeasonLocked(season)
                Button {
                    if isLocked {
                        if PaywallGate.shared.shouldPresent(.pastSeason) { paywallTrigger = .pastSeason }
                    } else {
                        viewModel.selectedSeason = season
                    }
                } label: {
                    HStack {
                        Text(String(season))
                        if isLocked {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(viewModel.selectedSeason))
                    .font(SavantType.smallBold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SavantPalette.savantRed)
            .clipShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Season")
        .accessibilityValue(String(viewModel.selectedSeason))
        .accessibilityHint("Choose which season's stats to view")
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
