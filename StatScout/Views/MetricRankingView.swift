import SwiftUI

struct MetricRankingView: View {
    let metricLabel: String
    let metricCategory: MetricCategory
    let players: [Player]
    let season: Int?
    @State private var sortDescending: Bool

    init(metricLabel: String, metricCategory: MetricCategory, players: [Player], season: Int?) {
        self.metricLabel = metricLabel
        self.metricCategory = metricCategory
        self.players = players
        self.season = season
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
                SavantSectionBar(
                    title: "\(metricLabel) · \(metricCategory.rawValue)",
                    trailing: AnyView(
                        HStack(spacing: 12) {
                            if let season {
                                Text(String(season))
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
                        NavigationLink(value: player) {
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
        .navigationTitle("\(metricLabel) · \(metricCategory.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricPercentile(for player: Player) -> Int {
        player.metrics.first { $0.label == metricLabel && $0.category == metricCategory }?.percentile ?? 0
    }

}

#if DEBUG
#Preview {
    NavigationStack {
        MetricRankingView(metricLabel: "xwOBA", metricCategory: .hitting, players: SampleData.players, season: 2026)
    }
}
#endif
