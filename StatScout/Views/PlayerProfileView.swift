import SwiftUI

struct PlayerProfileView: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let history: [Player]
    var allPlayers: [Player] = []
    var isHistoricalLoading = false
    var hasLoadedHistorical = true
    var historicalLoadingMessage = "Loading past seasons…"
    var historicalLoadingProgress = 0.12
    var loadHistorical: (() async -> Void)?
    var fetchGameLogs: ((Int, Int) async throws -> [PlayerGameLog])?
    /// Pre-aggregated rolling window for this player, when one is loaded.
    var recentFormLookup: ((Int, RecentWindow) -> RecentForm?)?
    var loadRecentForm: ((RecentWindow) async -> Void)?
    /// Lets a comparison pushed from here swap either side out in place.
    var comparisonCatalog: ComparisonCatalog?
    @State private var showPercentileInfo = false
    @State private var selectedTab: PlayerStatTab = .statcast
    @State private var selectedPercentileSeason: Int? = nil
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingPlayerPicker = false
    @State private var comparisonRoute: ComparisonRoute?
    // Contextual trial pitches (compare, recent form, year compare, first-open)
    // all route through the low-friction TrialPitchSheet, its CTA starts the
    // yearly trial directly. PaywallView stays for the deliberate upsell card.
    @State private var trialPitchTrigger: PaywallTrigger?
    @State private var formDisplayMode: FormDisplayMode = .season
    @State private var recentWindowDays: Int = 15
    @State private var recentLogs: [PlayerGameLog] = []
    @State private var recentLoading = false
    @State private var recentLoadError: String?
    @State private var recentCurves: LeaguePercentileCurves?
    @State private var standardMode: FormDisplayMode = .season
    @State private var standardWindow: RecentWindow = .fortnight
    @State private var favorites = FavoritesStore.shared

    private let profileOpenCountKey = "profileOpenCount"

    enum FormDisplayMode: String, CaseIterable {
        case season = "Season"
        case recent = "Recent"
        case both = "Both"
    }

    enum PlayerStatTab: String, CaseIterable {
        case statcast = "Advanced"
        case standard = "Standard"
        case yearCompare = "Year Compare"
    }

    /// Every season the dataset covers, not just the ones already loaded for
    /// this player. A locked year has to be visible to be worth unlocking.
    private var availablePercentileSeasons: [Int] {
        Array(StatScoutSeason.earliest...StatScoutSeason.current).reversed()
    }

    private var activeSeason: Int? {
        selectedPercentileSeason ?? player.season
    }

    private var displayedPlayer: Player {
        guard let season = activeSeason else { return player }
        return history.first { $0.season == season } ?? player
    }

    private var seasonLabel: String {
        activeSeason.map(String.init) ?? "-"
    }

    private var groupedMetrics: [(category: MetricCategory, metrics: [Metric])] {
        let grouped = Dictionary(grouping: displayedPlayer.metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let m = grouped[cat], !m.isEmpty else { return nil }
            return (category: cat, metrics: m.sorted { cat.sortMetrics($0.label, $1.label) })
        }
    }

    /// Players eligible for comparison: same player type (hitter↔hitter, pitcher↔pitcher),
    /// sorted by xwOBA proximity to the current player so the closest match is first.
    private var comparablePlayers: [Player] {
        let myType = player.playerType
        let pool = allPlayers.filter { other in
            guard other.playerId != player.playerId else { return false }
            switch myType {
            case "pitcher": return other.playerType == "pitcher"
            case "batter", "hitter": return other.playerType != "pitcher"
            case "two_way": return true
            default: return other.playerType == myType
            }
        }
        let myXwoba = player.metrics.first { $0.label == "xwOBA" }?.percentile
        guard let mine = myXwoba else { return pool }
        return pool.sorted { a, b in
            let ax = a.metrics.first { $0.label == "xwOBA" }?.percentile
            let bx = b.metrics.first { $0.label == "xwOBA" }?.percentile
            switch (ax, bx) {
            case let (.some(av), .some(bv)):
                return abs(av - mine) < abs(bv - mine)
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.name < b.name
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlayerIdentityStrip(player: player)

                tabSelector
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                switch selectedTab {
                case .statcast:
                    statcastContent
                case .standard:
                    standardContent
                case .yearCompare:
                    yearCompareContent
                }

                // Lets the last metric row clear the floating tab bar, the
                // profile was missing the spacer Dashboard and TeamView have,
                // so its bottom row sat under the glass.
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        // First-tap activation: profile renders immediately (no full-screen
        // paywall blocking it), and a native half-sheet TrialPitchSheet
        // floats on top with a "Maybe later" dismiss. PaywallGate caps this
        // at 2 per session so repeat taps don't re-prompt. The old full-page
        // .activation PaywallView was removed for being too intrusive, this
        // is the Vitals-style soft pitch that replaced it.
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Bare glyphs on the navy bar; the iOS 26 Liquid Glass container
            // wraps them in a pale capsule that reads as a stray button.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { compareButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                ToolbarItem(placement: .topBarTrailing) { compareButton }
            }
        }
        .sheet(isPresented: $showPercentileInfo) {
            PercentileInfoSheet()
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerSheet(players: comparablePlayers) { selected in
                comparisonRoute = ComparisonRoute(playerA: player, playerB: selected)
            }
        }
        // Sizing and the drag indicator belong to the sheet itself now, so every
        // entry point in the app presents an identically-shaped pitch.
        .sheet(item: $trialPitchTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(
                playerA: route.playerA,
                playerB: route.playerB,
                catalog: comparisonCatalog
            )
        }
        .onAppear {
            // Defer the first-impression pitch: a user verifying one stat from a
            // group chat shouldn't hit a subscription story before scrolling a
            // single row. Show it from the *second* profile open onward (Pro-only
            // controls, Recent Form, past seasons, Compare, still pitch on tap).
            let opens = UserDefaults.standard.integer(forKey: profileOpenCountKey) + 1
            UserDefaults.standard.set(opens, forKey: profileOpenCountKey)
            if !store.isPro, opens >= 2, PaywallGate.shared.shouldPresent(.playerScouting) {
                trialPitchTrigger = .playerScouting
            }
            // Engaged browsing, but only counted once the user has come back on
            // separate days, see ReviewPromptTracker.minimumDistinctUseDays.
            // Opening three profiles in one sitting used to be enough, which is
            // browsing depth, not satisfaction.
            if opens >= 3 {
                ReviewPromptTracker.recordPositiveMoment()
            }
        }
    }

    /// Following a player is free. It's the signal the Hot/Cold tab and the
    /// review funnel read from, so gating it would suppress the thing we most
    /// want people to do.
    private var favoriteButton: some View {
        let isFavorite = favorites.isFavorite(playerId: player.playerId)
        return Button {
            favorites.toggleFavorite(playerId: player.playerId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : .white)
        }
        .accessibilityLabel(isFavorite ? "Unfollow \(player.name)" : "Follow \(player.name)")
    }

    private var compareButton: some View {
        Button {
            if store.isPro {
                showingPlayerPicker = true
            } else {
                trialPitchTrigger = .playerComparison
            }
        } label: {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Compare with another player")
    }

    private var tabSelector: some View {
        HStack(spacing: 8) {
            statcastTabButton
            standardTabButton
            yearCompareTabButton
        }
    }

    private var statcastTabButton: some View {
        let isSelected = selectedTab == .statcast
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .statcast
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.statcast.rawValue)
                .font(SavantType.bodyBold)
                .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var standardTabButton: some View {
        let isSelected = selectedTab == .standard
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .standard
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.standard.rawValue)
                .font(SavantType.bodyBold)
                .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var yearCompareTabButton: some View {
        let isSelected = selectedTab == .yearCompare
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .yearCompare
            }
            if store.isPro, !hasLoadedHistorical, !isHistoricalLoading {
                Task { await loadHistorical?() }
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.yearCompare.rawValue)
                .font(SavantType.bodyBold)
                .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var statcastContent: some View {
        VStack(spacing: 12) {
            percentileRankingsCard

            if !store.isPro {
                RecentFormCard(
                    player: player,
                    season: activeSeason ?? player.season ?? Calendar.current.component(.year, from: .now),
                    leaguePlayers: allPlayers,
                    fetchGameLogs: fetchGameLogs
                )
            }

            if !store.isPro {
                proUpsellCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var proUpsellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)
                Text("StatScout+")
                    .font(SavantType.smallBold)
                    .tracking(0.4)
                    .foregroundStyle(SavantPalette.ink)
            }

            Text("Get the full scouting picture on \(player.name).")
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                proPerk("chart.line.uptrend.xyaxis", "Year-over-year trends across every metric")
                proPerk("person.2.fill", "Head-to-head comparisons vs any player")
                proPerk("calendar.badge.clock", "Every past season, not just this one")
                proPerk("arrow.down.circle.fill", "Saved offline, works on the road")
            }

            // Buys in place. This card's CTA used to open the plan picker,
            // which meant a user who tapped "Start 7-day free trial" was asked
            // to choose a plan and press a second button before Apple's sheet
            // appeared.
            PlusDirectCTA(trigger: store.defaultUpgradeTrigger)
        }
        .padding(16)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func proPerk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SavantPalette.savantRed)
                .frame(width: 16)
            Text(text)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var standardContent: some View {
        VStack(spacing: 12) {
            standardStatsGridCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var yearCompareContent: some View {
        if store.isPro {
            if isHistoricalLoading {
                historicalLoadingCard
            } else if !hasLoadedHistorical, loadHistorical != nil {
                loadHistoricalCard
            } else if history.count < 2 {
                ContentUnavailableView {
                    Label("Not enough history", systemImage: "calendar.badge.clock")
                } description: {
                    Text("\(player.name) doesn't have multiple seasons of data to compare.")
                }
                .padding(.vertical, 48)
            } else {
                YearComparisonView(history: history)
            }
        } else {
            YearComparePreview(playerName: player.name)
        }
    }

    private var historicalLoadingCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: min(max(historicalLoadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(SavantPalette.savantRed)
            Text(historicalLoadingMessage)
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("\(Int(min(max(historicalLoadingProgress, 0), 1) * 100))%")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var loadHistoricalCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(SavantPalette.savantRed)
            Text("Load past seasons")
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("Year Compare loads historical data only when you need it.")
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Load History") {
                Task { await loadHistorical?() }
            }
            .buttonStyle(.borderedProminent)
            .tint(SavantPalette.savantRed)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Cards

    private var seasonMenu: some View {
        SeasonMenu(
            seasons: availablePercentileSeasons,
            selected: activeSeason ?? StatScoutSeason.current,
            isLocked: { $0 != StatScoutSeason.free && !store.isPro },
            onSelect: { season in
                if season != StatScoutSeason.free && !store.isPro {
                    // Explicit tap on a locked season, always answer it.
                    // PaywallGate only caps automatic pop-ups.
                    trialPitchTrigger = .lockedSeason(season)
                } else {
                    selectedPercentileSeason = season
                    if season < StatScoutSeason.current, !hasLoadedHistorical {
                        Task { await loadHistorical?() }
                    }
                }
            }
        ) {
            HStack(spacing: 4) {
                Text(seasonLabel)
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .fixedSize()
        }
        .accessibilityValue(seasonLabel)
    }

    /// Season / Recent / Both. Shown to everyone: a free user needs to see that
    /// Recent exists before there's anything to want. Locked segments carry a
    /// crown and pitch on tap instead of switching.
    private var formModePicker: some View {
        SavantSegmented(
            segments: FormDisplayMode.allCases.map {
                .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 != .season)
            },
            selection: $formDisplayMode,
            onLockedTap: { _ in trialPitchTrigger = .recentForm }
        )
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.vertical, 10)
        .background(SavantPalette.surfaceAlt)
    }

    private var percentileRankingsCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "ADVANCED STATS",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        seasonMenu
                        Button(action: { showPercentileInfo = true }) {
                            Text("ⓘ")
                                .font(SavantType.micro)
                                .foregroundStyle(SavantPalette.linkBlue)
                        }
                        .buttonStyle(.plain)
                    }
                )
            )

            // Recent mode only makes sense for the live season, the 7/15/30-day
            // window is anchored to today, so on a historical season it would
            // always read "No games in the last N days".
            if isCurrentSeasonActive {
                formModePicker
            }

            if formDisplayMode != .season, store.isPro, isCurrentSeasonActive {
                recentWindowPicker
                if recentLoading {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.75)
                        Text("Loading recent games…")
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else if let recentLoadError {
                    Text(recentLoadError)
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if recentWindow == nil {
                    Text("No games in the last \(recentWindowDays) days")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }

            if groupedMetrics.isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "No metrics available",
                    description: "Percentile rankings are not available for this player in the \(seasonLabel) season."
                )
                .padding(.vertical, 24)
            } else {
                ForEach(groupedMetrics, id: \.category) { group in
                    let rows = displayedMetrics(in: group.metrics)
                    if !rows.isEmpty {
                        SavantSubSectionBar(
                            title: "\(group.category.rawValue.uppercased())"
                        )

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                            percentileMetricRow(metric: metric, index: index)
                        }
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
        .task(id: "\(formDisplayMode)-\(recentWindowDays)-\(player.playerId)-\(activeSeason ?? 0)-\(store.isPro)") {
            guard store.isPro, effectiveFormDisplayMode != .season else { return }
            rebuildRecentCurves()
            await loadRecentLogs()
        }
        .onAppear { rebuildRecentCurves() }
        .onChange(of: allPlayers.count) { _, _ in rebuildRecentCurves() }
    }

    private var isPitcher: Bool { player.playerType == "pitcher" }

    /// Recent-form is anchored to today's date, so it's only meaningful while
    /// viewing the current season. Historical seasons render season bars only.
    private var isCurrentSeasonActive: Bool {
        (activeSeason ?? StatScoutSeason.current) == StatScoutSeason.current
    }

    /// The mode rows actually render in, forced back to `.season` on a
    /// historical season so a user who toggled Recent/Both doesn't see stale
    /// current-season windows against past-season bars.
    private var effectiveFormDisplayMode: FormDisplayMode {
        isCurrentSeasonActive ? formDisplayMode : .season
    }

    private var recentWindow: RecentFormWindow? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: .now) ?? .now
        let windowLogs = recentLogs.filter { $0.gameDate >= cutoff }
        guard !windowLogs.isEmpty else { return nil }
        return RecentFormWindow.build(label: "Last \(recentWindowDays)", days: recentWindowDays, logs: windowLogs)
    }

    private var recentWindowPicker: some View {
        SavantSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: Binding(
                get: { RecentWindow(rawValue: recentWindowDays) ?? .fortnight },
                set: { recentWindowDays = $0.rawValue }
            )
        )
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.bottom, 8)
        .background(SavantPalette.surfaceAlt)
    }

    private func displayedMetrics(in metrics: [Metric]) -> [Metric] {
        // Applies to Both as well as Recent. It used to be Recent-only, so in
        // Both a metric with window data but no season row simply vanished
        // rather than showing its recent bar alone.
        guard effectiveFormDisplayMode != .season, store.isPro else { return metrics }
        // Recent mode: show every season bar, metrics with window data render the
        // recent value, the rest fall back to the season bar (handled in
        // `percentileMetricRow`). Additionally inject a stub for any game-log spec
        // the season snapshot omits (Savant sometimes drops e.g. Hard-Hit%) so its
        // recent bar still appears even with no season row to hang it on.
        let targetCategory: MetricCategory = isPitcher ? .pitching : .hitting
        guard metrics.first?.category == targetCategory else { return metrics }
        let existing = Set(metrics.map { $0.label })
        let stubs: [Metric] = recentSpecs.compactMap { spec in
            guard !existing.contains(spec.label) else { return nil }
            let stub = Metric(
                id: "recent-stub-\(spec.key)",
                label: spec.label,
                value: "",
                percentile: 0,
                category: targetCategory
            )
            return recentMetric(for: stub) != nil ? stub : nil
        }
        return metrics + stubs
    }

    /// Game-log metric key → the season metric whose league curve places it.
    ///
    /// Every entry needs a season counterpart: the recent bar is drawn on the
    /// league's season percentile ruler, so a metric Savant doesn't publish
    /// season percentiles for has nothing to be placed against. That's why
    /// batter Hard-Hit% / Sweet-Spot% / LA and pitcher Whiff% / Chase% are
    /// absent here even though the game logs now carry them, Savant only
    /// publishes those percentiles for the other side of the ball.
    private var recentSpecs: [(key: String, label: String, seasonLabel: String, format: String)] {
        isPitcher
            ? [
                ("opp_xwoba", "xwOBA", "xwOBA", "%.3f"),
                ("opp_xba", "xBA", "xBA", "%.3f"),
                ("opp_xslg", "xSLG", "xSLG", "%.3f"),
                ("k_pct", "K%", "K%", "%.1f%%"),
                ("bb_pct", "BB%", "BB%", "%.1f%%"),
                ("opp_hardhit_pct", "Hard-Hit%", "Hard-Hit%", "%.1f%%"),
                ("opp_barrel_pct", "Barrel%", "Barrel%", "%.1f%%"),
                ("opp_ev_avg", "Avg EV Against", "Avg EV Against", "%.1f mph"),
                ("opp_ev_max", "Max EV Against", "Max EV Against", "%.1f mph"),
                ("fb_velo_avg", "Fastball Velo", "Fastball Velo", "%.1f mph"),
                ("fb_spin_avg", "Fastball Spin", "Fastball Spin", "%.0f rpm"),
            ]
            : [
                ("xwoba", "xwOBA", "xwOBA", "%.3f"),
                ("xba", "xBA", "xBA", "%.3f"),
                ("xslg", "xSLG", "xSLG", "%.3f"),
                ("xiso", "xISO", "xISO", "%.3f"),
                ("barrel_pct", "Barrel%", "Barrel%", "%.1f%%"),
                ("ev_avg", "EV", "EV", "%.1f mph"),
                ("ev_max", "Max EV", "Max EV", "%.1f mph"),
                ("k_pct", "K%", "K%", "%.1f%%"),
                ("bb_pct", "BB%", "BB%", "%.1f%%"),
                ("whiff_pct", "Whiff%", "Whiff%", "%.1f%%"),
                ("chase_pct", "Chase%", "Chase%", "%.1f%%"),
                ("bat_speed", "Bat Speed", "Bat Speed", "%.1f mph"),
                ("swing_length", "Swing Length", "Swing Length", "%.2f ft"),
            ]
    }

    @ViewBuilder
    private func percentileMetricRow(metric: Metric, index: Int) -> some View {
        let recentMetric = recentMetric(for: metric)
        let rowBackground = index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt

        switch effectiveFormDisplayMode {
        case .season:
            NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason)) {
                MetricBar(metric: metric)
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
            }
            .buttonStyle(.plain)
        case .recent:
            if let recentMetric {
                MetricBar(metric: recentMetric)
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
            } else if !metric.id.hasPrefix("recent-stub-") {
                // No game-log data for this metric, fall back to the season bar
                // so the recent view still shows every percentile bar.
                NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason)) {
                    MetricBar(metric: metric)
                        .padding(.horizontal, SavantGeo.padCard)
                        .padding(.vertical, 12)
                        .background(rowBackground)
                        .overlay(
                            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        case .both:
            if metric.id.hasPrefix("recent-stub-") {
                // Recent-only metric, there's no season row to pair it with, so
                // pairing it with the empty stub would draw a season bar at 0.
                if let recentMetric {
                    MetricBar(metric: recentMetric)
                        .padding(.horizontal, SavantGeo.padCard)
                        .padding(.vertical, 12)
                        .background(rowBackground)
                        .overlay(
                            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                            alignment: .bottom
                        )
                }
            } else {
                NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason)) {
                    DualMetricBar(
                        season: metric,
                        recent: recentMetric,
                        recentCaption: "Last \(recentWindowDays)d"
                    )
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recentMetric(for seasonMetric: Metric) -> Metric? {
        guard let w = recentWindow else { return nil }
        guard let spec = recentSpecs.first(where: { $0.label == seasonMetric.label || $0.seasonLabel == seasonMetric.label }),
              let v = w.metrics[spec.key],
              let pct = recentCurves?.curve(for: spec.seasonLabel)?.percentile(for: v) else { return nil }
        return Metric(
            id: "recent-\(spec.key)",
            label: seasonMetric.label,
            value: String(format: spec.format, v),
            percentile: pct,
            category: seasonMetric.category
        )
    }

    /// Build one curve per season label the recent specs reference, so the two
    /// stay in step automatically instead of via a hand-kept parallel list.
    private func rebuildRecentCurves() {
        recentCurves = LeaguePercentileCurves(
            players: allPlayers,
            playerType: player.playerType ?? (isPitcher ? "pitcher" : "batter"),
            labels: Array(Set(recentSpecs.map(\.seasonLabel))),
            category: isPitcher ? .pitching : .hitting
        )
    }

    private func loadRecentLogs() async {
        guard store.isPro, let fetch = fetchGameLogs,
              let season = activeSeason ?? player.season else { return }
        recentLoading = true
        recentLoadError = nil
        do {
            recentLogs = try await fetch(player.playerId, season)
        } catch {
            // Distinguish "no games" from "fetch failed", otherwise a network
            // error renders as an honest-looking "No games in the last N days".
            recentLogs = []
            recentLoadError = "Couldn't load recent games. Check your connection and try again."
        }
        recentLoading = false
    }

    /// Traditional stats where a lower number is the better outcome, so the
    /// percentile has to be inverted before it's drawn.
    ///
    /// This has to be per-side: the same label means opposite things. A
    /// batter's HR, R, H and BB are all good; a pitcher's are runs and homers
    /// surrendered. A batter's SO is bad, a pitcher's is the whole point.
    /// Keyed off the stat's own category rather than the player's type, because
    /// a two-way player carries both lines at once and "H" means the opposite
    /// thing on each.
    private static func lowerIsBetterStandard(category: MetricCategory) -> Set<String> {
        switch category {
        case .pitching:
            return ["ERA", "WHIP", "L", "H", "R", "ER", "HR", "BB", "BB/9",
                    // On a pitcher's line these are what hitters did against them.
                    "AVG", "OBP", "SLG", "OPS"]
        case .hitting:
            return ["SO", "CS"]
        case .fielding:
            return ["E"]
        case .running:
            return ["CS"]
        }
    }

    /// Which of the four boards a traditional stat belongs to, so tapping a
    /// row opens the leaderboard that actually lists it. Errors and the glove
    /// line moved to Fielding, the stolen-base line to Running, and without
    /// this a hitter's E row pushed the Hitting board, which has no E column.
    private static func standardCategory(for label: String, statCategory: MetricCategory) -> MetricCategory {
        switch label.uppercased() {
        case "E", "A", "PO", "DP", "FLD%", "GF": return .fielding
        case "SB", "CS", "SB%": return .running
        // Otherwise the stat's own line, which is the only thing that gets a
        // two-way player's "H" onto the right board.
        default: return statCategory
        }
    }

    /// Counting stats. Ranking these is honest but playing-time driven, a
    /// bench bat's 2 HR isn't a talent signal, so they're grouped separately
    /// from the rate stats and captioned as volume.
    private static let countingStats: Set<String> = [
        "HR", "R", "RBI", "H", "2B", "3B", "BB", "SO", "SB", "CS", "PA", "AB",
        "W", "L", "SV", "IP", "ER", "QS", "G", "GS", "BF",
        "E", "A", "PO", "DP", "GF",
    ]

    /// Percentile rank for a traditional stat against the league.
    ///
    /// Savant publishes percentiles for its Statcast metrics but not for the
    /// traditional line, so these are computed here, a player's position in
    /// the distribution of every same-type player who has the stat. Returns nil
    /// below a usable pool size rather than drawing a bar off five samples.
    /// The comparison pool must clear the same bar the Standard leaderboard
    /// applies, or the two screens answer "how does this rank" against
    /// different leagues. `StandardStatsLeadersView` requires a Savant
    /// percentile in the matching category (Savant withholds them below its
    /// qualifying thresholds, so their presence *is* the qualification signal);
    /// this used to require only a matching player type, which let bench bats
    /// and mop-up relievers into the denominator.
    private func standardStatPercentile(label: String, category: MetricCategory, value: Double) -> Int? {
        let key = label.uppercased()
        // Fielding and running stats belong to position players and are gated
        // on a hitting percentile, matching the leaders board.
        let qualifyingCategory: MetricCategory = category == .pitching ? .pitching : .hitting
        let values: [Double] = allPlayers.compactMap { other in
            let otherType = other.playerType?.lowercased()
            let sideMatches = qualifyingCategory == .pitching
                ? (otherType == "pitcher" || otherType == "two_way")
                : otherType != "pitcher"
            guard sideMatches else { return nil }
            guard other.metrics.contains(where: { $0.category == qualifyingCategory }) else { return nil }
            // Match on category too: a two-way player has an "H" on each line.
            guard let stat = other.standardStats?.first(where: {
                $0.label.uppercased() == key
                    && $0.resolvedCategory(playerType: other.playerType) == category
            }) else { return nil }
            return DashboardViewModel.rawNumeric(stat.value)
        }
        guard values.count >= 20 else { return nil }

        // Midpoint rank, so a cluster of identical values lands mid-band
        // instead of all sharing the top of it.
        let below = values.reduce(0) { $0 + ($1 < value ? 1 : 0) }
        let equal = values.reduce(0) { $0 + ($1 == value ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        let oriented = Self.lowerIsBetterStandard(category: category).contains(key) ? 100 - raw : raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    /// Standard stats rendered as the same `Metric` the percentile card uses,
    /// so both tabs read on one ruler. Stats with too small a league pool keep
    /// their value but get no bar.
    /// Each stat keeps its own category. This used to stamp every one of them
    /// with `isPitcher ? .pitching : .hitting`, and `isPitcher` is false for a
    /// two-way player, so Ohtani's ERA, W-L and innings were all labelled
    /// hitting and rendered interleaved with his batting line.
    private func standardMetrics(counting: Bool) -> [Metric] {
        (displayedPlayer.standardStats ?? [])
            .filter { Self.countingStats.contains($0.label.uppercased()) == counting }
            .map { stat in
                let category = stat.resolvedCategory(playerType: displayedPlayer.playerType)
                let pct = DashboardViewModel.rawNumeric(stat.value)
                    .flatMap { standardStatPercentile(label: stat.label, category: category, value: $0) }
                return Metric(
                    // Namespaced by category: a two-way player has two "H" rows
                    // and a duplicate id collapses them in an Identifiable list.
                    id: "std-\(category.rawValue)-\(stat.label)",
                    label: stat.label.uppercased(),
                    value: stat.value,
                    percentile: pct ?? 0,
                    category: category
                )
            }
    }

    /// Traditional stat label → the rollup's key. RBI, runs, stolen bases and
    /// caught stealing aren't derivable from pitch-level data, so they have no
    /// recent counterpart and keep their season row alone.
    private static let standardRecentKeys: [String: String] = [
        "AVG": "avg", "OBP": "obp", "SLG": "slg", "OPS": "ops",
        "H": "h", "HR": "hr", "2B": "2b", "3B": "3b",
        "BB": "bb", "SO": "so", "AB": "ab",
    ]

    private var standardRecentForm: RecentForm? {
        recentFormLookup?(player.playerId, standardWindow)
    }

    /// The recent-window version of one traditional stat, or nil when the
    /// window has no figure for it. Percentile comes from the same league
    /// season distribution the season row uses, so both sit on one ruler.
    private func recentStandardMetric(for seasonMetric: Metric) -> Metric? {
        guard let key = Self.standardRecentKeys[seasonMetric.label],
              let value = standardRecentForm?.metrics[key] else { return nil }
        let isRate = ["AVG", "OBP", "SLG", "OPS"].contains(seasonMetric.label)
        let text = isRate
            ? String(format: "%.3f", value)
            : String(format: "%.0f", value)
        return Metric(
            id: "std-recent-\(seasonMetric.label)",
            label: seasonMetric.label,
            value: text,
            percentile: standardStatPercentile(
                label: seasonMetric.label,
                category: seasonMetric.category,
                value: value
            ) ?? 0,
            category: seasonMetric.category
        )
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            // The season already appears in the picker on the right; printing
            // it in the title too was saying it twice.
            SavantSectionBar(
                title: "STANDARD STATS",
                trailing: AnyView(seasonMenu)
            )

            // Recent only means something on the live season, the window is
            // anchored to today, so on a past season it would always be empty.
            if isCurrentSeasonActive {
                standardModePicker
                if effectiveStandardMode != .season {
                    standardWindowPicker
                }
            }

            if (displayedPlayer.standardStats ?? []).isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "Standard stats unavailable",
                    description: "Traditional stats are not available for this player."
                )
                .padding(.vertical, 24)
            } else {
                let rates = standardMetrics(counting: false)
                let counts = standardMetrics(counting: true)

                if !rates.isEmpty {
                    SavantSubSectionBar(title: "RATE")
                    standardRows(rates)
                }
                if !counts.isEmpty {
                    SavantSubSectionBar(title: "VOLUME")
                    standardRows(counts, startingIndex: rates.count)
                }
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var effectiveStandardMode: FormDisplayMode {
        (store.isPro && isCurrentSeasonActive) ? standardMode : .season
    }

    private var standardModePicker: some View {
        SavantSegmented(
            segments: FormDisplayMode.allCases.map {
                .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 != .season)
            },
            selection: $standardMode,
            onLockedTap: { _ in trialPitchTrigger = .recentForm }
        )
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.vertical, 10)
        .background(SavantPalette.surfaceAlt)
        .onChange(of: standardMode) { _, mode in
            if mode != .season { Task { await loadRecentForm?(standardWindow) } }
        }
    }

    private var standardWindowPicker: some View {
        SavantSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: $standardWindow
        )
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.bottom, 8)
        .background(SavantPalette.surfaceAlt)
        .onChange(of: standardWindow) { _, window in
            Task { await loadRecentForm?(window) }
        }
    }

    @ViewBuilder
    private func standardRows(_ metrics: [Metric], startingIndex: Int = 0) -> some View {
        ForEach(Array(metrics.enumerated()), id: \.element.id) { offset, metric in
            let recent = recentStandardMetric(for: metric)
            let background = (startingIndex + offset) % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt

            NavigationLink(value: StandardStatRoute(
                stat: metric.label,
                category: Self.standardCategory(for: metric.label, statCategory: metric.category),
                season: activeSeason
            )) {
                Group {
                    switch effectiveStandardMode {
                    case .season:
                        MetricBar(metric: metric)
                    case .recent:
                        // No recent figure for this stat, fall back to season
                        // rather than dropping the row, matching the
                        // percentile card's behaviour.
                        MetricBar(metric: recent ?? metric)
                    case .both:
                        DualMetricBar(
                            season: metric,
                            recent: recent,
                            recentCaption: standardWindow.segmentLabel
                        )
                    }
                }
                .padding(.horizontal, SavantGeo.padCard)
                .padding(.vertical, 12)
                .background(background)
                .overlay(
                    Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
        }
    }

}

struct PercentileInfoSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Percentile Rankings")
                        .font(SavantType.playerName)
                        .foregroundStyle(SavantPalette.ink)

                    Text("Percentile rankings compare a player to others at the same position. A 90th percentile means the player ranks in the top 10% of the league for that metric.")
                        .font(SavantType.body)
                        .foregroundStyle(SavantPalette.inkSecondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Elite (75–100): Red bars", systemImage: "flame.fill")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.pctlHot)
                        Label("Average (25–75): Gray bars", systemImage: "minus")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        Label("Below Average (0–25): Blue bars", systemImage: "snowflake")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.pctlCold)
                    }
                    .padding(.vertical, 8)

                    Text("Data refreshes nightly from public baseball percentile leaderboards. Not all metrics are available for every player due to qualifying thresholds.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                .padding(24)
            }
            .background(SavantPalette.canvas.ignoresSafeArea())
            .navigationTitle("About Percentiles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlayerPickerSheet: View {
    let players: [Player]
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredPlayers: [Player] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.team.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredPlayers) { player in
                Button {
                    dismiss()
                    onSelect(player)
                } label: {
                    HStack(spacing: 12) {
                        PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                            Text("\(player.team) · \(player.displayPosition)")
                                .font(SavantType.small)
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
            .navigationTitle("Compare With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerProfileView(player: SampleData.players[0], history: [SampleData.players[0]])
            .environmentObject(StoreService.shared)
    }
}
#endif
