import SwiftUI

/// Last 7 / 15 / 30 day rolling form for a single player. Pro-gated: free
/// users see a blurred static teaser and an upgrade CTA — no game-log fetch.
/// Pro users load game logs once, then compute window aggregates client-side
/// so we don't pay a round-trip when the user switches windows.
struct RecentFormCard: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let season: Int
    /// League pool used to build the value→percentile curve so the recent bar
    /// sits on the same ruler as the season bar. Filtered to the player's type
    /// at curve-build time.
    let leaguePlayers: [Player]
    let fetchGameLogs: ((Int, Int) async throws -> [PlayerGameLog])?
    let onUpgradeTap: () -> Void

    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var windowDays: Int = 15
    @State private var curves: LeaguePercentileCurves?

    private var isPitcher: Bool {
        player.playerType == "pitcher"
    }

    /// Smallest sample we'll consider trustworthy. Anything below shows the
    /// numbers but tags them as "small sample" so the user reads them with
    /// appropriate skepticism.
    private var smallSamplePAThreshold: Int { isPitcher ? 30 : 15 }

    private var windowLogs: [PlayerGameLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now) ?? .now
        return logs.filter { $0.gameDate >= cutoff }
    }

    private var window: RecentFormWindow? {
        guard !windowLogs.isEmpty else { return nil }
        return RecentFormWindow.build(
            label: "Last \(windowDays)",
            days: windowDays,
            logs: windowLogs
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
        .task(id: player.playerId) {
            await load()
        }
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
    }

    private func rebuildCurves() {
        guard store.isPro else { return }
        // Pitchers' season exit velocity is labeled "Avg EV Against", not "EV".
        let evLabel = isPitcher ? "Avg EV Against" : "EV"
        var labels = ["xwOBA", "Barrel%", "Hard-Hit%", evLabel, "K%", "BB%"]
        if !isPitcher { labels.append("Max EV") }
        curves = LeaguePercentileCurves(
            players: leaguePlayers,
            playerType: player.playerType ?? (isPitcher ? "pitcher" : "batter"),
            labels: labels
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SavantPalette.savantRed)
                Text("RECENT FORM")
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
                teaserBody
                    .blur(radius: 8)
                    .disabled(true)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See last 7 / 15 / 30 day form for any player",
                    cta: store.paywallBlurCTA,
                    subtext: store.paywallBlurSubtext,
                    action: onUpgradeTap
                )
            }
        }
    }

    /// Static, non-fetching preview for free users. No game logs are loaded —
    /// these are illustrative bars in the season percentile format so the blur
    /// reads as "real recent-form bars" without paying the network/battery cost.
    private var teaserBody: some View {
        let sample: [Metric] = [
            Metric(id: "t_xwoba",   label: "xwOBA",     value: "0.412",    percentile: 94, category: .hitting),
            Metric(id: "t_barrel",  label: "Barrel%",   value: "18.2%",    percentile: 88, category: .hitting),
            Metric(id: "t_hardhit", label: "Hard-Hit%", value: "52.1%",    percentile: 81, category: .hitting),
            Metric(id: "t_ev",      label: "EV",        value: "93.4 mph", percentile: 76, category: .hitting),
        ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "G", value: "12")
                summaryStat(label: isPitcher ? "BF" : "PA", value: "48")
                if !isPitcher { summaryStat(label: "BBE", value: "31") }
                Spacer(minLength: 0)
            }
            .padding(SavantGeo.padInline)

            metricBarList(sample)
        }
    }

    @ViewBuilder
    private var proContent: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
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
        } else if let w = window {
            statsBody(window: w)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(SavantPalette.inkTertiary)
                Text("No games in the last \(windowDays) days")
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
                summaryStat(label: isPitcher ? "BF" : "PA", value: "\(w.plateAppearances)")
                if !isPitcher {
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

    /// Recent-window metrics rendered with the exact same `MetricBar` row used
    /// on the season percentile card — same label/bar/value layout and the same
    /// alternating row backgrounds — so recent form reads on the identical ruler.
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

    /// Recent-window metrics mapped to `Metric` so they render with the season
    /// `MetricBar`. The percentile is interpolated from the league season curve
    /// (so the recent bar sits on the same ruler as the season card); the value
    /// is the recent-window number. Skips metrics with no window data or no
    /// curve so we never draw a bar we can't place.
    private func recentMetricRows(window w: RecentFormWindow) -> [Metric] {
        let category: MetricCategory = isPitcher ? .pitching : .hitting
        let specs: [(key: String, label: String, seasonLabel: String, format: String)] = isPitcher
            ? [
                ("opp_xwoba",       "xwOBA",       "xwOBA",     "%.3f"),
                ("k_pct",           "K%",          "K%",        "%.1f%%"),
                ("bb_pct",          "BB%",         "BB%",       "%.1f%%"),
                ("opp_hardhit_pct", "Hard-Hit%",   "Hard-Hit%", "%.1f%%"),
                ("opp_barrel_pct",  "Barrel%",     "Barrel%",   "%.1f%%"),
                ("opp_ev_avg",      "EV",          "Avg EV Against", "%.1f mph"),
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
                id: spec.key,
                label: spec.label,
                value: String(format: spec.format, v),
                percentile: pct,
                category: category
            )
        }
    }

    private func load() async {
        // Free users see a static teaser — no game-log fetch, no battery cost.
        guard store.isPro, let fetch = fetchGameLogs else { return }
        loading = true
        loadError = nil
        do {
            let result = try await fetch(player.playerId, season)
            logs = result
        } catch {
            loadError = "Couldn't load recent games. Pull to refresh."
        }
        loading = false
    }
}
