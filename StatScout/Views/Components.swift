import SwiftUI

// MARK: - Atomic Components

struct PlayerHeadshot: View {
    let url: URL?
    let initials: String
    let size: CGFloat
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Circle().fill(SavantPalette.surfaceAlt)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .onAppear { isLoading = false }
                    case .failure(_):
                        initialsView
                            .onAppear { isLoading = false }
                    case .empty:
                        shimmerView
                    @unknown default:
                        shimmerView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(SavantPalette.inkTertiary)
    }

    private var shimmerView: some View {
        Circle()
            .fill(SavantPalette.surfaceAlt)
            .shimmering()
    }
}

// MARK: - Shimmer Effect Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.5), .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 2)
                    .offset(x: -proxy.size.width + phase * proxy.size.width * 2)
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
                }
            )
            .mask(content)
            .onAppear { phase = 1 }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct OverallPercentileBadge: View {
    let percentile: Int
    var size: CGFloat = 64

    private var tierDescription: String {
        switch percentile {
        case 90...100: return "Elite"
        case 75..<90: return "Excellent"
        case 50..<75: return "Above Average"
        case 25..<50: return "Below Average"
        default: return "Poor"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(percentile)")
                .font(SavantType.statHero)
                .foregroundStyle(.white)
            Text(percentile.ordinal)
                .font(SavantType.micro)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: size, height: size)
        .background(SavantPalette.color(forPercentile: percentile))
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusBadge))
        .accessibilityLabel("Overall \(percentile)th percentile, \(tierDescription)")
    }
}

struct TeamColorDot: View {
    let abbr: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(MLBTeamColor.color(abbr)).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Module 2: Percentile Bar Row (MetricBar) - Baseball Savant Style

struct MetricBar: View {
    let metric: Metric
    var showValue: Bool = true

    private var accessibilityLabel: String {
        let valueText = metric.value.isEmpty ? "\(metric.percentile)th percentile" : "\(metric.value), \(metric.percentile)th percentile"
        return "\(metric.label): \(valueText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label row
            HStack(spacing: 8) {
                Text(metric.label)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)

                Spacer(minLength: 4)
            }

            // Percentile bar with value at the end - Baseball Savant style
            let percentileValue = max(0, min(100, metric.percentile))
            GeometryReader { proxy in
                let circleSize: CGFloat = 32
                let trackWidth = proxy.size.width - circleSize - 60 // Leave room for value text
                let offset = (circleSize / 2) + (trackWidth * CGFloat(percentileValue) / 100.0)

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SavantPalette.hairline)
                        .frame(height: 12)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SavantPalette.color(forPercentile: percentileValue))
                        .frame(width: offset, height: 12)

                    // Percentile circle - centered on the track (track height 12 centered in 32pt frame = y: 16)
                    ZStack {
                        Circle()
                            .fill(SavantPalette.color(forPercentile: percentileValue))
                            .frame(width: circleSize, height: circleSize)

                        Text("\(percentileValue)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(percentileValue < 25 ? SavantPalette.ink : .white)
                    }
                    .position(x: offset, y: 16)

                    // Stat value at the right end - Baseball Savant style
                    if showValue && !metric.value.isEmpty {
                        HStack {
                            Spacer()
                            Text(metric.value)
                                .font(SavantType.statMed)
                                .foregroundStyle(SavantPalette.ink)
                                .frame(width: 55, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

// MARK: - Search (restyled for light mode)

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SavantPalette.inkSecondary)
            TextField("Search players or teams", text: $text)
                .textInputAutocapitalization(.never)
                .foregroundStyle(SavantPalette.ink)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(SavantPalette.surface)
        .cornerRadius(SavantGeo.radiusCard)
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Category Tabs (Module 5 variant for dashboard)

struct CategoryFilter: View {
    @Binding var selectedCategory: MetricCategory?

    var body: some View {
        let tabs = MetricCategory.allCases.map { $0.rawValue }
        let selectedTab = selectedCategory?.rawValue ?? MetricCategory.hitting.rawValue

        SavantTabs(
            tabs: tabs,
            selected: Binding(
                get: { selectedTab },
                set: { newValue in
                    selectedCategory = MetricCategory.allCases.first { $0.rawValue == newValue }
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

// MARK: - Percentile Bar Mini (for leaderboards)

struct PercentileBarMini: View {
    let percentile: Int
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height/2)
                    .fill(SavantPalette.hairline)
                    .frame(height: height)

                RoundedRectangle(cornerRadius: height/2)
                    .fill(SavantPalette.color(forPercentile: percentile))
                    .frame(width: proxy.size.width * CGFloat(percentile) / 100.0, height: height)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Leaderboard Table

struct LeaderboardTableHeader: View {
    let sortDescending: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("RANK")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 50, alignment: .leading)

            Text("PLAYER")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("TEAM")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 4) {
                Text("OVERALL")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SavantPalette.savantRed)
            }
            .frame(width: 80, alignment: .trailing)
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
    var metricCategory: MetricCategory? = nil

    private var displayPercentile: Int {
        if let label = metricLabel, let category = metricCategory {
            return player.metrics.first { $0.label == label && $0.category == category }?.percentile ?? player.overallPercentile
        }
        return player.overallPercentile
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(SavantType.statSmall)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 50, alignment: .leading)
                .monospacedDigit()

            HStack(spacing: 10) {
                PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                        .lineLimit(1)
                    Text(player.position)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                TeamColorDot(abbr: player.team, size: 6)
                Text(player.team)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .frame(width: 50, alignment: .leading)

            HStack(spacing: 8) {
                PercentileBarMini(percentile: displayPercentile)
                    .frame(width: 40)
                Text("\(displayPercentile)")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.color(forPercentile: displayPercentile))
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }
            .frame(width: 80, alignment: .trailing)
        }
        .frame(height: SavantGeo.rowHeight)
        .padding(.horizontal, SavantGeo.padInline)
        .contentShape(Rectangle())
    }
}

// MARK: - Int Ordinal Extension

extension Int {
    var ordinal: String {
        let suffix: String
        switch self % 100 {
        case 11...13: suffix = "th"
        default:
            switch self % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(self)\(suffix)"
    }
}

// MARK: - Extensions for Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
