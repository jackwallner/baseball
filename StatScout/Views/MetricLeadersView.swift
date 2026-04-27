import SwiftUI

struct MetricLeadersView: View {
    let metrics: [(label: String, category: MetricCategory, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)]
    @Environment(\.dismiss) private var dismiss

    private var groupedByCategory: [(MetricCategory, [(label: String, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)])] {
        let grouped = Dictionary(grouping: metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            let mapped = items.map { (label: $0.label, best: $0.best, worst: $0.worst) }
            return (cat, mapped)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("METRIC LEADERS")
                                .font(SavantType.playerName)
                                .foregroundStyle(SavantPalette.inkOnDark)
                            Text("Best & worst per Statcast metric")
                                .font(SavantType.small)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, SavantGeo.padPage)
                    .padding(.vertical, SavantGeo.padPage)
                    .background(SavantPalette.savantNavy)

                    if metrics.isEmpty {
                        ContentUnavailableView {
                            Label("No metric data", systemImage: "chart.bar")
                        } description: {
                            Text("Check back after the nightly update.")
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
                    }
                }
            }
            .background(SavantPalette.canvas.ignoresSafeArea())
            .navigationTitle("Leaders")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Player.self) { player in
                PlayerProfileView(player: player)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .tint(SavantPalette.ink)
    }

    private func categoryCard(_ group: (MetricCategory, [(label: String, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)])) -> some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: group.0.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("BEST")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("WORST")
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
                    Text(item.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let best = item.best {
                        NavigationLink(value: best.player) {
                            HStack(spacing: 6) {
                                PlayerHeadshot(url: best.player.headshotURL, initials: best.player.initials, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(best.player.name)
                                        .font(SavantType.smallBold)
                                        .foregroundStyle(SavantPalette.ink)
                                        .lineLimit(1)
                                    Text("\(best.value)")
                                        .font(SavantType.statSmall)
                                        .foregroundStyle(SavantPalette.pctlHot)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("—")
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                                    Text("\(worst.value)")
                                        .font(SavantType.statSmall)
                                        .foregroundStyle(SavantPalette.pctlCold)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("—")
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
    MetricLeadersView(metrics: [])
}
