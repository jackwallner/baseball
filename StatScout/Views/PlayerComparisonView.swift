import SwiftUI

struct ComparisonRoute: Hashable, Identifiable {
    let playerA: Player
    let playerB: Player
    var id: String { "\(playerA.id)-vs-\(playerB.id)" }
}

struct PlayerComparisonView: View {
    @EnvironmentObject private var store: StoreService
    let playerA: Player
    let playerB: Player
    @State private var showingPaywall = false

    private var comparisonMetrics: [(label: String, category: MetricCategory, a: Metric?, b: Metric?)] {
        var seen = Set<String>()
        var result: [(label: String, category: MetricCategory, a: Metric?, b: Metric?)] = []
        let allMetrics = playerA.metrics + playerB.metrics
        for metric in allMetrics {
            let key = "\(metric.label)|\(metric.category.rawValue)"
            guard seen.insert(key).inserted else { continue }
            let a = playerA.metrics.first { $0.label == metric.label && $0.category == metric.category }
            let b = playerB.metrics.first { $0.label == metric.label && $0.category == metric.category }
            result.append((metric.label, metric.category, a, b))
        }
        return result.sorted { $0.category == $1.category
            ? $0.category.sortMetrics($0.label, $1.label)
            : MetricCategory.allCases.firstIndex(of: $0.category)! < MetricCategory.allCases.firstIndex(of: $1.category)!
        }
    }

    private var groupedComparison: [(MetricCategory, [(label: String, a: Metric?, b: Metric?)])] {
        let grouped = Dictionary(grouping: comparisonMetrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            let mapped = items.map { (label: $0.label, a: $0.a, b: $0.b) }
            return (cat, mapped)
        }
    }

    var body: some View {
        if store.isPro {
            comparisonContent
        } else {
            ZStack(alignment: .bottom) {
                comparisonContent
                    .blur(radius: 8)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, SavantPalette.canvas.opacity(0.9)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
                    .clipped()

                // CTA overlay
                VStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.yellow)

                    Text("Find the Edge")
                        .font(SavantType.cardTitle)
                        .foregroundStyle(SavantPalette.ink)

                    Text("Pro unlocks side-by-side player comparisons across every metric. See who leads in xwOBA, Barrel%, Sprint Speed, and more.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showingPaywall = true
                    } label: {
                        Text(store.proPrice.map { "Unlock Pro — \($0)" } ?? "Unlock Pro")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(SavantPalette.savantRed)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                        .fill(SavantPalette.surface)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(SavantPalette.divider)
                        .frame(height: SavantGeo.hairline)
                }
                .offset(y: -8)
            }
            .background(SavantPalette.canvas.ignoresSafeArea())
            .sheet(isPresented: $showingPaywall) {
                PaywallView(trigger: .playerComparison)
            }
        }
    }

    private var comparisonContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                playerHeadlines
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if comparisonMetrics.isEmpty {
                    ContentUnavailableView {
                        Label("No comparable metrics", systemImage: "chart.bar")
                    } description: {
                        Text("These players don't share any common metrics.")
                    }
                    .padding(.vertical, 48)
                } else {
                    ForEach(groupedComparison, id: \.0) { category, metrics in
                        categoryCard(category: category, metrics: metrics)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle("Player Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var playerHeadlines: some View {
        HStack(spacing: 12) {
            playerSummaryCard(player: playerA, label: "A")
            playerSummaryCard(player: playerB, label: "B")
        }
    }

    private func playerSummaryCard(player: Player, label: String) -> some View {
        VStack(spacing: 8) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 56)
            Text(player.name)
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(player.team) · \(player.displayPosition)")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func categoryCard(category: MetricCategory, metrics: [(label: String, a: Metric?, b: Metric?)]) -> some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: category.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 72, alignment: .leading)
                Text(playerA.name.split(separator: " ").last.map(String.init) ?? "A")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(playerB.name.split(separator: " ").last.map(String.init) ?? "B")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: SavantGeo.rowHeightHeader)
            .padding(.horizontal, SavantGeo.padInline)
            .background(SavantPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                        .frame(width: 72, alignment: .leading)

                    metricValueCell(metric: item.a, other: item.b)
                    metricValueCell(metric: item.b, other: item.a)
                }
                .frame(height: 56)
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

    private func metricValueCell(metric: Metric?, other: Metric?) -> some View {
        Group {
            if let m = metric {
                let isWinner = (other.map { m.percentile > $0.percentile }) ?? false
                let pctColor = SavantPalette.color(forPercentile: m.percentile)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if isWinner {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                        Text(m.value)
                            .font(SavantType.statSmall)
                            .foregroundStyle(SavantPalette.ink)
                            .lineLimit(1)
                    }
                    Text("\(m.percentile)%")
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pctColor)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("—")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerComparisonView(
            playerA: SampleData.players.first!,
            playerB: SampleData.players.last!
        )
        .environmentObject(StoreService.shared)
    }
}
#endif
