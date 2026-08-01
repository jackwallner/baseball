import SwiftUI

/// Two clubs, side by side. Carries only the identity of each slot; the
/// destination rebuilds both rosters from the view model so the route stays
/// cheap and Hashable, the same trick `YearCompareRoute` uses.
struct TeamComparisonRoute: Hashable {
    let teamA: String
    let teamB: String
    let seasonA: Int
    let seasonB: Int
}

/// One club's season line, pooled from its roster.
///
/// The team cards already do this per screen, each with its own private copy of
/// the rules; this is the one place both vocabularies are aggregated the same
/// way, so a comparison can't disagree with the team page it was opened from.
@MainActor
enum TeamAggregate {
    /// Rate stats and the roster quantity each is a rate of. Summing a team's
    /// hits and at-bats is exact; averaging its players' batting averages would
    /// weight a September call-up's 1-for-2 like a regular's season.
    static let rateWeights: [String: String] = [
        "AVG": "AB", "SLG": "AB",
        "OBP": "PA", "OPS": "PA",
        "ERA": "IP", "WHIP": "IP", "K/9": "IP", "BB/9": "IP",
    ]

    static let battingOrder = [
        "AVG", "OBP", "SLG", "OPS", "PA", "AB", "H", "2B", "3B", "HR", "R", "RBI", "BB", "SO", "SB", "CS",
    ]
    static let pitchingOrder = [
        "ERA", "WHIP", "IP", "W", "L", "SV", "SO", "BB", "H", "HR", "ER", "G", "GS",
    ]

    /// Lower is better, per side. A pitcher's H, HR and BB are what he gave up,
    /// so the trophy on those rows has to go to the smaller number.
    static func lowerIsBetter(_ category: MetricCategory) -> Set<String> {
        category == .pitching
            ? ["ERA", "WHIP", "L", "H", "R", "ER", "HR", "BB", "BB/9", "AVG", "OBP", "SLG", "OPS"]
            : ["SO", "CS"]
    }

    static func order(_ category: MetricCategory) -> [String] {
        category == .pitching ? pitchingOrder : battingOrder
    }

    /// The traditional line: rates weighted by their own denominator, counting
    /// stats summed.
    static func standardLine(roster: [Player], category: MetricCategory) -> [String: Double] {
        let pool = roster.filter { $0.matchesPlayerType(for: category) }
        guard !pool.isEmpty else { return [:] }

        var totals: [String: Double] = [:]
        var weighted: [String: (num: Double, den: Double)] = [:]

        for player in pool {
            // Only this side's line. A two-way player carries both, and summing
            // the whole block counts his hits and the hits he allowed into the
            // same team total.
            let stats = (player.standardStats ?? []).filter {
                $0.resolvedCategory(playerType: player.playerType) == category
            }
            func raw(_ label: String) -> Double? {
                stats.stat(label, category: category, playerType: player.playerType)
                    .flatMap { DashboardViewModel.rawNumeric($0.value) }
            }
            for stat in stats {
                let label = stat.label.uppercased()
                guard let value = DashboardViewModel.rawNumeric(stat.value) else { continue }
                if let weightKey = rateWeights[label] {
                    guard let weight = raw(weightKey), weight > 0 else { continue }
                    var entry = weighted[label] ?? (0, 0)
                    entry.num += value * weight
                    entry.den += weight
                    weighted[label] = entry
                } else {
                    totals[label, default: 0] += value
                }
            }
        }

        for (label, entry) in weighted where entry.den > 0 {
            totals[label] = entry.num / entry.den
        }
        return totals
    }

    /// The Statcast line: each metric averaged across the roster, weighted by
    /// playing time so a bench bat's small sample doesn't move the club's xwOBA
    /// as much as an everyday hitter's.
    static func advancedLine(roster: [Player], category: MetricCategory) -> [String: Double] {
        let pool = roster.filter { $0.matchesPlayerType(for: category) }
        guard !pool.isEmpty else { return [:] }

        var out: [String: Double] = [:]
        for label in advancedLabels(roster: pool, category: category) {
            var weightedSum = 0.0
            var weightTotal = 0.0
            for player in pool {
                guard let metric = player.metrics.first(where: {
                    $0.label == label && $0.category == category
                }), let value = DashboardViewModel.rawNumeric(metric.value) else { continue }
                let weight = workload(player, category: category) ?? 1
                weightedSum += value * weight
                weightTotal += weight
            }
            guard weightTotal > 0 else { continue }
            out[label] = weightedSum / weightTotal
        }
        return out
    }

