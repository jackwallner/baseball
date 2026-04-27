import SwiftUI

struct MetricRankingView: View {
    let metricLabel: String
    let players: [Player]

    private var rankedPlayers: [Player] {
        players.filter { player in
            player.metrics.contains { $0.label == metricLabel }
        }
        .sorted {
            metricPercentile(for: $0) > metricPercentile(for: $1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SavantSectionBar(title: metricLabel)

                if rankedPlayers.isEmpty {
                    ContentUnavailableView {
                        Label("No rankings found", systemImage: "chart.bar")
                    } description: {
                        Text("Check back after the nightly update.")
                    }
                    .padding(.vertical, 24)
                } else {
                    LeaderboardTableHeader()
                    ForEach(Array(rankedPlayers.enumerated()), id: \.element.id) { index, player in
                        NavigationLink(value: player) {
                            LeaderboardTableRow(
                                rank: index + 1,
                                player: player,
                                metricLabel: metricLabel
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
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(metricLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricPercentile(for player: Player) -> Int {
        player.metrics.first { $0.label == metricLabel }?.percentile ?? 0
    }
}

#Preview {
    NavigationStack {
        MetricRankingView(metricLabel: "xwOBA", players: SampleData.players)
    }
}
