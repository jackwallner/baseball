import SwiftUI

/// Last 7 / 15 / 30 day rolling form for a single player. Pro-gated: free
/// users see a blurred preview and an upgrade CTA. Loads game logs on
/// appear, then computes window aggregates client-side so we don't pay a
/// round-trip when the user switches windows.
struct RecentFormCard: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let season: Int
    let fetchGameLogs: ((Int, Int) async throws -> [PlayerGameLog])?
    let onUpgradeTap: () -> Void

    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var windowDays: Int = 15

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
                        Text("PRO")
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
            ZStack {
                proContent
                    .blur(radius: 6)
                    .disabled(true)
                    .allowsHitTesting(false)
                upgradeOverlay
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
        VStack(spacing: 12) {
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

            metricsGrid(window: w)
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

    private func metricsGrid(window w: RecentFormWindow) -> some View {
        let rows = metricRows(window: w)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(rows, id: \.label) { row in
                metricCell(row: row)
            }
        }
    }

    private func metricCell(row: MetricRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.label)
                .font(SavantType.micro)
                .tracking(0.4)
                .foregroundStyle(SavantPalette.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.display)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                if let delta = row.deltaDisplay {
                    Text(delta)
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(row.deltaColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SavantPalette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private struct MetricRow {
        let label: String
        let display: String
        let deltaDisplay: String?
        let deltaColor: Color
    }

    /// The set of metrics worth showing — same shape both sides of the ball,
    /// just relabeled. Skips rows the window has no data for so we don't
    /// render hollow cells.
    private func metricRows(window w: RecentFormWindow) -> [MetricRow] {
        if isPitcher {
            return [
                row(w, key: "opp_xwoba", label: "Opp xwOBA", seasonLabel: "xwOBA", format: "%.3f", lowerIsBetter: true),
                row(w, key: "k_pct", label: "K%", seasonLabel: "K%", format: "%.1f%%", lowerIsBetter: false),
                row(w, key: "bb_pct", label: "BB%", seasonLabel: "BB%", format: "%.1f%%", lowerIsBetter: true),
                row(w, key: "opp_hardhit_pct", label: "Opp Hard-Hit%", seasonLabel: "Hard-Hit%", format: "%.1f%%", lowerIsBetter: true),
                row(w, key: "opp_barrel_pct", label: "Opp Barrel%", seasonLabel: "Barrel%", format: "%.1f%%", lowerIsBetter: true),
                row(w, key: "opp_ev_avg", label: "Opp EV", seasonLabel: "EV", format: "%.1f mph", lowerIsBetter: true),
            ].compactMap { $0 }
        } else {
            return [
                row(w, key: "xwoba", label: "xwOBA", seasonLabel: "xwOBA", format: "%.3f", lowerIsBetter: false),
                row(w, key: "barrel_pct", label: "Barrel%", seasonLabel: "Barrel%", format: "%.1f%%", lowerIsBetter: false),
                row(w, key: "hardhit_pct", label: "Hard-Hit%", seasonLabel: "Hard-Hit%", format: "%.1f%%", lowerIsBetter: false),
                row(w, key: "ev_avg", label: "EV", seasonLabel: "EV", format: "%.1f mph", lowerIsBetter: false),
                row(w, key: "k_pct", label: "K%", seasonLabel: "K%", format: "%.1f%%", lowerIsBetter: true),
                row(w, key: "bb_pct", label: "BB%", seasonLabel: "BB%", format: "%.1f%%", lowerIsBetter: false),
            ].compactMap { $0 }
        }
    }

    private func row(_ w: RecentFormWindow, key: String, label: String, seasonLabel: String, format: String, lowerIsBetter: Bool) -> MetricRow? {
        guard let value = w.metrics[key] else { return nil }
        let display = formatValue(value, format: format)
        let (deltaStr, deltaColor) = deltaFromSeason(seasonLabel: seasonLabel, recent: value, lowerIsBetter: lowerIsBetter)
        return MetricRow(label: label, display: display, deltaDisplay: deltaStr, deltaColor: deltaColor)
    }

    private func formatValue(_ value: Double, format: String) -> String {
        if format.contains("%%") {
            // K%/BB%/Hard-Hit% etc come in as 0–100 already.
            return String(format: format, value)
        }
        return String(format: format, value)
    }

    /// Compare the window value against the player's full-season value (the
    /// number the user sees on the percentile card above). Direction-aware
    /// coloring — for "lower is better" metrics like K%, a drop is green.
    private func deltaFromSeason(seasonLabel: String, recent: Double, lowerIsBetter: Bool) -> (String?, Color) {
        guard let metric = player.metrics.first(where: { $0.label == seasonLabel }),
              let seasonRaw = DashboardViewModel.rawNumeric(metric.value) else {
            return (nil, SavantPalette.inkTertiary)
        }
        let diff = recent - seasonRaw
        guard abs(diff) > 0.001 else { return ("·", SavantPalette.inkTertiary) }
        let isImprovement = lowerIsBetter ? diff < 0 : diff > 0
        let color: Color = isImprovement ? .green : SavantPalette.savantRed
        let sign = diff > 0 ? "+" : ""
        // Match the value scale: percent metrics show 1 decimal; rate metrics 3.
        let formatted: String
        if seasonRaw >= 1 {
            formatted = String(format: "%@%.1f", sign, diff)
        } else {
            formatted = String(format: "%@%.3f", sign, diff)
        }
        return (formatted, color)
    }

    private var upgradeOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SavantPalette.savantRed)
            Text("Recent Form is a Pro feature")
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("See last 7 / 15 / 30 day splits for any player — spot hot streaks and slumps before anyone else.")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            Button(action: onUpgradeTap) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11))
                    Text("Unlock with Pro")
                        .font(SavantType.bodyBold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(SavantPalette.savantRed)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func load() async {
        guard let fetch = fetchGameLogs else { return }
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
