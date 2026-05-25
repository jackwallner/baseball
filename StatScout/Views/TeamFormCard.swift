import SwiftUI

/// Team-wide Recent Form (last 7 / 15 / 30 day windows) — aggregates every
/// rostered batter and pitcher's per-game logs into team-level rate stats.
/// Pro-gated with the same blur + CTA pattern as the player-level card so
/// the experience matches across surfaces.
struct TeamFormCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    /// League pool used to build the value→percentile curve so the recent team
    /// bar sits on the same ruler as individual players' season bars. Filtered
    /// per side (batter/pitcher) at curve-build time.
    let leaguePlayers: [Player]
    let fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])?
    let onUpgradeTap: () -> Void

    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var windowDays: Int = 15
    @State private var side: Side = .batting
    @State private var batterCurves: LeaguePercentileCurves?
    @State private var pitcherCurves: LeaguePercentileCurves?

    enum Side: String, CaseIterable, Identifiable {
        case batting, pitching
        var id: String { rawValue }
        var label: String { self == .batting ? "Hitting" : "Pitching" }
        var playerType: String { self == .batting ? "batter" : "pitcher" }
    }

    /// Smallest team-window PA we'll consider trustworthy. A team logs ~30 PA
    /// per game so a 7-day window is normally 200+; below 80 we tag it as
    /// small sample (rainouts, all-star break, late call-up team).
    private let smallSamplePAThreshold = 80

    private var sideLogs: [PlayerGameLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now) ?? .now
        return logs.filter { $0.playerType == side.playerType && $0.gameDate >= cutoff }
    }

    private var window: RecentFormWindow? {
        guard !sideLogs.isEmpty else { return nil }
        return RecentFormWindow.build(
            label: "Last \(windowDays)",
            days: windowDays,
            logs: sideLogs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .task(id: team + "-" + String(season)) {
            await load()
        }
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
    }

    private func rebuildCurves() {
        let labels = ["xwOBA", "Barrel%", "Hard-Hit%", "EV", "K%", "BB%"]
        batterCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "batter", labels: labels)
        pitcherCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "pitcher", labels: labels)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SavantPalette.savantRed)
                Text("TEAM RECENT FORM")
                    .font(SavantType.micro)
                    .tracking(0.6)
                    .foregroundStyle(SavantPalette.inkSecondary)
                Spacer()
                if !store.isPro {
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
            }
            .padding(.horizontal, SavantGeo.padInline)
            .padding(.top, 12)

            sidePicker
                .padding(.horizontal, SavantGeo.padInline)

            windowPicker
                .padding(.horizontal, SavantGeo.padInline)
                .padding(.bottom, 10)
        }
        .background(SavantPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
    }

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
                        .frame(height: 30)
                        .background(windowDays == w.days ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(w.label) days")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isPro {
            proContent
        } else {
            ZStack(alignment: .bottom) {
                proContent
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
    private var proContent: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
                Text("Loading team form…")
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
        } else if let w = window {
            statsBody(window: w)
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

    private func statsBody(window w: RecentFormWindow) -> some View {
        VStack(spacing: 0) {
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

            metricBarList(recentMetricRows(window: w))
        }
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

    /// Renders each recent-window metric as a `MetricBar` row so the team's
    /// recent form sits on the same percentile ruler as individual players'
    /// season bars. The team value is the weighted aggregate already computed
    /// upstream; the curve comes from the league pool filtered to the active
    /// side (batter / pitcher).
    private func metricBarList(_ rows: [Metric]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                MetricBar(metric: metric)
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                    .overlay(
                        Rectangle()
                            .fill(SavantPalette.divider)
                            .frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
            }
        }
    }

    private func recentMetricRows(window w: RecentFormWindow) -> [Metric] {
        let category: MetricCategory = side == .pitching ? .pitching : .hitting
        let curves = side == .pitching ? pitcherCurves : batterCurves
        let specs: [(key: String, label: String, seasonLabel: String, format: String)] = side == .pitching
            ? [
                ("opp_xwoba",       "Opp xwOBA",     "xwOBA",     "%.3f"),
                ("k_pct",           "K%",            "K%",        "%.1f%%"),
                ("bb_pct",          "BB%",           "BB%",       "%.1f%%"),
                ("opp_hardhit_pct", "Opp Hard-Hit%", "Hard-Hit%", "%.1f%%"),
                ("opp_barrel_pct",  "Opp Barrel%",   "Barrel%",   "%.1f%%"),
                ("opp_ev_avg",      "Opp EV",        "EV",        "%.1f mph"),
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
            // 30 days back covers the largest window — the 7/15 windows are
            // derived client-side from the same dataset.
            let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
            logs = try await fetch(team, season, since)
        } catch {
            loadError = "Couldn't load team form. Pull to refresh."
        }
        loading = false
    }
}
