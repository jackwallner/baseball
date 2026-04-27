import SwiftUI

// MARK: - Atomic Components

struct PlayerHeadshot: View {
    let url: URL?
    let initials: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(SavantPalette.surfaceAlt)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(SavantPalette.inkTertiary)
    }
}

struct OverallPercentileBadge: View {
    let percentile: Int
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            Text("\(percentile)")
                .font(SavantType.statHero)
                .foregroundStyle(.white)
            Text("PCTL")
                .font(SavantType.micro)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: size, height: size)
        .background(SavantPalette.color(forPercentile: percentile))
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusBadge))
    }
}

struct TeamColorDot: View {
    let abbr: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(MLBTeamColor.color(abbr)).frame(width: size, height: size)
    }
}

// MARK: - Module 2: Percentile Bar Row (MetricBar)

struct MetricBar: View {
    let metric: Metric
    var showValue: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(metric.label)
                    .font(SavantType.smallBold)
                    .foregroundStyle(SavantPalette.ink)
                Spacer(minLength: 8)
                if showValue && !metric.value.isEmpty {
                    Text(metric.value)
                        .font(SavantType.statSmall)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
            GeometryReader { proxy in
                let p = max(0, min(100, metric.percentile))
                let x = max(6, min(proxy.size.width - 6, proxy.size.width * CGFloat(p) / 100.0))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SavantPalette.hairline)
                        .frame(height: SavantGeo.barTrack)
                        .frame(maxHeight: .infinity)
                    Circle()
                        .fill(SavantPalette.color(forPercentile: p))
                        .frame(width: SavantGeo.barMarker, height: SavantGeo.barMarker)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(x: x, y: proxy.size.height / 2)
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Search (restyled for light mode)

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SavantPalette.inkTertiary)
            TextField("Search players or teams (e.g. NYY, LAD)", text: $text)
                .textInputAutocapitalization(.never)
                .foregroundStyle(SavantPalette.ink)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(SavantPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Category Tabs (Module 5 variant for dashboard)

struct CategoryFilter: View {
    @Binding var selectedCategory: MetricCategory?

    var body: some View {
        let tabs = ["All"] + MetricCategory.allCases.map { $0.rawValue }
        let selectedTab = selectedCategory?.rawValue ?? "All"

        SavantTabs(
            tabs: tabs,
            selected: Binding(
                get: { selectedTab },
                set: { newValue in
                    if newValue == "All" {
                        selectedCategory = nil
                    } else {
                        selectedCategory = MetricCategory.allCases.first { $0.rawValue == newValue }
                    }
                }
            )
        )
    }
}

// MARK: - Section Header (legacy, minimal use)

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SavantType.sectionTitle)
                .tracking(0.8)
                .foregroundStyle(SavantPalette.ink)
            Text(subtitle)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
        }
    }
}

// MARK: - Trend Glyph

struct TrendGlyph: View {
    let direction: MetricDirection

    var body: some View {
        Image(systemName: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(color)
    }

    private var icon: String {
        switch direction {
        case .up: "arrow.up.right"
        case .flat: "minus"
        case .down: "arrow.down.right"
        }
    }

    private var color: Color {
        switch direction {
        case .up: SavantPalette.up
        case .flat: SavantPalette.inkTertiary
        case .down: SavantPalette.down
        }
    }
}

// MARK: - Leaderboard Table Components

struct LeaderboardTableHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("#")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 28, alignment: .trailing)
            Text("PLAYER")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("VAL")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 56, alignment: .trailing)
            Text("PCTL")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 120, alignment: .leading)
        }
        .frame(height: SavantGeo.rowHeightHeader)
        .padding(.horizontal, SavantGeo.padInline)
        .background(SavantPalette.surfaceAlt)
        .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .bottom)
    }
}

struct LeaderboardTableRow: View {
    let rank: Int
    let player: Player
    var metricLabel: String? = nil

    private var displayMetric: Metric? {
        if let metricLabel {
            return player.metrics.first { $0.label == metricLabel }
        }
        return player.headlineMetric
    }

    private var displayPercentile: Int {
        if metricLabel != nil {
            return displayMetric?.percentile ?? player.overallPercentile
        }
        return player.overallPercentile
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(SavantType.statSmall)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 28, alignment: .trailing)
            HStack(spacing: 10) {
                PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        TeamColorDot(abbr: player.team, size: 6)
                        Text(player.team)
                            .font(SavantType.micro)
                            .tracking(0.4)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let metric = displayMetric {
                Text(metric.value)
                    .font(SavantType.statMed)
                    .foregroundStyle(SavantPalette.ink)
                    .frame(width: 56, alignment: .trailing)
            } else {
                Text("—")
                    .font(SavantType.statMed)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 56, alignment: .trailing)
            }
            PercentileBarMini(percentile: displayPercentile)
                .frame(width: 120, alignment: .leading)
        }
        .frame(height: SavantGeo.rowHeight)
        .padding(.horizontal, SavantGeo.padInline)
        .background(rank % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .bottom)
    }
}

struct PercentileBarMini: View {
    let percentile: Int

    var body: some View {
        GeometryReader { proxy in
            let p = max(0, min(100, percentile))
            let x = max(5, min(proxy.size.width - 5, proxy.size.width * CGFloat(p) / 100.0))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(SavantPalette.hairline)
                    .frame(height: 4)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                Circle()
                    .fill(SavantPalette.color(forPercentile: p))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .position(x: x, y: proxy.size.height / 2)
            }
        }
        .frame(height: 18)
    }
}

// MARK: - Featured Tile

struct FeaturedTile: View {
    let player: Player
    var weeklyDelta: Int? = nil

    private var deltaDirection: MetricDirection {
        guard let weeklyDelta else { return .flat }
        if weeklyDelta > 0 { return .up }
        if weeklyDelta < 0 { return .down }
        return .flat
    }

    var body: some View {
        HStack(spacing: 10) {
            PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    TeamColorDot(abbr: player.team, size: 6)
                    Text(player.team)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                if let metric = player.headlineMetric {
                    Text("\(metric.label) \(metric.value) · \(metric.percentile) PCTL")
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.color(forPercentile: metric.percentile))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if let weeklyDelta {
                HStack(spacing: 3) {
                    TrendGlyph(direction: deltaDirection)
                    Text("\(weeklyDelta >= 0 ? "+" : "")\(weeklyDelta)")
                        .font(SavantType.statSmall)
                        .foregroundStyle(weeklyDelta >= 0 ? SavantPalette.up : SavantPalette.down)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(SavantPalette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusBadge))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 240, height: 80)
        .background(SavantPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Utility

extension Int {
    var ordinal: String {
        let suffix: String
        let ones = self % 10
        let tens = (self / 10) % 10
        if tens == 1 {
            suffix = "th"
        } else if ones == 1 {
            suffix = "st"
        } else if ones == 2 {
            suffix = "nd"
        } else if ones == 3 {
            suffix = "rd"
        } else {
            suffix = "th"
        }
        return "\(self)\(suffix)"
    }
}
