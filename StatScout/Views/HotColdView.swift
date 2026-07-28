import SwiftUI

/// League-wide recent form, ranked by change rather than by level.
///
/// Modelled on Baseball Savant's rolling leaderboard, which reports THEN / NOW
/// / delta instead of a bare current-window number, the delta is the story. A
/// .380 xwOBA is interesting; a .380 that was .250 a fortnight ago is a player
/// you want to know about right now, and that's the thing season totals can't
/// tell you.
///
/// Colour is Savant's red-to-blue percentile gradient, which the app already
/// matches. The flame / snowflake accent is reserved for the direction control
/// rather than applied to every row, Savant uses no emoji at all, and marking
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
    @State private var showingCold = false
    @State private var side: TrendSide = .batting
    @State private var statMode: TrendStatMode = .advanced
    @State private var metric: TrendMetric = TrendMetric.batting[0]

    /// The metrics the picker offers, narrowed by the Advanced / Standard
    /// switch. Every other board in the app splits its stats this way (the
    /// player page, the team page, the Stats tab), and Trends was the one place
    /// where the two vocabularies were mixed into a single long menu.
    private var metricOptions: [TrendMetric] {
        statMode == .advanced ? TrendMetric.statcast(for: side) : TrendMetric.standard(for: side)
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
    /// excluded outright, a 3-PA week produces enormous deltas that would
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

    /// Free users get the header and a full-height locked board; Pro users get
    /// a scrolling one.
    ///
    /// The locked board deliberately does *not* scroll. It used to sit in the
    /// same `ScrollView` as the Pro board, which meant its height was whatever
    /// twelve invented rows happened to add up to, short of the viewport on a
    /// big phone, so the card stopped mid-screen with canvas grey under it and
    /// the unlock panel floating in the middle of nothing. There is also
    /// nothing below the fold to scroll *to* when the rows are a teaser. Laying
    /// it out as a fixed page that fills the space is both simpler and what it
    /// always should have looked like.
    var body: some View {
        VStack(spacing: 0) {
            header

            if store.isPro {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        proContent
                        Color.clear.frame(height: 88)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                lockedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SavantPalette.canvas)
        // Keyed on entitlement as well as the window. `isPro` starts false and
        // only flips once RevenueCat answers, which on a real device is often
        // after this view is already on screen, with the window alone as the
        // id, that first task had already returned at the guard and nothing
        // ever re-ran it. The board then sat empty forever: not loading, no
        // error, just a bare header. Switching windows was the only way to get
        // data, which is exactly how it looked in TestFlight.
        //
        // Free users load it too now: the top row of the locked board is the
        // real league leader, and a fabricated one would be a lie in the one
        // place we're asking to be trusted. It's a single request against the
        // pre-aggregated rollup table, the same one Pro reads.
        .task(id: "\(viewModel.recentWindow.rawValue)-\(store.isPro)") {
            await viewModel.loadRecentFormIfNeeded()
        }
        .onChange(of: side) { _, _ in
            // Keys don't carry across sides, so land on that side's headline
            // metric rather than an empty board.
            metric = metricOptions[0]
        }
        .onChange(of: statMode) { _, _ in
            metric = metricOptions[0]
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            // Which side of the ball, and which vocabulary. Both narrow the
            // stat list below them, so they sit above it.
            SavantPickerRow(spacing: 8) {
                SavantSegmented(
                    segments: TrendSide.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $side
                )
                .segmentCount(TrendSide.allCases.count)

                SavantSegmented(
                    segments: TrendStatMode.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $statMode
                )
                .segmentCount(TrendStatMode.allCases.count)
            }

            HStack(spacing: 8) {
                metricPicker
                Spacer(minLength: 0)
                if let asOf = viewModel.recentFormAsOf {
                    Text("Through \(asOf.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
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
                segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
                selection: $viewModel.recentWindow
            )

            // The window is calendar days; the per-row "· 12G" is how many
            // games the player actually appeared in inside it. Two numbers of
            // different kinds sat next to each other with nothing saying which
            // was which, so the picker read as a game count.
            Text("Calendar days, not games — G is games played in the window.")
                .font(SavantType.micro)
                .tracking(0.2)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    /// Thirteen Statcast metrics per side is far past what a segmented row can
    /// hold, so this is the app's other picker shape: the same plain `Menu` the
    /// season selector and every sort control use. The Advanced / Standard
    /// switch above decides which family it lists.
    private var metricPicker: some View {
        Menu {
            metricButtons(metricOptions)
        } label: {
            SavantInlinePill(systemImage: "chart.bar.fill", title: metric.label)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Metric")
        .accessibilityValue(metric.label)
    }

    private func metricButtons(_ list: [TrendMetric]) -> some View {
        ForEach(list) { option in
            Button {
                metric = option
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if option.key == metric.key {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }
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
        } else if ranked.isEmpty {
            // A metric the pipeline hasn't produced a prior window for yet
            // ranks nobody, and a bare header under a full set of controls
            // reads as a broken screen. Name the reason and point at the
            // metrics that do have movement.
            ContentUnavailableView {
                Label("No movement to rank yet", systemImage: "chart.line.flattrend.xyaxis")
            } description: {
                Text("\(metric.label) doesn't have enough of a prior window to compare against. Try another stat or a longer window.")
            }
            .padding(.vertical, 32)
        } else {
            section(title: boardTitle, forms: Array(ranked.prefix(50)), ranked: true)
        }
    }

    /// Free users get the real number one, then the wall.
    ///
    /// A gate that shows nobody is easy to walk away from. Showing the actual
    /// hottest hitter in the league, his name, his THEN → NOW, tappable
    /// through to his page, makes the board demonstrably real, and makes the
    /// blurred ranks below it a thing you can't see rather than a thing that
    /// might not exist. Everything under row one stays invented: blur is not a
    /// security boundary, so the rows behind it were never real numbers.
    private var lockedContent: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: boardTitle)

            leaderRow

            // The rows are drawn as an overlay on an empty flexible spacer, not
            // stacked directly. A VStack of eighteen rows has an ideal height
            // of ~800pt and `frame(maxHeight:)` doesn't shrink a child below
            // its ideal, so laying them out inline made the card taller than
            // the screen and shoved the whole page up, taking the pickers off
            // the top and the unlock panel off the bottom. `Color.clear` has no
            // ideal height of its own, so it takes exactly the space left over;
            // the overlay fills it and the excess is clipped.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(Array(teaserRows.dropFirst().enumerated()), id: \.offset) { index, teaser in
                            teaserRow(teaser, index: index + 1)
                        }
                    }
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    BlurGateUnlock(
                        headline: "See the full board: every hitter and pitcher ranked by how far they've moved",
                        trigger: .recentForm
                    )
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
        // Sits just clear of the floating tab bar. Measured from the safe area,
        // not the screen edge, so this is the pill's height above the inset
        // plus a hair, the page doesn't scroll, so unlike every other screen
        // there's nothing to gain from running underneath it.
        .padding(.bottom, 46)
    }

    /// Row one of the locked board: the genuine leader once the rollup lands,
    /// and a placeholder of the same height until then so the card doesn't
    /// resize under the gate as data arrives.
    @ViewBuilder
    private var leaderRow: some View {
        if let leader = ranked.first {
            row(form: leader, rank: 1, index: 0)
        } else {
            HStack(spacing: 10) {
                if viewModel.isRecentFormLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Text(viewModel.isRecentFormLoading ? "Loading the board…" : "No movement to rank yet")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SavantGeo.padInline)
            .frame(height: SavantGeo.rowHeight)
            .background(SavantPalette.surface)
            .overlay(
                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                alignment: .bottom
            )
        }
    }

    private var boardTitle: String {
        showingCold ? "COLDEST IN THE LEAGUE" : "HOTTEST IN THE LEAGUE"
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
                initials: player?.initials ?? "-",
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

    /// One row of the invented board behind the gate. Same geometry as the real
    /// `row`, so the blur reads as the board continuing rather than as a
    /// different component.
    private func teaserRow(_ teaser: TeaserRow, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(SavantType.statSmall)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 26, alignment: .leading)
            PlayerHeadshot(team: teaser.team, initials: teaser.initials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(teaser.name)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Text("\(metric.format(teaser.then)) → \(metric.format(teaser.now)) · \(teaser.games)G")
                    .font(SavantType.micro)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TrendArrow(
                delta: teaser.now - teaser.then,
                decimals: metric.decimals,
                lowerIsBetter: metric.lowerIsBetter
            )
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, SavantGeo.padInline)
        .frame(height: SavantGeo.rowHeight)
        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
    }

    struct TeaserRow {
        let name: String
        let team: String
        let initials: String
        let then: Double
        let now: Double
        let games: Int
    }

    /// Enough plausible rows to overflow the tallest phone behind the gate,
    /// the container clips them, so too many costs nothing and too few leaves
    /// the dead grey void that made this screen read as broken.
    ///
    /// The faces are real players from the selected side's roster (season data
    /// is free, so nothing is being given away), picked and ordered by a seed
    /// built from the metric, the direction and the window. That's what makes
    /// the board visibly redraw when a picker moves: with a fixed cast the
    /// twelve team colours stayed in exactly the same order no matter what the
    /// controls said, which gives the game away immediately.
    private var teaserRows: [TeaserRow] {
        let count = 18
        let seedSuffix = "\(metric.key)-\(showingCold)-\(viewModel.recentWindow.rawValue)"
        let roster = viewModel.players(forSeason: viewModel.selectedSeason)
            .filter { ($0.playerType ?? "batter") == side.playerType }
        let names: [(String, String, String)]
        if roster.count >= count {
            names = roster
                .map { ($0, Self.stableSeed("\($0.playerId)-\(seedSuffix)")) }
                .sorted { $0.1 < $1.1 }
                .prefix(count)
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
                ("Player Thirteen", "TOR", "PT"), ("Player Fourteen", "ARI", "PF"),
                ("Player Fifteen", "MIN", "PF"), ("Player Sixteen", "CLE", "PS"),
                ("Player Seventeen", "STL", "PS"), ("Player Eighteen", "DET", "PE"),
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
        // inverts it again, heating up on Chase% means the number falls.
        let improving = !showingCold
        let sign: Double = (improving != metric.lowerIsBetter) ? 1 : -1

        return names.enumerated().map { index, who in
            let decay = max(0.15, 1.0 - Double(index) * 0.045)
            let move = swing * decay
            let then = base - sign * move / 2
            return TeaserRow(
                name: who.0,
                team: who.1,
                initials: who.2,
                then: then,
                now: then + sign * move,
                games: 14 - index % 5
            )
        }
    }

    /// Deterministic across launches, unlike `hashValue`, so the preview doesn't
    /// reshuffle itself on a redraw.
    private static func stableSeed(_ text: String) -> Int {
        abs(text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
    }
}
