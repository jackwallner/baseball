import SwiftUI

struct PlayerProfileView: View {
    let player: Player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        PercentileBadge(percentile: player.overallPercentile)
                        Text(player.name)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(player.team) · \(player.position) · \(player.handedness)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(StatScoutTheme.stroke))

                    SectionHeader(title: "Percentile profile", subtitle: "How the underlying tools stack up right now")

                    VStack(spacing: 14) {
                        ForEach(player.metrics) { metric in
                            MetricBar(metric: metric)
                                .padding(16)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }

                    SectionHeader(title: "Game-to-game notes", subtitle: "Short-form context built for quick nightly reads")

                    VStack(spacing: 12) {
                        ForEach(player.games) { game in
                            GameTrendCard(game: game)
                        }
                    }
                }
                .padding(20)
            }
            .background(StatScoutTheme.background.ignoresSafeArea())
            .toolbar {
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
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(StatScoutTheme.accent, in: Capsule())
        }
        .padding(16)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(StatScoutTheme.stroke))
    }
}

#Preview {
    PlayerProfileView(player: SampleData.players[0])
}
