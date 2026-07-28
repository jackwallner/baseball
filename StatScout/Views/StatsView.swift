import SwiftUI

/// Advanced / Standard is the same split the player and team pages use,
/// Statcast's expected stats against the box score. Naming them "Leaders" and
/// "Box Score" made the two leaderboards look like different kinds of thing
/// when they're the same list read in two vocabularies.
enum StatsMode: String, CaseIterable, Identifiable {
    case leaders = "Advanced"
    case boxScore = "Standard"
    case bestWorst = "Best/Worst"
    var id: String { rawValue }
}

/// The Advanced / Standard chooser, as a chip.
///
/// It spent a while in the nav bar, first as bare text (which read as a title,
/// so nobody tapped it) and then as a pill, which iOS dropped: that bar already
/// carries the season, the settings gear and the upgrade CTA, and an overfull
/// toolbar answers by folding items away. Down here it sits with the other
/// controls that change what the board shows, at the same size and shape as
/// them, and it can't be dropped.
struct StatsModeMenu: View {
    @Binding var mode: StatsMode

    var body: some View {
        Menu {
            ForEach(StatsMode.allCases) { option in
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
            SavantChip(
                title: mode.rawValue,
                systemImage: "chart.bar.doc.horizontal",
                trailing: .chevron,
                isActive: true
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("View")
        .accessibilityValue(mode.rawValue)
    }
}

/// Single home for every league-wide stat view. Folds the old Leaders, Box
/// Score, and StatScout-Best/Worst tabs into one place. The season selector
/// sits in the leading toolbar slot and the mode chooser rides in the board's
/// own control row, so both apply across every mode and the scroll content
/// keeps its full height. Each mode's heavy data is only built when its branch
/// is selected (the `switch` doesn't instantiate the others), which preserves
/// the lazy-load behavior the old per-tab guards had.
struct StatsView: View {
    let viewModel: DashboardViewModel
    @EnvironmentObject private var store: StoreService

    @State private var mode: StatsMode = .leaders
    @State private var paywallTrigger: PaywallTrigger?

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .leaders:
                // The advanced board hosts the chip in its own control row, so
                // it costs no vertical space on the screen people live on.
                DashboardView(viewModel: viewModel, statsMode: $mode)
            case .boxScore:
                // Same deal as the advanced board: the chip lives in this
                // board's own control row, under its own category tabs, so
                // switching modes doesn't reshuffle the header.
                StandardStatsLeadersView(
                    players: viewModel.qualifiedSeasonPlayers,
                    statsMode: $mode
                )
            case .bestWorst:
                modeRow
                MetricLeadersView(metrics: viewModel.allMetrics)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SavantPalette.canvas)
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

    /// Standalone row for the two modes that have no control row of their own.
    private var modeRow: some View {
        HStack(spacing: 8) {
            StatsModeMenu(mode: $mode)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
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

#if DEBUG
#Preview {
    NavigationStack {
        StatsView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
