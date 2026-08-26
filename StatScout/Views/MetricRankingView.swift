import SwiftUI

struct MetricRankingView: View {
    let metricLabel: String
    let metricCategory: MetricCategory
    let players: [Player]
    let season: Int?
    let phase: SeasonPhase
    @State private var sortDescending: Bool

    init(
        metricLabel: String,
        metricCategory: MetricCategory,
        players: [Player],
        season: Int?,
        phase: SeasonPhase = .regular
    ) {
        self.metricLabel = metricLabel
        self.metricCategory = metricCategory
        self.players = players
        self.season = season
        self.phase = phase
        // Default to "best first" for the active metric (descending for
        // higher-is-better, ascending for pitcher xwOBA / ERA / WHIP / etc.).
        // User can still flip via the header chevron.
        _sortDescending = State(initialValue: DashboardViewModel.defaultSortDescending(label: metricLabel, category: metricCategory))
    }

    /// Everyone who has the metric, ranked by percentile.
    ///
    /// This used to additionally require a parseable value string, which threw
    /// away every player on metrics the backend ships percentile-only. On Arm
    /// Strength and Squared-Up% that is 100% of players, so the page rendered
    /// "no players have this metric" for a metric the whole league has.
    private var rankedPlayers: [Player] {
        players
            .filter { player in
                player.metrics.contains { $0.label == metricLabel && $0.category == metricCategory }
            }
            .sorted(by: DashboardViewModel.metricComparator(
                label: metricLabel,
                category: metricCategory,
                descending: sortDescending
            ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if phase == .postseason {
                    PostseasonReferenceNote(referenceSeason: StatScoutSeason.current)
                }
                SavantSectionBar(
                    title: "\(metricLabel) · \(metricCategory.rawValue)",
                    trailing: AnyView(
                        HStack(spacing: 12) {
                            if let season {
                                Text(phase == .postseason
                                     ? "\(String(season)) Postseason"
                                     : String(season))
                                    .font(SavantType.micro)
                                    .foregroundStyle(SavantPalette.inkSecondary)
                            }
                            Button(action: {
                                sortDescending.toggle()
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }) {
                                HStack(spacing: 4) {
                                    Text(metricLabel)
                                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                                }
                                .font(SavantType.micro)
                                .foregroundStyle(SavantPalette.inkSecondary)
                            }
                        }
                    )
                )

                if rankedPlayers.isEmpty {
                    ContentUnavailableView {
                        Label("No rankings found", systemImage: "chart.bar")
                    } description: {
                        Text("No players have the \(metricLabel) metric for this season.")
                    }
                    .padding(.vertical, 24)
                } else {
                    // Sorted by raw stat value, header carries the metric label
                    // (e.g. "xwOBA") so the column matches what's in each row.
                    LeaderboardTableHeader(sortDescending: sortDescending, sortLabel: metricLabel)
                    ForEach(Array(rankedPlayers.enumerated()), id: \.element.id) { index, player in
                        NavigationLink(value: PlayerRoute(
                            player: player,
                            phase: phase,
                            season: season
                        )) {
                            LeaderboardTableRow(
                                rank: index + 1,
                                player: player,
                                metricLabel: metricLabel,
                                metricCategory: metricCategory
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                    .stroke(SavantPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Clearance for the floating tab bar, same as every other board.
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(
            phase == .postseason
                ? "\(metricLabel) · \(metricCategory.rawValue) Postseason"
                : "\(metricLabel) · \(metricCategory.rawValue)"
        )
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricPercentile(for player: Player) -> Int {
        player.metrics.first { $0.label == metricLabel && $0.category == metricCategory }?.percentile ?? 0
    }

}

/// The Statcast drill-down as a season-owning screen, so the year printed in its
/// header is also the year you can change from it. Mirrors
/// `StandardStatsLeaderboardScreen`.
struct MetricRankingScreen: View {
    let viewModel: DashboardViewModel
    let metricLabel: String
    let metricCategory: MetricCategory
    @State private var phase: SeasonPhase
    @State private var season: Int
    @State private var paywallTrigger: PaywallTrigger?

    init(
        viewModel: DashboardViewModel,
        metricLabel: String,
        metricCategory: MetricCategory,
        initialSeason: Int,
        phase: SeasonPhase = .regular
    ) {
        self.viewModel = viewModel
        self.metricLabel = metricLabel
        self.metricCategory = metricCategory
        _phase = State(initialValue: phase)
        _season = State(initialValue: initialSeason)
    }

    private var activePhase: SeasonPhase {
        phase == .postseason && season == StatScoutSeason.current ? .postseason : .regular
    }

    var body: some View {
        MetricRankingView(
            metricLabel: metricLabel,
            metricCategory: metricCategory,
            players: viewModel.players(forSeason: season, phase: activePhase),
            season: season,
            phase: activePhase
        )
        // Identity is the metric plus the season; without the season in the id
        // the sort-direction default wouldn't survive a year change.
        .id(season)
        .modifier(DrillDownSeasonPill(
            viewModel: viewModel,
            season: $season,
            paywallTrigger: $paywallTrigger,
            phase: $phase
        ))
        .task(id: season) {
            guard season != viewModel.selectedSeason else { return }
            await viewModel.loadHistoricalIfNeeded()
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        MetricRankingView(metricLabel: "xwOBA", metricCategory: .hitting, players: SampleData.players, season: 2026)
    }
}
#endif
