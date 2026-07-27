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
/// matches. The flame / snowflake accent is reserved for the direction control
/// rather than applied to every row — Savant uses no emoji at all, and marking
/// everything marks nothing. (Those are SF Symbols: 🔥/🧊 render as
/// missing-glyph boxes here, and `flame.fill` / `snowflake` are what
/// PercentileInfoSheet already uses for this exact meaning.)
///
/// Purely league-wide. The players you follow live on the Compare tab, which
/// is where they can actually be used; a personal list wedged above this board
/// made the tab answer two questions at once and buried the leaderboard the
/// subscription is sold on. Followed players are still marked with a star
/// here, and any row can be followed from its context menu.
struct HotColdView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @State private var favorites = FavoritesStore.shared
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingCold = false
    @State private var side: TrendSide = .batting
    @State private var metric: TrendMetric = TrendMetric.batting[0]
    @State private var showingMetricPicker = false

    private var forms: [RecentForm] {
        Array(viewModel.recentFormByWindow[viewModel.recentWindow.rawValue]?.values ?? [:].values)
    }

    /// How much better this player got. Falling numbers are the improvement for
    /// a chase rate or anything a pitcher gives up, so the board ranks on this
    /// rather than on the raw delta.
    private func improvement(_ form: RecentForm) -> Double? {
        guard let delta = form.delta[metric.key] else { return nil }
        return metric.lowerIsBetter ? -delta : delta
    }

    /// Ranked by improvement, hot first or cold first. Small samples are
    /// excluded outright — a 3-PA week produces enormous deltas that would
    /// crowd out every real riser.
    private var ranked: [RecentForm] {
        forms
            .filter { !$0.isSmallSample && $0.playerType == side.playerType && improvement($0) != nil }
            .sorted {
                let a = improvement($0) ?? 0
                let b = improvement($1) ?? 0
                return showingCold ? a < b : a > b
            }
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
        .onChange(of: side) { _, newSide in
            // Keys don't carry across sides, so land on that side's headline
            // metric rather than an empty board.
            metric = TrendMetric.list(for: newSide)[0]
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            // Side and stat on one row, then direction, then the window —
            // matching the team card's ordering so the two read the same.
            HStack(spacing: 8) {
                SavantSegmented(
                    segments: TrendSide.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $side
                )
                metricPicker
            }

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

    /// Thirteen metrics per side is far past what a segmented row can hold, so
    /// this is the app's other picker shape: the same vertical popover the
    /// season selector uses.
    private var metricPicker: some View {
        Button {
            showingMetricPicker = true
        } label: {
            SavantInlinePill(systemImage: "chart.bar.fill", title: metric.label)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingMetricPicker, arrowEdge: .top) {
            let list = TrendMetric.list(for: side)
            let standardStart = TrendMetric.standardStartIndex(for: side)
            VerticalOptionPopover(
                options: list.enumerated().map { index, m in
                    .init(
                        value: m.key,
                        label: m.label,
                        header: index == 0 ? "STATCAST" : (index == standardStart ? "STANDARD" : nil)
                    )
                },
                selected: metric.key,
                onSelect: { key in
                    if let match = list.first(where: { $0.key == key }) {
                        metric = match
                    }
                },
                width: 210
            )
        }
        .accessibilityLabel("Metric")
        .accessibilityValue(metric.label)
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
        let delta = form.delta[metric.key] ?? 0
        let now = form.metrics[metric.key]
        let then = form.priorMetrics[metric.key]

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
                    if favorites.isFavorite(playerId: form.playerId) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.yellow)
                    }
                }
                // THEN → NOW, the framing Savant's rolling leaderboard uses.
                if let then, let now {
                    Text("\(metric.format(then)) → \(metric.format(now)) · \(form.games)G")
                        .font(SavantType.micro)
                        .tracking(0.2)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TrendArrow(delta: delta, decimals: metric.decimals, lowerIsBetter: metric.lowerIsBetter)
                .frame(width: 56, alignment: .trailing)
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
        // Following straight off the board, so a name you spot here can be
        // pinned without a round trip through the player page.
        .contextMenu {
            Button {
                favorites.toggleFavorite(playerId: form.playerId)
            } label: {
                let following = favorites.isFavorite(playerId: form.playerId)
                Label(following ? "Unfollow" : "Follow", systemImage: following ? "star.slash" : "star")
            }
        }
    }

    /// Illustrative board for the blurred gate.
    ///
    /// Invented numbers, not real ones: a locked screen shouldn't spend the
    /// user's data on a fetch they can't read, and blur is not a security
    /// boundary — real values behind 8pt of blur are still real values.
    ///
    /// It does follow the pickers, though. A preview frozen on hitters' xwOBA
    /// while the header says "Pitching · Cooling off · K%" makes the controls
    /// look broken, which is the opposite of what a teaser is for. The shape is
    /// generated from the selected metric's own scale and direction.
    private var teaserBoard: some View {
        let ranked = teaserRows
        return VStack(spacing: 0) {
            SavantSectionBar(title: showingCold ? "COLDEST IN THE LEAGUE" : "HOTTEST IN THE LEAGUE")
            ForEach(Array(ranked.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(SavantType.statSmall)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(width: 26, alignment: .leading)
                    PlayerHeadshot(team: row.team, initials: row.initials, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        Text("\(metric.format(row.then)) → \(metric.format(row.now)) · \(row.games)G")
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TrendArrow(
                        delta: row.now - row.then,
                        decimals: metric.decimals,
                        lowerIsBetter: metric.lowerIsBetter
                    )
                    .frame(width: 56, alignment: .trailing)
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

    /// Twelve plausible rows for the current metric. Enough to fill the
    /// viewport behind the gate — six left a dead grey void under the unlock
    /// panel, which read as a broken screen rather than as a paywall.
    ///
    /// The faces are real players from the selected side's roster (season data
    /// is free, so nothing is being given away), picked and ordered by a seed
    /// built from the metric, the direction and the window. That's what makes
    /// the board visibly redraw when a picker moves: with a fixed cast the
    /// twelve team colours stayed in exactly the same order no matter what the
    /// controls said, which gives the game away immediately.
    private var teaserRows: [(name: String, team: String, initials: String, then: Double, now: Double, games: Int)] {
        let seedSuffix = "\(metric.key)-\(showingCold)-\(viewModel.recentWindow.rawValue)"
        let roster = viewModel.players(forSeason: viewModel.selectedSeason)
            .filter { ($0.playerType ?? "batter") == side.playerType }
        let names: [(String, String, String)]
        if roster.count >= 12 {
            names = roster
                .map { ($0, Self.stableSeed("\($0.playerId)-\(seedSuffix)")) }
                .sorted { $0.1 < $1.1 }
                .prefix(12)
                .map { ($0.0.name, $0.0.team, $0.0.initials) }
        } else {
            // Pre-load, or a season with no roster yet.
            let placeholders = [
                ("Player One", "HOU", "PO"), ("Player Two", "ATL", "PT"),
                ("Player Three", "NYY", "PT"), ("Player Four", "LAD", "PF"),
                ("Player Five", "SEA", "PF"), ("Player Six", "KC", "PS"),
                ("Player Seven", "PHI", "PS"), ("Player Eight", "BAL", "PE"),
                ("Player Nine", "CHC", "PN"), ("Player Ten", "TEX", "PT"),
                ("Player Eleven", "MIL", "PE"), ("Player Twelve", "SD", "PT"),
            ]
            names = placeholders
                .map { ($0, Self.stableSeed("\($0.0)-\(seedSuffix)")) }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
        }
        // Centre and spread the invented values on the metric's own scale, so
        // a rate stat reads .250→.400 and a percent reads 20%→32%.
        let base: Double = metric.decimals >= 3 ? 0.290 : (metric.unit == " mph" ? 90 : 24)
        let swing: Double = metric.decimals >= 3 ? 0.130 : (metric.unit == " mph" ? 3.5 : 9)
        // Cooling off inverts the movement, and a lower-is-better metric
        // inverts it again — heating up on Chase% means the number falls.
        let improving = !showingCold
        let sign: Double = (improving != metric.lowerIsBetter) ? 1 : -1

        return names.enumerated().map { index, who in
            let decay = 1.0 - Double(index) * 0.055
            let move = swing * decay
            let then = base - sign * move / 2
            return (who.0, who.1, who.2, then, then + sign * move, 14 - index % 5)
        }
    }

    /// Deterministic across launches, unlike `hashValue`, so the preview doesn't
    /// reshuffle itself on a redraw.
    private static func stableSeed(_ text: String) -> Int {
        abs(text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
    }
}