    /// Every advanced metric the roster carries for this category, in the app's
    /// usual display order.
    static func advancedLabels(roster: [Player], category: MetricCategory) -> [String] {
        let present = Set(roster.flatMap { player in
            player.metrics.filter { $0.category == category }.map(\.label)
        })
        let ordered = category.metricPriorityOrder.filter { present.contains($0) }
        return ordered + present.subtracting(category.metricPriorityOrder).sorted()
    }

    /// PA for batters, IP for pitchers. nil falls back to equal weighting.
    static func workload(_ player: Player, category: MetricCategory) -> Double? {
        let key = category == .pitching ? "IP" : "PA"
        guard let raw = player.standardStats?.first(where: { $0.label == key })?.value else { return nil }
        return DashboardViewModel.rawNumeric(raw)
    }

    /// Advanced metrics where a falling number is the better outcome. Mirrors
    /// `DashboardViewModel.defaultSortDescending`'s rule so the trophy and the
    /// leaderboards agree about which way a metric runs.
    static func advancedLowerIsBetter(_ label: String, category: MetricCategory) -> Bool {
        !DashboardViewModel.defaultSortDescending(label: label, category: category)
    }

    static func formatStandard(_ label: String, _ value: Double) -> String {
        switch label {
        case "AVG", "OBP", "SLG", "OPS":
            return String(format: "%.3f", value).replacingOccurrences(of: "0.", with: ".")
        case "ERA", "WHIP", "K/9", "BB/9":
            return String(format: "%.2f", value)
        case "IP":
            return String(format: "%.1f", value)
        default:
            return String(format: "%.0f", value)
        }
    }

    static func formatAdvanced(_ value: Double, label: String) -> String {
        if label.hasSuffix("%") { return String(format: "%.1f%%", value) }
        if label.hasSuffix("Spin") { return String(format: "%.0f rpm", value) }
        if label == "Swing Length" { return String(format: "%.2f ft", value) }
        if label.contains("EV") || label.contains("Velo") || label == "Bat Speed" {
            return String(format: "%.1f mph", value)
        }
        if value < 10 { return String(format: "%.3f", value).replacingOccurrences(of: "0.", with: ".") }
        return String(format: "%.1f", value)
    }
}

/// Head-to-head for two clubs, in both vocabularies.
///
/// Player vs player has been the tab's whole answer to "who's better", which
/// leaves out the question fans actually argue about. Same shape as
/// `PlayerComparisonView`: two identity headers, then rows of A / label / B with
/// a marker on the better side.
///
/// A club against its own past season is a legitimate comparison and the reason
/// each slot holds a year of its own, so only the exactly-identical pair is
/// refused.
struct TeamComparisonView: View {
    let route: TeamComparisonRoute
    /// Every player in each slot's season, filtered to the club here so the
    /// caller doesn't have to know the abbreviation-normalising rules.
    let leaguePlayersA: [Player]
    let leaguePlayersB: [Player]

    @State private var side: TeamRankingsCard.Side = .batting

    private var category: MetricCategory { side.category }

    private var rosterA: [Player] {
        leaguePlayersA.filter {
            normalizedTeamAbbreviation($0.team) == normalizedTeamAbbreviation(route.teamA)
        }
    }

    private var rosterB: [Player] {
        leaguePlayersB.filter {
            normalizedTeamAbbreviation($0.team) == normalizedTeamAbbreviation(route.teamB)
        }
    }

    private struct StatRow: Identifiable {
        let id: String
        let label: String
        let aText: String
        let bText: String
        /// Sign-flipped for lower-is-better metrics so the marker always goes to
        /// the greater number. Nil means "show the value, don't call a winner".
        let aValue: Double?
        let bValue: Double?
    }

    /// Volume rows describe a roster rather than rank it: more plate
    /// appearances is more baseball played, not better baseball, and a club
    /// that has played two extra games would collect a trophy for it.
    private static let descriptiveOnlyLabels: Set<String> = ["PA", "AB", "IP", "G", "GS"]

