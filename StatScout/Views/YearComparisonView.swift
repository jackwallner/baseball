import SwiftUI

struct YearComparisonView: View {
    let history: [Player]
    @State private var selectedYear1: Int = 2026
    @State private var selectedYear2: Int = 2025

    // Static available years - 2024, 2025, 2026
    private let availableYears: [Int] = [2026, 2025, 2024, 2023, 2022]

    private var sortedHistory: [Player] {
        history.sorted {
            guard let s1 = $0.season, let s2 = $1.season else { return false }
            return s1 > s2
        }
    }

    private var player1: Player? {
        sortedHistory.first { $0.season == selectedYear1 }
    }

    private var player2: Player? {
        sortedHistory.first { $0.season == selectedYear2 }
    }

    var body: some View {
        VStack(spacing: 12) {
            yearSelectors

            if let p1 = player1, let p2 = player2 {
                comparisonContent(p1: p1, p2: p2)
            } else {
                noDataForYearView
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var noDataForYearView: some View {
        ContentUnavailableView {
            Label("No Data Available", systemImage: "calendar.badge.clock")
        } description: {
            Text("Historical data for \(selectedYear1) or \(selectedYear2) is not available for this player.")
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

    private var yearSelectors: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                yearPicker(title: "Year 1", selection: $selectedYear1, exclude: selectedYear2)
                yearPicker(title: "Year 2", selection: $selectedYear2, exclude: selectedYear1)
            }

            if let p1 = player1, let p2 = player2 {
                summaryRow(p1: p1, p2: p2)
            }
        }
        .padding(12)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func yearPicker(title: String, selection: Binding<Int>, exclude: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)

            Menu {
                ForEach(availableYears.filter { $0 != exclude }, id: \.self) { year in
                    Button {
                        selection.wrappedValue = year
                    } label: {
                        HStack {
                            Text(String(year))
                            if selection.wrappedValue == year {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(String(selection.wrappedValue))
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(SavantPalette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryRow(p1: Player, p2: Player) -> some View {
        let change = p1.overallPercentile - p2.overallPercentile
        let changeColor: Color = change > 0 ? .green : (change < 0 ? SavantPalette.savantRed : SavantPalette.inkSecondary)
        let arrow = change > 0 ? "↑" : (change < 0 ? "↓" : "→")

        return HStack {
            Spacer()
            VStack(spacing: 2) {
                Text("Overall Change")
                    .font(SavantType.micro)
                    .foregroundStyle(SavantPalette.inkSecondary)
                HStack(spacing: 4) {
                    Text("\(abs(change))")
                        .font(SavantType.statMed)
                    Text(arrow)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(changeColor)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var placeholderContent: some View {
        ContentUnavailableView {
            Label("Select Two Years", systemImage: "calendar.badge.clock")
        } description: {
            Text("Choose two seasons above to compare metrics.")
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

    private func comparisonContent(p1: Player, p2: Player) -> some View {
        let comparisons = buildComparisons(p1: p1, p2: p2)
        let grouped = Dictionary(grouping: comparisons) { $0.category }

        return VStack(spacing: 12) {
            ForEach(MetricCategory.allCases, id: \.self) { category in
                if let items = grouped[category], !items.isEmpty {
                    categoryComparisonCard(category: category, items: items, year1: p1.season ?? 0, year2: p2.season ?? 0)
                }
            }
        }
    }

    private func categoryComparisonCard(category: MetricCategory, items: [MetricComparison], year1: Int, year2: Int) -> some View {
        VStack(spacing: 0) {
            SavantSubSectionBar(title: category.rawValue.uppercased())

            comparisonGridHeader(year1: year1, year2: year2)

            ForEach(Array(items.enumerated()), id: \.element.metricLabel) { index, item in
                comparisonRow(item: item, isAltRow: index % 2 == 1)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func comparisonGridHeader(year1: Int, year2: Int) -> some View {
        HStack(spacing: 0) {
            Text("Metric")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            Text("\(year2)")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 50)

            Text("\(year1)")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 50)

            Text("Δ")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 40)
        }
        .padding(.horizontal, SavantGeo.padInline)
        .frame(height: 28)
        .background(SavantPalette.surfaceAlt)
    }

    private func comparisonRow(item: MetricComparison, isAltRow: Bool) -> some View {
        let changeColor: Color = item.change > 0 ? .green : (item.change < 0 ? SavantPalette.savantRed : SavantPalette.inkSecondary)
        let arrow = item.change > 0 ? "↑" : (item.change < 0 ? "↓" : "→")

        return HStack(spacing: 0) {
            Text(item.metricLabel)
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.ink)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            Spacer()

            // Year 2 (earlier year) - faded
            VStack(spacing: 0) {
                Text("\(item.percentile2)")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.inkSecondary)
                if !item.value2.isEmpty {
                    Text(item.value2)
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
            }
            .frame(width: 50)

            // Year 1 (later year) - emphasized
            VStack(spacing: 0) {
                Text("\(item.percentile1)")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.color(forPercentile: item.percentile1))
                if !item.value1.isEmpty {
                    Text(item.value1)
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
            }
            .frame(width: 50)

            // Change indicator
            HStack(spacing: 2) {
                Text("\(abs(item.change))")
                    .font(SavantType.bodyBold)
                Text(arrow)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(changeColor)
            .frame(width: 40)
        }
        .padding(.horizontal, SavantGeo.padInline)
        .frame(height: 44)
        .background(isAltRow ? SavantPalette.surfaceAlt : SavantPalette.surface)
        .overlay(
            Rectangle()
                .fill(SavantPalette.divider)
                .frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
    }

    private func buildComparisons(p1: Player, p2: Player) -> [MetricComparison] {
        let metrics1 = Dictionary(grouping: p1.metrics) { $0.label }
        let metrics2 = Dictionary(grouping: p2.metrics) { $0.label }
        let allLabels = Set(metrics1.keys).union(metrics2.keys)

        return allLabels.compactMap { label in
            let m1 = metrics1[label]?.first
            let m2 = metrics2[label]?.first

            // Skip if metric doesn't exist in both years
            guard let metric1 = m1, let metric2 = m2 else { return nil }

            return MetricComparison(
                metricLabel: label,
                category: metric1.category,
                percentile1: metric1.percentile,
                percentile2: metric2.percentile,
                value1: metric1.value,
                value2: metric2.value,
                change: metric1.percentile - metric2.percentile
            )
        }.sorted { abs($0.change) > abs($1.change) }
    }
}

private struct MetricComparison {
    let metricLabel: String
    let category: MetricCategory
    let percentile1: Int
    let percentile2: Int
    let value1: String
    let value2: String
    let change: Int
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
