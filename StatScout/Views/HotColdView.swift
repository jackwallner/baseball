import SwiftUI

/// League-wide recent form, ranked by change rather than by level.
///
/// Modelled on Baseball Savant's rolling leaderboard, which reports THEN / NOW
/// / delta instead of a bare current-window number — the delta is the story. A
/// .380 xwOBA is interesting; a .380 that was .250 a fortnight ago is a player
/// you want to know about right now, and that's the thing season totals can't
/// tell you.
///
/// Colour is Savant's red-to-blue percentile gradient, which the app already
/// matches. The flame / snowflake accent is reserved for genuine outliers
/// rather than applied to every row — Savant uses no emoji at all, and marking
/// everything marks nothing.
///
/// Those are SF Symbols, not emoji: 🔥/🧊 rendered as missing-glyph boxes here,
/// and `flame.fill` / `snowflake` are what PercentileInfoSheet already uses for
/// this exact hot/cold meaning, so they tint with the palette and match the
/// rest of the app.
struct HotColdView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @State private var favorites = FavoritesStore.shared
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingCold = false

    /// Deltas beyond this earn a flame or snowflake — but only in "Your
    /// players". On the ranked board every visible row is a large move by
    /// construction, so an icon there marks everything and therefore nothing;
    /// the arrow and its colour already carry direction. In a mixed personal
    /// list it's the one place the icon distinguishes anything.
    private static let outlierDelta = 0.040

    private var metricKey: String { "xwoba" }

    private var forms: [RecentForm] {
        Array(viewModel.recentFormByWindow[viewModel.recentWindow.rawValue]?.values ?? [:].values)
    }

    /// Ranked by delta, hot first or cold first. Small samples are excluded
    /// outright here — a 3-PA week produces enormous deltas that would crowd
    /// out every real riser.
    private var ranked: [RecentForm] {
        let usable = forms.filter {
            !$0.isSmallSample
                && $0.delta[metricKey] != nil
                && $0.playerType != "pitcher"
        }
        return usable.sorted {
            let a = $0.delta[metricKey] ?? 0
            let b = $1.delta[metricKey] ?? 0
            return showingCold ? a < b : a > b
        }
    }

    private var favoriteForms: [RecentForm] {
        favorites.playerIds.compactMap { viewModel.recentForm(for: $0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header

                if store.isPro {
                    proContent
                } else {
                    lockedContent
                }

                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas)
        .task(id: viewModel.recentWindow.rawValue) {
            guard store.isPro else { return }
            await viewModel.loadRecentFormIfNeeded()
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            // Same control as every other inline picker; only the selected fill
            // differs, because here the choice itself encodes hot vs cold.
            SavantSegmented(
                segments: [
                    .init(value: false, label: "Heating up", systemImage: "flame.fill"),
                    .init(value: true, label: "Cooling off", systemImage: "snowflake"),
                ],
                selection: $showingCold,
                selectedFill: { $0 ? SavantPalette.pctlCold : SavantPalette.pctlHot }
            )

            SavantSegmented(
                segments: RecentWindow.allCases.map { .init(value: $0, label: $0.label) },
                selection: $viewModel.recentWindow
            )

            if let asOf = viewModel.recentFormAsOf {
                Text("Through \(asOf.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var proContent: some View {
        if viewModel.isRecentFormLoading && forms.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let error = viewModel.recentFormError, forms.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load recent form", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
            .padding(.vertical, 32)
        } else {
            if !favoriteForms.isEmpty {
                section(title: "YOUR PLAYERS", forms: favoriteForms, ranked: false)
            }
            section(
                title: showingCold ? "COLDEST IN THE LEAGUE" : "HOTTEST IN THE LEAGUE",
                forms: Array(ranked.prefix(50)),
                ranked: true
            )
        }
    }

    /// Free users get the real header and a blurred board beneath it. The point
    /// is to show the shape of what's behind the wall — names, movement, a
    /// ranking — rather than a padlock that communicates nothing.
    private var lockedContent: some View {
        ZStack(alignment: .bottom) {
            teaserBoard
                .blur(radius: 8)
                .disabled(true)
                .allowsHitTesting(false)
            BlurGateUnlock(
                headline: "See who's heating up and cooling off across the league",
                cta: store.paywallBlurCTA,
                subtext: store.paywallBlurSubtext,
                action: { paywallTrigger = .recentForm }
            )
        }
    }

    private func section(title: String, forms: [RecentForm], ranked: Bool) -> some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: title)
            ForEach(Array(forms.enumerated()), id: \.element.id) { index, form in
                row(form: form, rank: ranked ? index + 1 : nil, index: index)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func row(form: RecentForm, rank: Int?, index: Int) -> some View {
        let player = viewModel.players(forSeason: form.season).first { $0.playerId == form.playerId }
        let delta = form.delta[metricKey] ?? 0
        let now = form.metrics[metricKey]
        let then = form.priorMetrics[metricKey]

        HStack(spacing: 10) {
            if let rank {
                Text("\(rank)")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .frame(width: 26, alignment: .leading)
                    .monospacedDigit()
            }

            PlayerHeadshot(
                team: player?.team ?? form.team ?? "",
                initials: player?.initials ?? "—",
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(player?.name ?? "Player \(form.playerId)")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                        .lineLimit(1)
                    if rank == nil, abs(delta) >= Self.outlierDelta {
                        Image(systemName: delta > 0 ? "flame.fill" : "snowflake")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(delta > 0 ? SavantPalette.pctlHot : SavantPalette.pctlCold)
                    }
                }
                // THEN → NOW, the framing Savant's rolling leaderboard uses.
                if let then, let now {
                    Text("\(fmt(then)) → \(fmt(now)) xwOBA · \(form.games)G")
                        .font(SavantType.micro)
                        .tracking(0.2)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TrendArrow(delta: delta, decimals: 3)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, SavantGeo.padInline)
        .frame(height: SavantGeo.rowHeight)
        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .overlay {
            if let player {
                NavigationLink(value: player) { Color.clear }
                    .buttonStyle(.plain)
            }
        }
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.3f", value).replacingOccurrences(of: "0.", with: ".")
    }

    /// Illustrative board for the blurred gate. Static on purpose: a locked
    /// screen shouldn't spend the user's data on a fetch they can't read.
    private var teaserBoard: some View {
        // Enough rows to fill the viewport behind the gate. Six left a dead
        // grey void under the unlock panel, which read as a broken screen
        // rather than a paywall.
        let rows: [(name: String, team: String, initials: String, then: Double, now: Double, games: Int)] = [
            ("Riser One",    "HOU", "RO", 0.248, 0.421, 13),
            ("Riser Two",    "ATL", "RT", 0.263, 0.418, 12),
            ("Riser Three",  "NYY", "RH", 0.291, 0.402, 14),
            ("Riser Four",   "LAD", "RF", 0.277, 0.381, 11),
            ("Riser Five",   "SEA", "RV", 0.302, 0.375, 13),
            ("Riser Six",    "KC",  "RS", 0.288, 0.361, 12),
            ("Riser Seven",  "PHI", "RS", 0.271, 0.354, 10),
            ("Riser Eight",  "BAL", "RE", 0.264, 0.347, 12),
            ("Riser Nine",   "CHC", "RN", 0.259, 0.341, 11),
            ("Riser Ten",    "TEX", "RT", 0.283, 0.338, 13),
            ("Riser Eleven", "MIL", "RE", 0.276, 0.332, 12),
            ("Riser Twelve", "SD",  "RT", 0.269, 0.327, 14),
        ]
        return VStack(spacing: 0) {
            SavantSectionBar(title: "HOTTEST IN THE LEAGUE")
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(SavantType.statSmall)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(width: 26, alignment: .leading)
                    PlayerHeadshot(team: row.team, initials: row.initials, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(row.name)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                        }
                        Text("\(fmt(row.then)) → \(fmt(row.now)) xwOBA · \(row.games)G")
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TrendArrow(delta: row.now - row.then, decimals: 3)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.horizontal, SavantGeo.padInline)
                .frame(height: SavantGeo.rowHeight)
                .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}
