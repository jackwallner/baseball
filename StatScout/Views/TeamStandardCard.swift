import SwiftUI

/// The traditional line for a whole team, percentile-mapped against the other
/// 29 clubs.
///
/// The percentile card next to it answers "how good is the contact quality";
/// this answers "what actually happened". Both are Savant's own framing — its
/// team pages carry a standard line alongside the Statcast one — and the app
/// already does this on a player page, so a team not having it was the gap.
///
/// The ruler here is the league's thirty teams, not its several hundred
/// players: a team's .258 average means nothing against individual hitters'
/// spread, and everything against the other clubs'.
struct TeamStandardCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    let players: [Player]
    /// Every player in the season, used to build the thirty team lines.
    let leaguePlayers: [Player]
    let fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])?
    let onUpgradeTap: () -> Void

    @State private var side: TeamRankingsCard.Side = .batting
    @State private var showingRecent = false
    @State private var windowDays: Int = 15
    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?

    // MARK: - Stat vocabulary

    /// Rate stats and the roster quantity each is a rate of. Summing a team's
    /// hits and at-bats is exact; averaging its players' batting averages would
    /// weight a September call-up's 1-for-2 like a regular's season.
    private static let rateWeights: [String: String] = [
        "AVG": "AB", "SLG": "AB",
        "OBP": "PA", "OPS": "PA",
        "ERA": "IP", "WHIP": "IP", "K/9": "IP", "BB/9": "IP", "K%": "BF", "BB%": "BF",
    ]

    private static let battingOrder = [
        "AVG", "OBP", "SLG", "OPS", "PA", "AB", "H", "2B", "3B", "HR", "R", "RBI", "BB", "SO", "SB", "CS",
    ]
    private static let pitchingOrder = [
        "ERA", "WHIP", "IP", "W", "L", "SV", "SO", "BB", "H", "HR", "ER", "G", "GS",
    ]

    /// Lower is better. Same per-side split as the player page: a pitcher's H,
    /// HR and BB are what he gave up.
    private static func lowerIsBetter(_ side: TeamRankingsCard.Side) -> Set<String> {
        side == .pitching
            ? ["ERA", "WHIP", "L", "H", "R", "ER", "HR", "BB", "BB/9", "AVG", "OBP", "SLG", "OPS"]
            : ["SO", "CS"]
    }

    private var order: [String] {
        side == .pitching ? Self.pitchingOrder : Self.battingOrder
    }

    private var rateLabels: [String] {
        order.filter { Self.rateWeights[$0] != nil }
    }

    private var countingLabels: [String] {
        order.filter { Self.rateWeights[$0] == nil }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "TEAM STANDARD STATS")

            SavantPickerRow {
                SavantSegmented(
                    segments: TeamRankingsCard.Side.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $side
                )
                .segmentCount(TeamRankingsCard.Side.allCases.count)
                SavantSegmented(
                    segments: [
                        .init(value: false, label: "Season"),
                        .init(value: true, label: "Recent", isLocked: !store.isPro),
                    ],
                    selection: $showingRecent,
                    onLockedTap: { _ in onUpgradeTap() }
                )
                .segmentCount(2)
            }
            .padding(.horizontal, SavantGeo.padInline)
            .padding(.vertical, 8)
            .background(SavantPalette.surfaceAlt)

            if showingRecent {
                SavantSegmented(
                    segments: RecentWindow.allCases.map { .init(value: $0, label: $0.label) },
                    selection: Binding(
                        get: { RecentWindow(rawValue: windowDays) ?? .fortnight },
                        set: { windowDays = $0.rawValue }
                    )
                )
                .padding(.horizontal, SavantGeo.padInline)
                .padding(.bottom, 8)
                .background(SavantPalette.surfaceAlt)
            }

            if showingRecent {
                recentContent
            } else {
                seasonContent
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(showingRecent)-\(store.isPro)") {
            if showingRecent, store.isPro { await load() }
        }
    }

    // MARK: - Season

    @ViewBuilder
    private var seasonContent: some View {
        let line = teamLine(for: players)
        if line.isEmpty {
            emptyState("No standard stats for this roster")
        } else {
            let league = leagueLines()
            barGroup(
                title: "RATE",
                labels: rateLabels,
                line: line,
                league: league,
                startIndex: 0
            )
            barGroup(
                title: "VOLUME",
                labels: countingLabels,
                line: line,
                league: league,
                startIndex: rateLabels.count
            )
            Text("Totals add up the current roster's season lines, so a player traded in July brings his whole year with him.")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkTertiary)
                .padding(.horizontal, SavantGeo.padCard)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func barGroup(
        title: String,
        labels: [String],
        line: [String: Double],
        league: [[String: Double]],
        startIndex: Int
    ) -> some View {
        let present = labels.filter { line[$0] != nil }
        return Group {
            if !present.isEmpty {
                SavantSubSectionBar(title: title)
                ForEach(Array(present.enumerated()), id: \.element) { offset, label in
                    let value = line[label] ?? 0
                    MetricBar(
                        metric: Metric(
                            id: "team-std-\(label)",
                            label: label,
                            value: format(label, value),
                            percentile: percentile(label: label, value: value, league: league) ?? 0,
                            category: side.category
                        )
                    )
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 12)
                    .background((startIndex + offset) % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentContent: some View {
        if !store.isPro {
            ZStack(alignment: .bottom) {
                teaser
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See every team's last 7 / 15 / 30 days",
                    cta: store.paywallBlurCTA,
                    subtext: store.paywallBlurSubtext,
                    action: onUpgradeTap
                )
            }
        } else if loading {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.75)
                Text("Loading recent games…")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let loadError {
            emptyState(loadError)
        } else {
            let totals = windowTotals()
            if totals.isEmpty {
                emptyState("No \(side.label.lowercased()) games in the last \(windowDays) days")
            } else {
                let rates = windowRates(totals)
                let seasonLine = teamLine(for: players)

                // Season → window, not a percentile bar. A fortnight's team
                // batting average sits outside the whole spread of thirty
                // *season* averages more often than not, so a bar drawn on that
                // ruler pins to 1 or 100 and says nothing. The move against the
                // team's own season number is the real information, and it's
                // the same framing the Trends board uses.
                if !rates.isEmpty {
                    SavantSubSectionBar(title: "RATE · LAST \(windowDays) DAYS")
                    ForEach(Array(rates.keys.sorted(by: sortByOrder).enumerated()), id: \.element) { index, label in
                        let now = rates[label] ?? 0
                        let then = seasonLine[label]
                        HStack(spacing: 10) {
                            Text(label)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                                .frame(width: 60, alignment: .leading)
                            if let then {
                                Text("\(format(label, then)) → \(format(label, now))")
                                    .font(SavantType.small)
                                    .monospacedDigit()
                                    .foregroundStyle(SavantPalette.inkSecondary)
                            } else {
                                Text(format(label, now))
                                    .font(SavantType.small)
                                    .monospacedDigit()
                                    .foregroundStyle(SavantPalette.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            if let then {
                                TrendArrow(
                                    delta: now - then,
                                    decimals: 3,
                                    lowerIsBetter: Self.lowerIsBetter(side).contains(label)
                                )
                            }
                        }
                        .padding(.horizontal, SavantGeo.padCard)
                        .frame(height: SavantGeo.rowHeight)
                        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                            alignment: .bottom
                        )
                    }
                    Text("Compared with the same team's season line.")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .padding(.horizontal, SavantGeo.padCard)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Counting stats get no bar. A fortnight's home runs against
                // thirty season totals would sit at the first percentile for
                // every team in the league, which says nothing.
                SavantSubSectionBar(title: "TOTALS · LAST \(windowDays) DAYS")
                let counts = Self.countingWindowKeys.filter { totals[$0.label] != nil }
                ForEach(Array(counts.enumerated()), id: \.element.label) { index, entry in
                    HStack {
                        Text(entry.label)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        Spacer()
                        Text(String(format: "%.0f", totals[entry.label] ?? 0))
                            .font(SavantType.statSmall)
                            .monospacedDigit()
                            .foregroundStyle(SavantPalette.ink)
                    }
                    .padding(.horizontal, SavantGeo.padCard)
                    .frame(height: SavantGeo.rowHeight)
                    .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    /// Invented numbers in the real layout, so a free user can see what the
    /// window actually reports rather than a padlock. It tracks the window
    /// picker, because a preview that ignores the control above it looks broken.
    private var teaser: some View {
        let rows = teaserRows
        return VStack(spacing: 0) {
            SavantSubSectionBar(title: "RATE · LAST \(windowDays) DAYS")
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                        .frame(width: 60, alignment: .leading)
                    Text("\(format(row.0, row.1)) → \(format(row.0, row.2))")
                        .font(SavantType.small)
                        .monospacedDigit()
                        .foregroundStyle(SavantPalette.inkSecondary)
                    Spacer(minLength: 0)
                    TrendArrow(delta: row.2 - row.1, decimals: 3)
                }
                .padding(.horizontal, SavantGeo.padCard)
                .frame(height: SavantGeo.rowHeight)
                .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
            }
            SavantSubSectionBar(title: "TOTALS · LAST \(windowDays) DAYS")
            ForEach(Array(teaserTotals.enumerated()), id: \.element.0) { index, row in
                HStack {
                    Text(row.0)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                    Spacer()
                    Text("\(row.1)")
                        .font(SavantType.statSmall)
                        .monospacedDigit()
                        .foregroundStyle(SavantPalette.ink)
                }
                .padding(.horizontal, SavantGeo.padCard)
                .frame(height: SavantGeo.rowHeight)
                .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
            }
        }
    }

    /// Season line → an invented window, per side and per window length. Built
    /// from *this* team's real season rates so the preview is the club the user
    /// is looking at, and so moving the Hitting/Pitching or 7/15/30 pickers
    /// visibly redraws it. Only the window column is fictional, and it stays
    /// behind the blur.
    private var teaserRows: [(String, Double, Double)] {
        let seasonLine = teamLine(for: players)
        let labels = rateLabels.filter { seasonLine[$0] != nil }
        let fallback: [(String, Double)] = side == .pitching
            ? [("ERA", 4.05), ("WHIP", 1.28), ("K/9", 8.6), ("BB/9", 3.1)]
            : [("AVG", 0.251), ("OBP", 0.318), ("SLG", 0.408), ("OPS", 0.726)]
        let base: [(String, Double)] = labels.isEmpty
            ? fallback
            : labels.prefix(4).map { ($0, seasonLine[$0] ?? 0) }

        return base.map { label, season in
            let seed = Self.stableSeed("\(label)-\(side.rawValue)-\(windowDays)-\(team)")
            // ±12% of the season figure — the size of a real fortnight's swing.
            let swing = season * Double(seed % 25 - 12) / 100
            return (label, season, season + swing)
        }
    }

    private var teaserTotals: [(String, Int)] {
        let scale = Double(windowDays) / 15
        return [("AB", 512), ("H", 147), ("HR", 21), ("BB", 48)].map { label, value in
            (label, Int((Double(value) * scale).rounded()))
        }
    }

    /// Deterministic across launches, unlike `hashValue`.
    private static func stableSeed(_ text: String) -> Int {
        abs(text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
    }

    // MARK: - Aggregation

    /// One team's standard line: counting stats summed, rates rebuilt from the
    /// quantity they're a rate of.
    private func teamLine(for roster: [Player]) -> [String: Double] {
        let pool = roster.filter { $0.matchesPlayerType(for: side.category) }
        guard !pool.isEmpty else { return [:] }

        var totals: [String: Double] = [:]
        var weighted: [String: (num: Double, den: Double)] = [:]

        for player in pool {
            let stats = player.standardStats ?? []
            func raw(_ label: String) -> Double? {
                stats.first { $0.label.uppercased() == label }
                    .flatMap { DashboardViewModel.rawNumeric($0.value) }
            }
            for stat in stats {
                let label = stat.label.uppercased()
                guard let value = DashboardViewModel.rawNumeric(stat.value) else { continue }
                if let weightKey = Self.rateWeights[label] {
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

    /// The other twenty-nine, plus this one — the distribution a bar is drawn
    /// against.
    private func leagueLines() -> [[String: Double]] {
        Dictionary(grouping: leaguePlayers, by: \.team)
            .values
            .map { teamLine(for: $0) }
            .filter { !$0.isEmpty }
    }

    private func percentile(label: String, value: Double, league: [[String: Double]]) -> Int? {
        let values = league.compactMap { $0[label] }
        // Thirty clubs is the whole population, so anything much short of it
        // means the season hasn't been aggregated yet.
        guard values.count >= 10 else { return nil }
        let below = values.reduce(0) { $0 + ($1 < value ? 1 : 0) }
        let equal = values.reduce(0) { $0 + ($1 == value ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        let oriented = Self.lowerIsBetter(side).contains(label) ? 100 - raw : raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    // MARK: - Window

    /// Game-log key → the label it's displayed under. The rollup's own naming,
    /// so the two stay in step.
    private static let countingWindowKeys: [(key: String, label: String)] = [
        ("_ab", "AB"), ("_h", "H"), ("_2b", "2B"), ("_3b", "3B"), ("_hr", "HR"),
        ("_bb", "BB"), ("_so", "SO"),
    ]

    private var sideLogs: [PlayerGameLog] {
        let ofSide = logs.filter { $0.playerType == side.playerType }
        guard let anchor = ofSide.map(\.gameDate).max() else { return [] }
        let calendar = Calendar.current
        let start = calendar.date(
            byAdding: .day,
            value: -(windowDays - 1),
            to: calendar.startOfDay(for: anchor)
        ) ?? anchor
        return ofSide.filter { $0.gameDate >= start }
    }

    /// Summed counting stats for the window, keyed by display label.
    private func windowTotals() -> [String: Double] {
        let window = sideLogs
        guard !window.isEmpty else { return [:] }
        var totals: [String: Double] = [:]
        for log in window {
            for (key, label) in Self.countingWindowKeys {
                if let value = log.metrics[key] ?? nil {
                    totals[label, default: 0] += value
                }
            }
            for key in ["_hbp", "_sf", "_tb"] {
                if let value = log.metrics[key] ?? nil {
                    totals[key, default: 0] += value
                }
            }
        }
        return totals
    }

    /// AVG / OBP / SLG / OPS rebuilt from the window's sums — the same identity
    /// the backend rollup uses, so the numbers agree with the Trends board.
    private func windowRates(_ totals: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        let ab = totals["AB"] ?? 0
        let hits = totals["H"] ?? 0
        let walks = totals["BB"] ?? 0
        let hbp = totals["_hbp"] ?? 0
        let sf = totals["_sf"] ?? 0
        let tb = totals["_tb"] ?? 0

        if ab > 0 {
            out["AVG"] = hits / ab
            if tb > 0 { out["SLG"] = tb / ab }
        }
        let onBaseDenom = ab + walks + hbp + sf
        if onBaseDenom > 0 {
            out["OBP"] = (hits + walks + hbp) / onBaseDenom
        }
        if let obp = out["OBP"], let slg = out["SLG"] {
            out["OPS"] = obp + slg
        }
        return out
    }

    private func sortByOrder(_ a: String, _ b: String) -> Bool {
        let ai = order.firstIndex(of: a) ?? Int.max
        let bi = order.firstIndex(of: b) ?? Int.max
        return ai < bi
    }

    private func load() async {
        guard store.isPro, let fetch = fetchTeamGameLogs else { return }
        loading = true
        loadError = nil
        do {
            let since = Calendar.current.date(byAdding: .day, value: -37, to: .now) ?? .now
            logs = try await fetch(team, season, since)
        } catch {
            loadError = "Couldn't load team form. Pull to refresh."
        }
        loading = false
    }

    // MARK: - Formatting

    private func format(_ label: String, _ value: Double) -> String {
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

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(SavantPalette.inkTertiary)
            Text(message)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
