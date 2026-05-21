import SwiftUI

/// Team-wide Recent Form (last 7 / 15 / 30 day windows) — aggregates every
/// rostered batter and pitcher's per-game logs into team-level rate stats.
/// Pro-gated with the same blur + CTA pattern as the player-level card so
/// the experience matches across surfaces.
struct TeamFormCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    let fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])?
    let onUpgradeTap: () -> Void

    @State private var logs: [PlayerGameLog] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var windowDays: Int = 15
    @State private var side: Side = .batting

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
        VStack(spacing: 12) {
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
            Text(row.display)
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
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
    }

    private func metricRows(window w: RecentFormWindow) -> [MetricRow] {
        if side == .pitching {
            return [
                cell(w, key: "opp_xwoba", label: "Opp xwOBA", format: "%.3f"),
                cell(w, key: "k_pct", label: "K%", format: "%.1f%%"),
                cell(w, key: "bb_pct", label: "BB%", format: "%.1f%%"),
                cell(w, key: "opp_hardhit_pct", label: "Opp Hard-Hit%", format: "%.1f%%"),
                cell(w, key: "opp_barrel_pct", label: "Opp Barrel%", format: "%.1f%%"),
                cell(w, key: "opp_ev_avg", label: "Opp EV", format: "%.1f mph"),
            ].compactMap { $0 }
        } else {
            return [
                cell(w, key: "xwoba", label: "xwOBA", format: "%.3f"),
                cell(w, key: "barrel_pct", label: "Barrel%", format: "%.1f%%"),
                cell(w, key: "hardhit_pct", label: "Hard-Hit%", format: "%.1f%%"),
                cell(w, key: "ev_avg", label: "EV", format: "%.1f mph"),
                cell(w, key: "k_pct", label: "K%", format: "%.1f%%"),
                cell(w, key: "bb_pct", label: "BB%", format: "%.1f%%"),
            ].compactMap { $0 }
        }
    }

    private func cell(_ w: RecentFormWindow, key: String, label: String, format: String) -> MetricRow? {
        guard let v = w.metrics[key] else { return nil }
        return MetricRow(label: label, display: String(format: format, v))
    }

    private var upgradeOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SavantPalette.savantRed)
            Text("Team Recent Form is a Pro feature")
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("See how every team is hitting and pitching over the last 7 / 15 / 30 days — spot hot rosters and slumping staffs.")
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
