import SwiftUI

struct StatScoutTheme {
    static let background = LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.06, green: 0.08, blue: 0.16)], startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.12)
    static let accent = Color(red: 0.38, green: 0.77, blue: 1.00)
    static let hot = Color(red: 1.00, green: 0.37, blue: 0.28)
    static let savantBlue = Color(red: 0.09, green: 0.38, blue: 0.74)
    static let savantRed = Color(red: 0.84, green: 0.16, blue: 0.16)
}

struct HeroHeaderView: View {
    let updatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nightly Statcast pulse")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Player percentiles, movement signals, and clean context for fans and media.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                Text("Refreshed \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(StatScoutTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.28), Color.purple.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(StatScoutTheme.stroke))
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.56))
            TextField("Search players or teams", text: $text)
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(StatScoutTheme.stroke))
    }
}

struct CategoryFilter: View {
    @Binding var selectedCategory: MetricCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(MetricCategory.allCases, id: \.self) { category in
                    FilterChip(title: category.rawValue, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? .black : .white)
                .background(isSelected ? StatScoutTheme.accent : StatScoutTheme.card, in: Capsule())
                .overlay(Capsule().stroke(StatScoutTheme.stroke))
        }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
        }
    }
}

struct PlayerCard: View {
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(player.name)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                    Text("\(player.team) · \(player.position) · \(player.handedness)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                PercentileBadge(percentile: player.overallPercentile)
            }

            if let metric = player.headlineMetric {
                Text("Top signal: \(metric.label) in the \(metric.percentile.ordinal) percentile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            VStack(spacing: 10) {
                ForEach(player.metrics.prefix(3)) { metric in
                    MetricBar(metric: metric)
                }
            }
        }
        .padding(18)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(StatScoutTheme.stroke))
    }
}

struct LeaderboardRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: 14) {
            PercentileBadge(percentile: player.overallPercentile)
            VStack(alignment: .leading, spacing: 5) {
                Text(player.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(player.team) · \(player.position)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if let metric = player.headlineMetric {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(metric.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.64))
                    TrendGlyph(direction: metric.direction)
                }
            }
        }
        .padding(16)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(StatScoutTheme.stroke))
    }
}

struct PercentileBadge: View {
    let percentile: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(percentile)")
                .font(.title3.weight(.black))
            Text("PCTL")
                .font(.system(size: 9, weight: .black))
        }
        .foregroundStyle(percentile > 90 ? .black : .white)
        .frame(width: 58, height: 58)
        .background(percentile > 90 ? StatScoutTheme.accent : Color.white.opacity(0.10), in: Circle())
        .overlay(Circle().stroke(StatScoutTheme.stroke))
    }
}

struct MetricBar: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(metric.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(metric.value)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                TrendGlyph(direction: metric.direction)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(percentileColor)
                        .frame(width: proxy.size.width * CGFloat(metric.percentile) / 100)
                }
            }
            .frame(height: 8)
        }
    }

    private var percentileColor: Color {
        if metric.percentile >= 70 {
            return StatScoutTheme.savantRed
        }
        if metric.percentile <= 30 {
            return StatScoutTheme.savantBlue
        }
        return Color.white.opacity(0.48)
    }
}

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
        case .up: .green
        case .flat: .white.opacity(0.6)
        case .down: .orange
        }
    }
}

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
