import SwiftUI

struct YearComparisonView: View {
    let history: [Player]
    /// The baseline season, on the left, and the season being read against it,
    /// on the right. They used to be sorted into "recent" and "prior" by
    /// `max`/`min`, which meant the two menus were interchangeable and the
    /// direction of the comparison couldn't be chosen at all.
    @State private var fromYear: Int = 0
    @State private var toYear: Int = 0

    private var availableYears: [Int] {
        history.compactMap(\.season).uniqued().sorted(by: >)
    }

    private var playerTo: Player? {
        history.first { $0.season == toYear }
    }

    private var playerFrom: Player? {
        history.first { $0.season == fromYear }
    }

    var body: some View {
        VStack(spacing: 12) {
            yearPickerCard

            if let p1 = playerTo, let p2 = playerFrom {
                overallChangeCard(p1: p1, p2: p2)
                comparisonContent(p1: p1, p2: p2)
            } else {
                noDataView
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .onAppear(perform: snapSelections)
    }

    /// Defaults read left to right in time: the season before last on the left,
    /// the newest on the right.
    private func snapSelections() {
        let years = availableYears
        guard !years.isEmpty else { return }
        if !years.contains(toYear) { toYear = years.first ?? 0 }
        if !years.contains(fromYear) || fromYear == toYear {
            fromYear = years.first(where: { $0 != toYear }) ?? fromYear
        }
    }

    private var noDataView: some View {
        ContentUnavailableView {
            Label("No Data Available", systemImage: "calendar.badge.clock")
        } description: {
            Text(availableYears.isEmpty
                 ? "No historical data is available for this player."
                 : "Data for \(String(fromYear)) or \(String(toYear)) is not available.")
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

    // MARK: - Year Picker Card

    private var yearPickerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                yearButton(year: $fromYear, otherYear: toYear, caption: "From",
                           label: fromYear > 0 ? String(fromYear) : "Select")
                // Flips which season is the baseline and which is the result,
                // one tap instead of two menus. The table below re-labels
                // itself, so a "how far has he come" reading and a "what has
                // he lost" reading are the same tap apart.
                Button {
                    let held = fromYear
                    fromYear = toYear
                    toYear = held
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(width: 34, height: 34)
                        .background(SavantPalette.surfaceAlt)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap the two seasons")
                yearButton(year: $toYear, otherYear: fromYear, caption: "To",
                           label: toYear > 0 ? String(toYear) : "Select")
            }
        }
        .padding(16)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func yearButton(year: Binding<Int>, otherYear: Int, caption: String, label: String) -> some View {
        Menu {
            ForEach(availableYears.filter { $0 != otherYear }, id: \.self) { y in
                Button {
                    year.wrappedValue = y
                } label: {
                    HStack {
                        Text(String(y))
                        if year.wrappedValue == y {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(SavantType.statLarge)
                    .foregroundStyle(SavantPalette.ink)
                Text(caption)
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(SavantPalette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            .overlay(
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .padding(.trailing, 8)
                },
                alignment: .trailing
            )
        }
    }

    // MARK: - Overall Change Card

    private func overallChangeCard(p1: Player, p2: Player) -> some View {
        let delta = p1.overallPercentile - p2.overallPercentile
        let isUp = delta > 0
        let isDown = delta < 0
        let color: Color = isUp ? .green : (isDown ? SavantPalette.savantRed : SavantPalette.inkSecondary)
        let icon = isUp ? "arrow.up.circle.fill" : (isDown ? "arrow.down.circle.fill" : "minus.circle.fill")

        return HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("Overall Average")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
                Text("\(p2.overallPercentile)% (\(String(fromYear))) → \(p1.overallPercentile)% (\(String(toYear)))")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
            }

            Spacer()

            HStack(spacing: 2) {
                Text(isUp ? "+\(delta)%" : "\(delta)%")
                    .font(SavantType.statLarge)
            }
            .foregroundStyle(color)
        }
        .padding(16)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Comparison Content

    private func comparisonContent(p1: Player, p2: Player) -> some View {
        let comparisons = buildComparisons(p1: p1, p2: p2)
        let grouped = Dictionary(grouping: comparisons) { $0.category }

        if comparisons.isEmpty {
            return AnyView(noMetricsView)
        }

        return AnyView(
            LazyVStack(spacing: 12) {
                ForEach(MetricCategory.allCases, id: \.self) { category in
                    if let items = grouped[category], !items.isEmpty {
                        categoryCard(category: category, items: items)
                    }
                }
            }
        )
    }

    private var noMetricsView: some View {
        ContentUnavailableView {
            Label("No Comparable Metrics", systemImage: "chart.bar.xaxis")
        } description: {
            Text("These seasons don't have overlapping metrics to compare.")
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

    // MARK: - Category Card

    private func categoryCard(category: MetricCategory, items: [MetricComparison]) -> some View {
        VStack(spacing: 0) {
            SavantSubSectionBar(title: category.rawValue.uppercased())

            columnHeader

            ForEach(Array(items.enumerated()), id: \.element.metricLabel) { idx, item in
                comparisonRow(item: item, isAlt: idx % 2 == 1)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Metric")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(fromYear))
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 72)

            Text(String(toYear))
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 72)

            Text("Δ")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 48)
        }
        .padding(.horizontal, SavantGeo.padInline)
        .frame(height: 28)
        .background(SavantPalette.surfaceAlt)
    }

    private func comparisonRow(item: MetricComparison, isAlt: Bool) -> some View {
        let isUp = item.change > 0
        let isDown = item.change < 0
        let deltaColor: Color = isUp ? .green : (isDown ? SavantPalette.savantRed : SavantPalette.inkSecondary)
        let arrow = isUp ? "↑" : (isDown ? "↓" : "→")

        return HStack(spacing: 0) {
            // Metric label
            Text(item.metricLabel)
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // Prior year (earlier)
            yearValueColumn(
                percentile: item.percentileB,
                value: item.valueB,
                isFaded: true
            )
            .frame(width: 72)

            // Recent year (later) - emphasized with color
            yearValueColumn(
                percentile: item.percentileA,
                value: item.valueA,
                isFaded: false
            )
            .frame(width: 72)

            // Delta (in percentile points)
            HStack(spacing: 2) {
                Text(arrow)
                    .font(SavantFont.condensed(12, weight: .bold))
                Text("\(abs(item.change))%")
                    .font(SavantType.bodyBold)
            }
            .foregroundStyle(deltaColor)
            .frame(width: 48)
        }
        .frame(height: 48)
        .padding(.horizontal, SavantGeo.padInline)
        .background(isAlt ? SavantPalette.surfaceAlt : SavantPalette.surface)
        .overlay(
            Rectangle()
                .fill(SavantPalette.divider)
                .frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
    }

    private func yearValueColumn(percentile: Int, value: String, isFaded: Bool) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text("\(percentile)")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(isFaded ? SavantPalette.inkTertiary : SavantPalette.textColor(forPercentile: percentile))
                // Mini bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(SavantPalette.color(forPercentile: percentile))
                    .frame(width: CGFloat(percentile) * 0.3, height: 4)
                    .opacity(isFaded ? 0.5 : 1)
            }
            if !value.isEmpty {
                Text(value)
                    .font(SavantType.micro)
                    .foregroundStyle(isFaded ? SavantPalette.inkTertiary : SavantPalette.inkSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Comparisons Builder

    private func buildComparisons(p1: Player, p2: Player) -> [MetricComparison] {
        let metrics1 = Dictionary(grouping: p1.metrics) { $0.label }
        let metrics2 = Dictionary(grouping: p2.metrics) { $0.label }
        let allLabels = Set(metrics1.keys).union(metrics2.keys)

        return allLabels.compactMap { label in
            guard let m1 = metrics1[label]?.first, let m2 = metrics2[label]?.first else { return nil }
            return MetricComparison(
                metricLabel: label,
                category: m1.category,
                percentileA: m1.percentile,
                percentileB: m2.percentile,
                valueA: m1.value,
                valueB: m2.value,
                change: m1.percentile - m2.percentile
            )
        }.sorted { a, b in
            a.category == b.category
                ? a.category.sortMetrics(a.metricLabel, b.metricLabel)
                : MetricCategory.allCases.firstIndex(of: a.category)! < MetricCategory.allCases.firstIndex(of: b.category)!
        }
    }
}

private struct MetricComparison {
    let metricLabel: String
    let category: MetricCategory
    let percentileA: Int
    let percentileB: Int
    let valueA: String
    let valueB: String
    let change: Int
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
