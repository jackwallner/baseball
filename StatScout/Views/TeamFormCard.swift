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
        case season = "Season", recent = "Recent"
        var id: String { rawValue }
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

            sidePicker
                .padding(.horizontal, SavantGeo.padInline)
                .padding(.vertical, 8)
                .background(SavantPalette.surfaceAlt)

            modePicker

            if mode == .recent {
                windowPicker
            }

            if mode == .season {
                seasonBars
            } else {
                recentSection
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(mode.rawValue)") {
            if mode == .recent { await load() }
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
        HStack(spacing: 0) {
            ForEach(Side.allCases) { s in
                Button {
                    side = s
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(s.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(side == s ? SavantPalette.ink : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(
                            Rectangle()
                                .fill(side == s ? SavantPalette.savantRed : Color.clear)
                                .frame(height: 2)
                                .padding(.top, 32),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases) { m in
                Button {
                    mode = m
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(m.rawValue)
                        .font(SavantType.smallBold)
                        .foregroundStyle(mode == m ? .white : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(mode == m ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.vertical, 10)
        .background(SavantPalette.surfaceAlt)
    }

    private var windowPicker: some View {
        HStack(spacing: 6) {
            ForEach(RecentFormWindow.windows, id: \.days) { w in
                Button {
                    windowDays = w.days
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(w.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(windowDays == w.days ? .white : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(windowDays == w.days ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(w.label) days")
            }
        }
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.bottom, 8)
        .background(SavantPalette.surfaceAlt)
    }

    // MARK: - Season

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
        let pool = players.filter { ($0.playerType ?? "") == side.playerType }
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

    private func formattedValue(_ v: Double, label: String) -> String {
        if label == "xwOBA" { return String(format: "%.3f", v) }
        if label == "EV"     { return String(format: "%.1f mph", v) }
        if label.hasSuffix("%") { return String(format: "%.1f%%", v) }
        return String(format: "%.2f", v)
    }

    // MARK: - Recent

    private var sideLogs: [PlayerGameLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now) ?? .now
        return logs.filter { $0.playerType == side.playerType && $0.gameDate >= cutoff }
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
                recentBars
                    .blur(radius: 5)
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
            let rows = recentMetricRows(window: w)
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

    private func recentMetricRows(window w: RecentFormWindow) -> [Metric] {
        let category: MetricCategory = side == .pitching ? .pitching : .hitting
        let specs: [(key: String, label: String, seasonLabel: String, format: String)] = side == .pitching
            ? [
                ("opp_xwoba",       "Opp xwOBA",     "xwOBA",          "%.3f"),
                ("k_pct",           "K%",            "K%",             "%.1f%%"),
                ("bb_pct",          "BB%",           "BB%",            "%.1f%%"),
                ("opp_hardhit_pct", "Opp Hard-Hit%", "Hard-Hit%",      "%.1f%%"),
                ("opp_barrel_pct",  "Opp Barrel%",   "Barrel%",        "%.1f%%"),
                ("opp_ev_avg",      "Opp EV",        "Avg EV Against", "%.1f mph"),
            ]
            : [
                ("xwoba",       "xwOBA",     "xwOBA",     "%.3f"),
                ("barrel_pct",  "Barrel%",   "Barrel%",   "%.1f%%"),
                ("hardhit_pct", "Hard-Hit%", "Hard-Hit%", "%.1f%%"),
                ("ev_avg",      "EV",        "EV",        "%.1f mph"),
                ("k_pct",       "K%",        "K%",        "%.1f%%"),
                ("bb_pct",      "BB%",       "BB%",       "%.1f%%"),
            ]

        return specs.compactMap { spec -> Metric? in
            guard let v = w.metrics[spec.key],
                  let pct = curves?.curve(for: spec.seasonLabel)?.percentile(for: v) else { return nil }
            return Metric(
                id: "team-\(spec.key)",
                label: spec.label,
                value: String(format: spec.format, v),
                percentile: pct,
                category: category
            )
        }
    }

    private func load() async {
        guard let fetch = fetchTeamGameLogs else { return }
        loading = true
        loadError = nil
        do {
            // 30 days back covers the largest window — 7/15 are derived client-side.
            let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
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
        let recentSeasonLabels = ["xwOBA", "Barrel%", "Hard-Hit%", "EV", "Avg EV Against", "K%", "BB%"]
        let rosterLabels = players.flatMap { $0.metrics.map(\.label) }
        let labels = Array(Set(rosterLabels + recentSeasonLabels))
        batterCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "batter", labels: labels)
        pitcherCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "pitcher", labels: labels)
    }
}
