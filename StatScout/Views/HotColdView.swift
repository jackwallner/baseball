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
    @State private var side: TrendSide = .batting
    @State private var metric: TrendMetric = TrendMetric.batting[0]
    @State private var showingMetricPicker = false
    @State private var showingFollowSheet = false

    /// Deltas beyond this earn a flame or snowflake — but only in "Your
    /// players". On the ranked board every visible row is a large move by
    /// construction, so an icon there marks everything and therefore nothing;
    /// the arrow and its colour already carry direction. In a mixed personal
    /// list it's the one place the icon distinguishes anything.
    ///
    /// Scaled to the metric, since a 0.040 move in xwOBA and a 0.040 move in
    /// Whiff% are not remotely the same event.
    private var outlierDelta: Double {
        metric.decimals >= 3 ? 0.040 : 4.0
    }

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

    /// Followed players on the side currently being shown, paired with their
    /// window if they have one. A followed pitcher has no xwOBA of his own, so
    /// the side filter isn't cosmetic.
    ///
    /// Membership comes from the roster rather than from the recent-form table:
    /// a player on the IL has no rows in the window, and dropping him would
    /// silently shorten a list the user curated by hand.
    private var followedOnSide: [(player: Player, form: RecentForm?)] {
        let roster = viewModel.players(forSeason: viewModel.selectedSeason)
        return favorites.playerIds.compactMap { id in
            guard let player = roster.first(where: { $0.playerId == id }),
                  (player.playerType ?? "batter") == side.playerType else { return nil }
            return (player, viewModel.recentForm(for: id))
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
        .sheet(isPresented: $showingFollowSheet) {
            FollowPlayersSheet(viewModel: viewModel, side: side)
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
            yourPlayersSection
            section(
                title: showingCold ? "COLDEST IN THE LEAGUE" : "HOTTEST IN THE LEAGUE",
                forms: Array(ranked.prefix(50)),
                ranked: true
            )
        }
    }

    /// Always present, even empty. It's the only place in the app that explains
    /// what following a player buys you, and an empty section with a button is
    /// a better prompt than no section at all.
    private var yourPlayersSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "YOUR PLAYERS",
                trailing: AnyView(
                    Button {
                        showingFollowSheet = true
                    } label: {
                        Label(favorites.playerIds.isEmpty ? "Add" : "Edit", systemImage: "star")
                            .font(SavantType.micro)
                            .tracking(0.3)
                            .foregroundStyle(SavantPalette.savantRed)
                    }
                    .buttonStyle(.plain)
                )
            )

            if followedOnSide.isEmpty {
                VStack(spacing: 8) {
                    Text(followEmptyMessage)
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showingFollowSheet = true
                    } label: {
                        Text("Follow players")
                            .font(SavantType.smallBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .background(SavantPalette.savantRed)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(followedOnSide.enumerated()), id: \.element.player.playerId) { index, entry in
                    if let form = entry.form {
                        row(form: form, rank: nil, index: index)
                    } else {
                        noDataRow(player: entry.player, index: index)
                    }
                }
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

    private var followEmptyMessage: String {
        favorites.playerIds.isEmpty
            ? "Follow players and their last \(viewModel.recentWindow.rawValue) days show up here first."
            : "None of the players you follow are \(side == .batting ? "hitters" : "pitchers")."
    }

    /// A followed player with nothing in the window — injured, called up, or
    /// simply idle. Listed rather than dropped, so the section always matches
    /// the list the user built.
    private func noDataRow(player: Player, index: Int) -> some View {
        HStack(spacing: 10) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                    .lineLimit(1)
                Text("No games in the last \(viewModel.recentWindow.rawValue) days")
                    .font(SavantType.micro)
                    .tracking(0.2)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            Spacer(minLength: 0)
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
            NavigationLink(value: player) { Color.clear }
                .buttonStyle(.plain)
        }
        .contextMenu {
            Button {
                favorites.toggleFavorite(playerId: player.playerId)
            } label: {
                Label("Unfollow", systemImage: "star.slash")
            }
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
        let gain = metric.lowerIsBetter ? -delta : delta

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
                    if rank == nil, abs(delta) >= outlierDelta {
                        Image(systemName: gain > 0 ? "flame.fill" : "snowflake")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(gain > 0 ? SavantPalette.pctlHot : SavantPalette.pctlCold)
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
    private var teaserRows: [(name: String, team: String, initials: String, then: Double, now: Double, games: Int)] {
        let names = [
            ("Player One", "HOU", "PO"), ("Player Two", "ATL", "PT"),
            ("Player Three", "NYY", "PT"), ("Player Four", "LAD", "PF"),
            ("Player Five", "SEA", "PF"), ("Player Six", "KC", "PS"),
            ("Player Seven", "PHI", "PS"), ("Player Eight", "BAL", "PE"),
            ("Player Nine", "CHC", "PN"), ("Player Ten", "TEX", "PT"),
            ("Player Eleven", "MIL", "PE"), ("Player Twelve", "SD", "PT"),
        ]
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
}
