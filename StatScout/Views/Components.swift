import SwiftUI

struct StatScoutTheme {
    static let background = LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.06, green: 0.08, blue: 0.16)], startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.12)
    static let accent = Color(red: 0.38, green: 0.77, blue: 1.00)
    static let hot = Color(red: 1.00, green: 0.37, blue: 0.28)
    static let savantBlue = Color(red: 0.09, green: 0.38, blue: 0.74)
    static let savantRed = Color(red: 0.84, green: 0.16, blue: 0.16)
    static let savantOrange = Color(red: 0.90, green: 0.40, blue: 0.30)
    static let savantMidBlue = Color(red: 0.30, green: 0.55, blue: 0.85)

    static func percentileColor(_ percentile: Int) -> Color {
        if percentile >= 75 { return savantRed }
        if percentile <= 25 { return savantBlue }
        return Color.white.opacity(0.7)
    }
}

struct HeroHeaderView: View {
    let playerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Date(), style: .date)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Baseball Savant-style player percentiles, leaderboards, and metric insights.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 8) {
                Image(systemName: "baseball.fill")
                Text("\(playerCount) players tracked")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(StatScoutTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [Color(red: 0.06, green: 0.14, blue: 0.32), Color(red: 0.04, green: 0.08, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
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
            TextField("Search players or teams (e.g. NYY, LAD)", text: $text)
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(StatScoutTheme.stroke))
    }
}

struct TeamChipRow: View {
    let teams: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(teams, id: \.self) { team in
                    Button(action: { onSelect(team) }) {
                        Text(team)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(StatScoutTheme.card, in: Capsule())
                            .overlay(Capsule().stroke(StatScoutTheme.stroke))
                    }
                }
            }
        }
    }
}

struct RandomPlayerButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "shuffle")
                Text(isEnabled ? "Random Player" : "Loading players...")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isEnabled ? StatScoutTheme.savantRed.opacity(0.85) : StatScoutTheme.card, in: Capsule())
        }
        .disabled(!isEnabled)
    }
}

struct MetricLeaderRow: View {
    let label: String
    let category: MetricCategory
    let bestPlayer: Player?
    let bestValue: Int?
    let worstPlayer: Player?
    let worstValue: Int?
    let onSelect: (Player) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text(category.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            if let bestPlayer, let bestValue {
                HStack(spacing: 10) {
                    Text("Best")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(StatScoutTheme.savantRed)
                        .frame(width: 36, alignment: .leading)

                    Text(bestPlayer.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(bestValue)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(StatScoutTheme.savantRed)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(bestPlayer) }
            }

            if let worstPlayer, let worstValue {
                HStack(spacing: 10) {
                    Text("Worst")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(StatScoutTheme.savantBlue)
                        .frame(width: 36, alignment: .leading)

                    Text(worstPlayer.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    Text("\(worstValue)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(StatScoutTheme.savantBlue)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(worstPlayer) }
            }
        }
        .padding(14)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(StatScoutTheme.stroke))
    }
}

struct SavantPlayerHeader: View {
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                if let imageURL = player.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else if phase.error != nil {
                            Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.5))
                        } else {
                            ProgressView().tint(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(player.name)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(player.team) · \(player.position) · \(player.handedness)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(player.overallPercentile)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("PCTL")
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(StatScoutTheme.percentileColor(player.overallPercentile))
                .frame(width: 64, height: 64)
                .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(StatScoutTheme.stroke))
            }

            if let headline = player.headlineMetric {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(StatScoutTheme.accent)
                    Text("\(headline.label): \(headline.value.isEmpty ? "--" : headline.value) — \(headline.percentile.ordinal) percentile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("No standout metric available yet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.04, green: 0.10, blue: 0.24), Color(red: 0.03, green: 0.06, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(StatScoutTheme.stroke))
    }
}

struct CategoryFilter: View {
    @Binding var selectedCategory: MetricCategory?
    let counts: [MetricCategory: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(MetricCategory.allCases, id: \.self) { category in
                    let count = counts[category] ?? 0
                    FilterChip(title: "\(category.rawValue) (\(count))", isSelected: selectedCategory == category) {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                if let imageURL = player.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else if phase.error != nil {
                            Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.5))
                        } else {
                            ProgressView().tint(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(player.name)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                    Text("\(player.team) · \(player.position) · \(player.handedness)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(player.overallPercentile)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                    Text("PCTL")
                        .font(.system(size: 8, weight: .black))
                }
                .foregroundStyle(StatScoutTheme.percentileColor(player.overallPercentile))
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            if let metric = player.headlineMetric {
                HStack(spacing: 4) {
                    TrendGlyph(direction: metric.direction)
                    Text("\(metric.label): \(metric.value.isEmpty ? "--" : metric.value) (\(metric.percentile) PCTL)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
            } else {
                Text("No metrics available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(spacing: 8) {
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
            VStack(spacing: 0) {
                Text("\(player.overallPercentile)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Text("PCTL")
                    .font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(StatScoutTheme.percentileColor(player.overallPercentile))
            .frame(width: 64, height: 64)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(player.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(player.team) · \(player.position) · \(player.handedness)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if let metric = player.headlineMetric {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(metric.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.64))
                    Text("\(metric.percentile)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(StatScoutTheme.percentileColor(metric.percentile))
                }
            } else {
                Text("—")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .background(StatScoutTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(StatScoutTheme.stroke))
    }
}

struct MetricBar: View {
    let metric: Metric
    let showValue: Bool

    init(metric: Metric, showValue: Bool = true) {
        self.metric = metric
        self.showValue = showValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(metric.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if showValue && !metric.value.isEmpty {
                    Text(metric.value)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                }
                Text("\(metric.percentile)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(StatScoutTheme.percentileColor(metric.percentile))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(percentileFillColor)
                        .frame(width: max(4, proxy.size.width * CGFloat(metric.percentile) / 100))
                }
            }
            .frame(height: 10)
        }
    }

    private var percentileFillColor: Color {
        if metric.percentile >= 75 {
            return StatScoutTheme.savantRed
        }
        if metric.percentile >= 50 {
            return StatScoutTheme.savantOrange
        }
        if metric.percentile >= 25 {
            return StatScoutTheme.savantMidBlue
        }
        return StatScoutTheme.savantBlue
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
