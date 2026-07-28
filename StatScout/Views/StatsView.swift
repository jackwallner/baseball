import SwiftUI

/// The bindings the two leaderboards share when they're hosted by `StatsView`.
///
/// Both boards draw the same control row, and that row can move the user
/// between them (picking AVG from the Statcast board lands on the standard
/// one), so the selection has to live above both. Absent means the board is
/// standalone, pushed as its own screen from a drill-down, and owns its state.
struct StatsBoardBindings {
    @Binding var board: StatsBoard
    @Binding var standardStat: String
    /// Direction for the standard board. The advanced board's lives in the
    /// view model, which also tracks whether the user pinned it.
    @Binding var standardSortDescending: Bool
}

/// Single home for every league-wide stat view. Folds the old Leaders, Box
/// Score, and StatScout-Best/Worst tabs into one place. The season selector
/// sits in the leading toolbar slot and every other control rides in the
/// board's own row, so both apply across every mode and the scroll content
/// keeps its full height. Each mode's heavy data is only built when its branch
/// is selected (the `switch` doesn't instantiate the others), which preserves
/// the lazy-load behavior the old per-tab guards had.
struct StatsView: View {
    let viewModel: DashboardViewModel
    @EnvironmentObject private var store: StoreService

    @State private var board: StatsBoard = .advanced
    @State private var standardStat = "AVG"
    @State private var standardSortDescending = true
    @State private var paywallTrigger: PaywallTrigger?

    private var category: MetricCategory { viewModel.selectedCategory ?? .hitting }

    private var bindings: StatsBoardBindings {
        StatsBoardBindings(
            board: $board,
            standardStat: $standardStat,
            standardSortDescending: $standardSortDescending
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            switch board {
            case .advanced:
                DashboardView(viewModel: viewModel, boardBindings: bindings)
            case .standard:
                StandardStatsLeadersView(
                    players: standardBoardPlayers,
                    selectedStat: $standardStat,
                    selectedCategory: categoryBinding,
                    sortDescending: $standardSortDescending,
                    boardBindings: bindings,
                    viewModel: viewModel
                )
            case .bestWorst:
                BestWorstBoard(viewModel: viewModel, bindings: bindings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SavantPalette.canvas)
        // A category the standard board has no stats for would otherwise leave
        // the board ranking by a stat that isn't in its own menu.
        .onChange(of: viewModel.selectedCategory) { _, _ in
            guard !StandardStatCatalog.stats(for: category).contains(standardStat) else { return }
            standardStat = StandardStatCatalog.defaultStat(for: category)
            standardSortDescending = StandardStatCatalog.defaultDescending(for: standardStat, category: category)
        }
        .toolbar {
            // The season pill draws its own red capsule; iOS 26 wraps toolbar
            // items in a Liquid Glass capsule of their own, which stacks into a
            // washed-out double-pill. Hide the system one where it exists.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { seasonMenu }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { seasonMenu }
            }
        }
        // Contextual past-season pitches route through the low-friction
        // TrialPitchSheet (its CTA starts the yearly trial directly), not the
        // full multi-plan PaywallView.
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    /// The standard board reads the same qualifier and position filter as the
    /// advanced one, so switching vocabularies doesn't silently widen the pool.
    private var standardBoardPlayers: [Player] {
        let players = viewModel.qualifiedSeasonPlayers
        guard viewModel.positionFilterApplies, viewModel.positionFilter != .all else { return players }
        return players.filter { viewModel.positionFilter.matches($0) }
    }

    private var categoryBinding: Binding<MetricCategory> {
        Binding(
            get: { viewModel.selectedCategory ?? .hitting },
            set: { viewModel.selectedCategory = $0 }
        )
    }

    // Compact season selector for the leading toolbar slot. Sits on the navy
    // nav bar, so it reads as a red pill with the year only.
    private var seasonMenu: some View {
        SeasonMenu(
            seasons: viewModel.availableSeasons,
            selected: viewModel.selectedSeason,
            isLocked: { viewModel.isSeasonLocked($0) },
            onSelect: { season in
                if viewModel.isSeasonLocked(season) {
                    // Explicit tap on a locked year, always answer it; the
                    // gate only caps automatic pop-ups.
                    paywallTrigger = .lockedSeason(season)
                } else {
                    viewModel.selectedSeason = season
                }
            }
        ) {
            // No calendar glyph here: this bar also carries the title, the gear
            // and the upgrade CTA, and on a 375pt phone the glyph is what
            // pushes "Stats" into an ellipsis.
            SavantNavPill(title: String(viewModel.selectedSeason))
        }
        .accessibilityHint("Choose which season's stats to view")
    }
}

/// Best & Worst, with the same control row as the boards either side of it and
/// the same blur gate the rest of the app uses for StatScout+ content.
///
/// Free users can reach it and see it exists, which is the point of a blur
/// rather than a hidden menu item: the shape of the answer is visible, the
/// answer isn't.
private struct BestWorstBoard: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    let bindings: StatsBoardBindings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatsViewMenu(
                    viewModel: viewModel,
                    board: bindings.$board,
                    standardStat: bindings.$standardStat,
                    sortDescending: bindings.$standardSortDescending
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if store.isPro {
                MetricLeadersView(metrics: viewModel.allMetrics)
            } else {
                ZStack(alignment: .bottom) {
                    MetricLeadersView(metrics: viewModel.allMetrics)
                        .blur(radius: 8)
                        .allowsHitTesting(false)
                    BlurGateUnlock(
                        headline: "See who leads and who trails on every metric in the league",
                        trigger: .bestWorst
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 100)
                }
            }
        }
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
