import SwiftUI

struct PlayerProfileView: View {
    let player: Player
    @State private var selectedTab = "Advanced"

    private var seasonLabel: String {
        player.season.map(String.init) ?? "Season"
    }

    private var groupedMetrics: [(category: MetricCategory, metrics: [Metric])] {
        let grouped = Dictionary(grouping: player.metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let m = grouped[cat], !m.isEmpty else { return nil }
            return (category: cat, metrics: m.sorted { $0.percentile > $1.percentile })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlayerIdentityStrip(player: player)

                SavantTabs(
                    tabs: ["Standard", "Advanced"],
                    selected: $selectedTab
                )

                switch selectedTab {
                case "Advanced":
                    statcastContent
                case "Standard":
                    standardContent
                default:
                    statcastContent
                }
            }
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: player.shareSummary)
            }
        }
    }

    private var statcastContent: some View {
        VStack(spacing: 12) {
            percentileRankingsCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var standardContent: some View {
        VStack(spacing: 12) {
            standardStatsGridCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Cards

    private var percentileRankingsCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "PERCENTILE RANKINGS",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        Text(seasonLabel)
                            .font(SavantType.micro)
                            .tracking(0.5)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        Text("ⓘ")
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.linkBlue)
                    }
                )
            )

            ForEach(groupedMetrics, id: \.category) { group in
                let avg = player.percentile(for: group.category)
                SavantSubSectionBar(
                    title: "\(group.category.rawValue.uppercased())",
                    trailing: avg.map { "AVG \($0)" },
                    trailingColor: avg.map { SavantPalette.color(forPercentile: $0) } ?? SavantPalette.inkSecondary
                )

                ForEach(Array(group.metrics.enumerated()), id: \.element.id) { index, metric in
                    NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
                        MetricBar(metric: metric)
                            .padding(.horizontal, SavantGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                            .overlay(
                                Rectangle()
                                    .fill(SavantPalette.divider)
                                    .frame(height: SavantGeo.hairline),
                                alignment: .bottom
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
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "STANDARD STATS · \(seasonLabel)")

            if (player.standardStats ?? []).isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "Standard stats unavailable",
                    description: "Traditional stats are not available for this player in the current data feed."
                )
                .padding(.vertical, 24)
            } else {
                let cols = (player.standardStats ?? []).chunked(into: 2)
                ForEach(Array(cols.enumerated()), id: \.offset) { rowIndex, pair in
                    HStack(spacing: 0) {
                        ForEach(Array(pair.enumerated()), id: \.element.id) { colIndex, stat in
                            HStack {
                                Text(stat.label)
                                    .font(SavantType.micro)
                                    .tracking(0.4)
                                    .foregroundStyle(SavantPalette.inkTertiary)
                                Spacer()
                                Text(stat.value)
                                    .font(SavantType.statMed)
                                    .foregroundStyle(SavantPalette.ink)
                            }
                            .padding(.horizontal, SavantGeo.padCard)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background((rowIndex * 2 + colIndex) % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                            .overlay(
                                Rectangle()
                                    .fill(SavantPalette.divider)
                                    .frame(height: SavantGeo.hairline),
                                alignment: .bottom
                            )
                            .overlay(
                                Rectangle()
                                    .fill(SavantPalette.divider)
                                    .frame(width: SavantGeo.hairline)
                                    .opacity(colIndex > 0 ? 1 : 0),
                                alignment: .leading
                            )
                        }
                    }
                }
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    NavigationStack {
        PlayerProfileView(player: SampleData.players[0])
    }
}
