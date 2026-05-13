import SwiftUI

typealias MetricLeaderEntry = (label: String, category: MetricCategory, best: (player: Player, percentile: Int, actualValue: String)?, worst: (player: Player, percentile: Int, actualValue: String)?)

struct MetricLeadersView: View {
    @EnvironmentObject private var store: StoreService
    let metrics: [MetricLeaderEntry]

    private var groupedByCategory: [(MetricCategory, [MetricLeaderEntry])] {
        let grouped = Dictionary(grouping: metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if metrics.isEmpty {
                    ContentUnavailableView {
                        Label("No metric data", systemImage: "chart.bar")
                    } description: {
                        Text("No metrics are available for the current season.")
                    }
                    .padding(.vertical, 48)
                } else {
                    VStack(spacing: 12) {
                        ForEach(groupedByCategory, id: \.0) { group in
                            categoryCard(group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryCard(_ group: (MetricCategory, [MetricLeaderEntry])) -> some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: group.0.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 88, alignment: .leading)
                Text("BEST")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("LOWEST")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: SavantGeo.rowHeightHeader)
            .padding(.horizontal, SavantGeo.padInline)
            .background(SavantPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(group.1.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    NavigationLink(value: MetricRoute(label: item.label, category: item.category)) {
                        HStack(spacing: 2) {
                            Text(item.label)
                                .font(SavantType.smallBold)
                                .foregroundStyle(SavantPalette.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                        .frame(width: 88, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if let best = item.best {
                        NavigationLink(value: best.player) {
                            HStack(spacing: 6) {
                                PlayerHeadshot(url: best.player.headshotURL, initials: best.player.initials, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(best.player.name)
                                        .font(SavantType.smallBold)
                                        .foregroundStyle(SavantPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(best.actualValue)
                                        .font(SavantType.statSmall)
                                        .foregroundStyle(SavantPalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("No qualified players")
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }

                    if let worst = item.worst {
                        NavigationLink(value: worst.player) {
                            HStack(spacing: 6) {
                                PlayerHeadshot(url: worst.player.headshotURL, initials: worst.player.initials, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(worst.player.name)
                                        .font(SavantType.smallBold)
                                        .foregroundStyle(SavantPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(worst.actualValue)
                                        .font(SavantType.statSmall)
                                        .foregroundStyle(SavantPalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("No qualified players")
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .frame(height: SavantGeo.rowHeight)
                .padding(.horizontal, SavantGeo.padInline)
                .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                    alignment: .bottom
                )
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

#Preview {
    NavigationStack {
        MetricLeadersView(metrics: [])
            .environmentObject(StoreService.shared)
    }
}
