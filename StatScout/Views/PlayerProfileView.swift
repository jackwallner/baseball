import SwiftUI

struct PlayerProfileView: View {
    let player: Player
    @Environment(\.dismiss) private var dismiss

    private var groupedMetrics: [(category: MetricCategory, metrics: [Metric])] {
        let grouped = Dictionary(grouping: player.metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let m = grouped[cat], !m.isEmpty else { return nil }
            return (category: cat, metrics: m.sorted { $0.percentile > $1.percentile })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SavantPlayerHeader(player: player)

                    ForEach(groupedMetrics, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(group.category.rawValue)
                                    .font(.title3.weight(.black))
                                    .foregroundStyle(.white)
                                Spacer()
                                if let avg = player.percentile(for: group.category) {
                                    Text("Avg \(avg)")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(StatScoutTheme.percentileColor(avg))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.06), in: Capsule())
                                }
                            }

                            VStack(spacing: 10) {
                                ForEach(group.metrics) { metric in
                                    MetricBar(metric: metric)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    if !player.games.isEmpty {
                        SectionHeader(title: "Recent Games", subtitle: "Game-to-game trends and context")

                        VStack(spacing: 12) {
                            ForEach(player.games) { game in
                                GameTrendCard(game: game)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(StatScoutTheme.background.ignoresSafeArea())
            .navigationTitle(player.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: player.shareSummary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}

struct GameTrendCard: View {
    let game: GameTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.56))
                Text("vs \(game.opponent)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(StatScoutTheme.accent)
                Spacer()
                Text(game.percentileDelta >= 0 ? "+\(game.percentileDelta)" : "\(game.percentileDelta)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(game.percentileDelta >= 0 ? .green : .orange)
            }

            Text(game.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            Text(game.keyMetric)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(StatScoutTheme.accent, in: Capsule())

            Text("Percentile change since previous game")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(StatScoutTheme.stroke))
    }
}

#Preview {
    PlayerProfileView(player: SampleData.players[0])
}