    private var advancedRows: [StatRow] {
        let a = TeamAggregate.advancedLine(roster: rosterA, category: category)
        let b = TeamAggregate.advancedLine(roster: rosterB, category: category)
        let labels = TeamAggregate.advancedLabels(roster: rosterA + rosterB, category: category)
        return labels.compactMap { label in
            guard a[label] != nil || b[label] != nil else { return nil }
            let sign: Double = TeamAggregate.advancedLowerIsBetter(label, category: category) ? -1 : 1
            return StatRow(
                id: "adv-\(label)",
                label: label,
                aText: a[label].map { TeamAggregate.formatAdvanced($0, label: label) } ?? "-",
                bText: b[label].map { TeamAggregate.formatAdvanced($0, label: label) } ?? "-",
                aValue: a[label].map { $0 * sign },
                bValue: b[label].map { $0 * sign }
            )
        }
    }

    private var standardRows: [StatRow] {
        let a = TeamAggregate.standardLine(roster: rosterA, category: category)
        let b = TeamAggregate.standardLine(roster: rosterB, category: category)
        let lower = TeamAggregate.lowerIsBetter(category)
        return TeamAggregate.order(category).compactMap { label in
            guard a[label] != nil || b[label] != nil else { return nil }
            let comparable = !Self.descriptiveOnlyLabels.contains(label)
            let sign: Double = lower.contains(label) ? -1 : 1
            return StatRow(
                id: "std-\(label)",
                label: label,
                aText: a[label].map { TeamAggregate.formatStandard(label, $0) } ?? "-",
                bText: b[label].map { TeamAggregate.formatStandard(label, $0) } ?? "-",
                aValue: comparable ? a[label].map { $0 * sign } : nil,
                bValue: comparable ? b[label].map { $0 * sign } : nil
            )
        }
    }

    private var statGroups: [(title: String, rows: [StatRow])] {
        [
            ("\(category.rawValue.uppercased()) · ADVANCED", advancedRows),
            ("\(category.rawValue.uppercased()) · STANDARD", standardRows),
        ]
        .filter { !$0.1.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    teamHeader(route.teamA, rosterCount: rosterA.count, season: route.seasonA)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SavantPalette.inkTertiary)
                    teamHeader(route.teamB, rosterCount: rosterB.count, season: route.seasonB)
                }

                SavantSegmented(
                    segments: TeamRankingsCard.Side.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $side
                )

                if statGroups.isEmpty {
                    ContentUnavailableView {
                        Label("No aggregate stats", systemImage: "sum")
                    } description: {
                        Text("Neither roster has \(category.rawValue.lowercased()) stats for these seasons.")
                    }
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .background(SavantPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
                } else {
                    ForEach(statGroups, id: \.title) { group in
                        VStack(spacing: 0) {
                            SavantSectionBar(title: group.title)
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                statRow(row, index: index)
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

                Text("Rate stats are weighted by the roster's own PA or IP; counting stats are summed. A player traded in July brings his whole season with him, so these are roster aggregates rather than official team totals.")
                    .font(SavantType.micro)
                    .tracking(0.2)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            // Clears the floating tab bar.
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle("\(displayTeamAbbr(route.teamA)) vs \(displayTeamAbbr(route.teamB))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func teamHeader(_ team: String, rosterCount: Int, season: Int) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MLBTeamColor.color(team))
                    .frame(width: 58, height: 58)
                Text(displayTeamAbbr(team))
                    .font(SavantType.smallBold)
                    .foregroundStyle(.white)
            }
            Text(teamFullName(team))
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(rosterCount) tracked · \(String(season))")
                .font(SavantType.micro)
                .tracking(0.3)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func statRow(_ row: StatRow, index: Int) -> some View {
        HStack(spacing: 8) {
            statValue(row.aText, value: row.aValue, other: row.bValue)
            Text(row.label)
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .frame(width: 96)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            statValue(row.bText, value: row.bValue, other: row.aValue)
        }
        .frame(height: 52)
        .padding(.horizontal, SavantGeo.padInline)
        .background(index.isMultiple(of: 2) ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
    }

    private func statValue(_ text: String, value: Double?, other: Double?) -> some View {
        HStack(spacing: 4) {
            if let value, let other, value > other {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.yellow)
            }
            Text(text)
                .font(SavantType.statMed)
                .foregroundStyle(text == "-" ? SavantPalette.inkTertiary : SavantPalette.savantRed)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TeamComparisonView(
            route: TeamComparisonRoute(
                teamA: "NYY",
                teamB: "SEA",
                seasonA: StatScoutSeason.current,
                seasonB: StatScoutSeason.current
            ),
            leaguePlayersA: SampleData.players,
            leaguePlayersB: SampleData.players
        )
    }
}
#endif
