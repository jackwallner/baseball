import SwiftUI

/// Team "percentile rankings" card — the team-level analogue of the player
/// profile's percentile card. Aggregates the roster into one synthetic
/// "team-as-a-player" and renders its profile as percentile bars on the league
/// ruler, with a Season / Recent toggle that mirrors the player page:
///
/// - **Season**: PA/IP-weighted mean of every roster metric for the active side,
///   placed on the league curve. Tapping a bar opens that metric's leaderboard.
/// - **Recent**: the same aggregation over the last 7 / 15 / 30 days of game
///   logs. Pro-gated with the standard blur + CTA, identical to the player card.
///
/// This replaces the old split between a season "team average" card and a
/// separate "team recent form" card, which read as two disconnected modules.
struct TeamRankingsCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    /// The roster for this team/season.
    let players: [Player]
    /// League pool used to build the value→percentile curve so the team bar sits
    /// on the same ruler as individual players' bars. Filtered per side at
    /// curve-build time.
    let leaguePlayers: [Player]
    let fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])?
    let onUpgradeTap: () -> Void

    @State private var side: Side = .batting
    @State private var mode: Mode = .season
    @State private var windowDays: Int = 15
    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var batterCurves: LeaguePercentileCurves?
    @State private var pitcherCurves: LeaguePercentileCurves?

    enum Side: String, CaseIterable, Identifiable {
        case batting, pitching
        var id: String { rawValue }
        var label: String { self == .batting ? "Hitting" : "Pitching" }
        var playerType: String { self == .batting ? "batter" : "pitcher" }
        var category: MetricCategory { self == .batting ? .hitting : .pitching }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case season = "Season", recent = "Recent", both = "Both"
        var id: String { rawValue }

        /// Whether this mode needs game logs — and therefore whether the
        /// window picker is worth showing.
        var usesRecent: Bool { self != .season }
    }

    /// Smallest team-window PA we'll treat as trustworthy — below this we flag
    /// the window as a small sample (rainouts, all-star break, late call-ups).
    private let smallSamplePAThreshold = 80

    private var curves: LeaguePercentileCurves? {
        side == .pitching ? pitcherCurves : batterCurves
    }

    var body: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "TEAM PERCENTILE RANKINGS",
                trailing: store.isPro ? nil : AnyView(proBadge)
            )

            // Side and mode share one row. They used to be stacked, which with
            // the identity strip, the tab selector and the window picker put
            // the first actual stat past halfway down the screen.
            HStack(spacing: 8) {
                sidePicker
                Spacer(minLength: 8)
                modePicker
            }
            .padding(.horizontal, SavantGeo.padInline)
            .padding(.vertical, 8)
            .background(SavantPalette.surfaceAlt)

            if mode.usesRecent {
                windowPicker
            }

            switch mode {
            case .season: seasonBars
            case .recent: recentSection
            case .both: bothSection
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(mode.rawValue)-\(store.isPro)") {
            if mode.usesRecent, store.isPro { await load() }
        }
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
    }

    private var proBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
            Text("STATSCOUT+")
                .font(SavantType.micro)
                .tracking(0.4)
                .fontWeight(.bold)
        }
        .foregroundStyle(SavantPalette.savantNavy)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.yellow)
        .clipShape(Capsule())
    }

    // MARK: - Pickers

    private var sidePicker: some View {
        SavantSegmented(
            segments: Side.allCases.map { .init(value: $0, label: $0.label) },
            selection: $side
        )
    }

    private var modePicker: some View {
        SavantSegmented(
            segments: Mode.allCases.map {
                .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 != .season)
            },
            selection: $mode,
            onLockedTap: { _ in onUpgradeTap() }
        )
    }

    /// Season and recent bars paired on one row, the same DualMetricBar the
    /// player page uses — so a team reads the way a player does.
    private var bothSection: some View {
        let seasonRows = aggregateSeasonRows()
        // Deliberately NOT recentDisplayRows: that falls back to the season
        // aggregate when the window has no data for a metric, which is right
        // for Recent (show the full slate) but a lie here — it would print the
        // season number under a "Last 15d" label and imply nothing moved.
        let recentRows: [String: Metric] = {
            guard let w = recentWindow else { return [:] }
            let pairs = seasonRows.compactMap { row -> (String, Metric)? in
                guard let recent = recentMetric(forSeasonLabel: row.label, window: w) else { return nil }
                return (row.label, recent)
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }()

        return VStack(spacing: 0) {
            if loading {
                loadingRow
            } else if let loadError {
                errorRow(loadError)
            } else {
                ForEach(Array(seasonRows.enumerated()), id: \.element.id) { index, metric in
                    DualMetricBar(
                        season: metric,
                        recent: recentRows[metric.label],
                        recentCaption: "Last \(windowDays)d"
                    )
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 10)
                    .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.75)
            Text("Loading recent games…")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(SavantType.small)
            .foregroundStyle(SavantPalette.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private var windowPicker: some View {
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

    @ViewBuilder
    private var seasonBars: some View {
        let rows = aggregateSeasonRows()
        if rows.isEmpty {
            emptyAggregate
        } else {
            SavantSubSectionBar(title: side.category.rawValue.uppercased())

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                    NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
                        MetricBar(metric: metric)
                            .padding(.horizontal, SavantGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                            .overlay(
                                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                                alignment: .bottom
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("See the league leaderboard for \(metric.label)")
                }
            }

            weightedCaption
        }
    }

    /// One bar per roster metric — PA/IP-weighted mean placed on the league curve.
    private func aggregateSeasonRows() -> [Metric] {
        // matchesPlayerType keeps two-way players in both pools (Ohtani hits AND pitches).
        let pool = players.filter { $0.matchesPlayerType(for: side.category) }
        guard !pool.isEmpty, let curves else { return [] }

        let present = Set(pool.flatMap { p in
            p.metrics.filter { $0.category == side.category }.map(\.label)
        })
        let ordered = side.category.metricPriorityOrder.filter { present.contains($0) }
        let labels = ordered + present.subtracting(side.category.metricPriorityOrder).sorted()

        return labels.compactMap { label -> Metric? in
            var weightedSum = 0.0
            var weightTotal = 0.0
            for player in pool {
                guard let m = player.metrics.first(where: { $0.label == label && $0.category == side.category }),
                      let v = DashboardViewModel.rawNumeric(m.value) else { continue }
                let w = workload(player) ?? 1.0
                weightedSum += v * w
                weightTotal += w
            }
            guard weightTotal > 0 else { return nil }
            let avg = weightedSum / weightTotal
            guard let pct = curves.curve(for: label)?.percentile(for: avg) else { return nil }
            return Metric(
                id: "teamavg-\(label)",
                label: label,
                value: formattedValue(avg, label: label),
                percentile: pct,
                category: side.category
            )
        }
    }

    /// Workload for weighting — PA for batters, IP for pitchers, read from the
    /// standard-stats block. nil falls back to equal weighting.
    private func workload(_ player: Player) -> Double? {
        let key = side == .pitching ? "IP" : "PA"
        guard let raw = player.standardStats?.first(where: { $0.label == key })?.value else { return nil }
        return DashboardViewModel.rawNumeric(raw)
    }

    /// Matches the player page's conventions. The old fallback of two decimals
    /// printed a team's xBA as "0.25" next to a player's ".250", and bat speed
    /// as "69.60" with a meaningless trailing zero and no unit.
    private func formattedValue(_ v: Double, label: String) -> String {
        if label.hasSuffix("%") { return String(format: "%.1f%%", v) }
        if label.hasSuffix("Spin") { return String(format: "%.0f rpm", v) }
        if label == "Swing Length" { return String(format: "%.2f ft", v) }
        if label.contains("EV") || label.contains("Velo") || label == "Bat Speed" {
            return String(format: "%.1f mph", v)
        }
        // Rate stats — xwOBA, xBA, xSLG, xISO and the traditional slash line.
        if v < 10 { return String(format: "%.3f", v) }
        return String(format: "%.1f", v)
    }

    // MARK: - Recent

    /// Anchored to the last game in the data rather than to the clock. The
    /// pipeline runs overnight, so "now minus 15 days" against a feed that ends
    /// two days ago silently drops the oldest days of the window and shrinks
    /// the sample — and it disagreed with the backend rollup, which anchors to
    /// the last game date. Start-of-day, so the hour you open the app doesn't
    /// decide whether the earliest game counts.
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

    private var recentWindow: RecentFormWindow? {
        guard !sideLogs.isEmpty else { return nil }
        return RecentFormWindow.build(label: "Last \(windowDays)", days: windowDays, logs: sideLogs)
    }

    @ViewBuilder
    private var recentSection: some View {
        if store.isPro {
            recentBars
        } else {
            ZStack(alignment: .bottom) {
                recentTeaser
                    .blur(radius: 8)
                    .disabled(true)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See every team's last 7 / 15 / 30 day form",
                    cta: store.paywallBlurCTA,
                    subtext: store.paywallBlurSubtext,
                    action: onUpgradeTap
                )
            }
        }
    }

    /// Static, non-fetching preview for free users — illustrative team bars in
    /// the recent-form layout. No game logs are fetched (no network/battery cost)
    /// and no real team data is shown, so the blur can't be read through to leak
    /// the actual recent numbers.
    private var recentTeaser: some View {
        let sample: [Metric] = side == .batting
            ? [
                Metric(id: "tt_xwoba",   label: "xwOBA",     value: "0.342",    percentile: 84, category: .hitting),
                Metric(id: "tt_barrel",  label: "Barrel%",   value: "9.8%",     percentile: 77, category: .hitting),
                Metric(id: "tt_hardhit", label: "Hard-Hit%", value: "43.5%",    percentile: 71, category: .hitting),
                Metric(id: "tt_ev",      label: "EV",        value: "90.1 mph", percentile: 66, category: .hitting),
            ]
            : [
                Metric(id: "tt_xwoba", label: "xwOBA",     value: "0.298", percentile: 81, category: .pitching),
                Metric(id: "tt_k",     label: "K%",        value: "25.1%", percentile: 76, category: .pitching),
                Metric(id: "tt_bb",    label: "BB%",       value: "7.2%",  percentile: 70, category: .pitching),
                Metric(id: "tt_hh",    label: "Hard-Hit%", value: "36.4%", percentile: 73, category: .pitching),
            ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "G", value: "14")
                summaryStat(label: side == .pitching ? "BF" : "PA", value: "521")
                if side == .batting { summaryStat(label: "BBE", value: "318") }
                Spacer(minLength: 0)
            }
            .padding(SavantGeo.padInline)

            SavantSubSectionBar(title: side.category.rawValue.uppercased())
            VStack(spacing: 0) {
                ForEach(Array(sample.enumerated()), id: \.element.id) { index, metric in
                    MetricBar(metric: metric)
                        .padding(.horizontal, SavantGeo.padCard)
                        .padding(.vertical, 12)
                        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                            alignment: .bottom
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var recentBars: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().progressViewStyle(.circular).scaleEffect(0.75)
                Text("Loading recent games…")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let err = loadError {
            Text(err)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SavantGeo.padInline)
                .padding(.vertical, 24)
        } else if let w = recentWindow {
            recentSummaryRow(w)
            let rows = recentDisplayRows(window: w)
            if !rows.isEmpty {
                SavantSubSectionBar(title: side.category.rawValue.uppercased())
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                        MetricBar(metric: metric)
                            .padding(.horizontal, SavantGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                            .overlay(
                                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                                alignment: .bottom
                            )
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(SavantPalette.inkTertiary)
                Text("No \(side.label.lowercased()) data in the last \(windowDays) days")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private func recentSummaryRow(_ w: RecentFormWindow) -> some View {
        HStack(spacing: 12) {
            summaryStat(label: "G", value: "\(w.games)")
            summaryStat(label: side == .pitching ? "BF" : "PA", value: "\(w.plateAppearances)")
            if side == .batting {
                summaryStat(label: "BBE", value: "\(w.battedBallEvents)")
            }
            Spacer(minLength: 0)
            if w.plateAppearances < smallSamplePAThreshold {
                Text("SMALL SAMPLE")
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SavantPalette.inkTertiary)
                    .clipShape(Capsule())
            }
        }
        .padding(SavantGeo.padInline)
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(SavantType.micro)
                .tracking(0.4)
                .foregroundStyle(SavantPalette.inkTertiary)
            Text(value)
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
        }
    }

    /// Maps a recent game-log metric onto the matching season aggregate label.
    /// Keyed by `seasonLabel` so a recent value can overlay the season bar it
    /// corresponds to (pitchers' recent EV maps onto "Avg EV Against", etc.).
    private var recentSpecs: [(key: String, seasonLabel: String, format: String)] {
        side == .pitching
            ? [
                ("opp_xwoba",       "xwOBA",           "%.3f"),
                ("opp_xba",         "xBA",             "%.3f"),
                ("opp_xslg",        "xSLG",            "%.3f"),
                ("k_pct",           "K%",              "%.1f%%"),
                ("bb_pct",          "BB%",             "%.1f%%"),
                ("opp_hardhit_pct", "Hard-Hit%",       "%.1f%%"),
                ("opp_barrel_pct",  "Barrel%",         "%.1f%%"),
                ("opp_ev_avg",      "Avg EV Against",  "%.1f mph"),
                ("opp_ev_max",      "Max EV Against",  "%.1f mph"),
                ("fb_velo_avg",     "Fastball Velo",   "%.1f mph"),
                ("fb_spin_avg",     "Fastball Spin",   "%.0f rpm"),
            ]
            : [
                ("xwoba",        "xwOBA",        "%.3f"),
                ("xba",          "xBA",          "%.3f"),
                ("xslg",         "xSLG",         "%.3f"),
                ("xiso",         "xISO",         "%.3f"),
                ("barrel_pct",   "Barrel%",      "%.1f%%"),
                ("hardhit_pct",  "Hard-Hit%",    "%.1f%%"),
                ("ev_avg",       "EV",           "%.1f mph"),
                ("ev_max",       "Max EV",       "%.1f mph"),
                ("k_pct",        "K%",           "%.1f%%"),
                ("bb_pct",       "BB%",          "%.1f%%"),
                ("whiff_pct",    "Whiff%",       "%.1f%%"),
                ("chase_pct",    "Chase%",       "%.1f%%"),
                ("bat_speed",    "Bat Speed",    "%.1f mph"),
                ("swing_length", "Swing Length", "%.2f ft"),
            ]
    }

    /// Recent mode mirrors the season list: every season aggregate bar is shown.
    /// Metrics with game-log data in the window render the recent value (re-placed
    /// on the league curve); the rest fall back to their season aggregate bar — so
    /// a team's Recent view shows the same full slate of stats as its Season view,
    /// not just the handful the per-game feed carries. Recent specs the season
    /// aggregate omits (Savant sometimes drops e.g. Hard-Hit%) are injected as
    /// stubs so their recent bar still appears.
    private func recentDisplayRows(window w: RecentFormWindow) -> [Metric] {
        let seasonRows = aggregateSeasonRows()
        let existing = Set(seasonRows.map(\.label))
        let stubs: [Metric] = recentSpecs.compactMap { spec in
            guard !existing.contains(spec.seasonLabel),
                  recentMetric(forSeasonLabel: spec.seasonLabel, window: w) != nil else { return nil }
            return Metric(
                id: "team-recent-stub-\(spec.key)",
                label: spec.seasonLabel,
                value: "",
                percentile: 0,
                category: side.category
            )
        }
        return (seasonRows + stubs).map { recentMetric(forSeasonLabel: $0.label, window: w) ?? $0 }
    }

    /// The recent-window bar for a given season label, or nil if the window has
    /// no game-log data for it (caller falls back to the season aggregate bar).
    private func recentMetric(forSeasonLabel label: String, window w: RecentFormWindow) -> Metric? {
        guard let spec = recentSpecs.first(where: { $0.seasonLabel == label }),
              let v = w.metrics[spec.key],
              let pct = curves?.curve(for: label)?.percentile(for: v) else { return nil }
        return Metric(
            id: "team-recent-\(spec.key)",
            label: label,
            value: String(format: spec.format, v),
            percentile: pct,
            category: side.category
        )
    }

    private func load() async {
        // Free users see a static teaser — never fetch real team game logs.
        guard store.isPro, let fetch = fetchTeamGameLogs else { return }
        loading = true
        loadError = nil
        do {
            // 30 days back covers the largest window — 7/15 are derived
            // client-side. The extra week absorbs pipeline lag: the windows
            // anchor to the last game in the data, which can trail today.
            let since = Calendar.current.date(byAdding: .day, value: -37, to: .now) ?? .now
            logs = try await fetch(team, season, since)
        } catch {
            loadError = "Couldn't load team form. Pull to refresh."
        }
        loading = false
    }

    // MARK: - Shared bits

    private var emptyAggregate: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22))
                .foregroundStyle(SavantPalette.inkTertiary)
            Text("Not enough \(side.label.lowercased()) data to aggregate")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var weightedCaption: some View {
        Text("Weighted by \(side == .pitching ? "IP" : "PA") across the \(side.label.lowercased()) roster")
            .font(SavantType.micro)
            .tracking(0.3)
            .foregroundStyle(SavantPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SavantGeo.padCard)
            .padding(.vertical, 10)
    }

    private func rebuildCurves() {
        // Cover both the season aggregate labels (every roster metric) and the
        // recent specs' season labels (e.g. pitchers' "Avg EV Against").
        let recentSeasonLabels = ["xwOBA", "Barrel%", "Hard-Hit%", "EV", "Max EV", "Avg EV Against", "K%", "BB%"]
        let rosterLabels = players.flatMap { $0.metrics.map(\.label) }
        let labels = Array(Set(rosterLabels + recentSeasonLabels))
        batterCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "batter", labels: labels)
        pitcherCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "pitcher", labels: labels)
    }
}
