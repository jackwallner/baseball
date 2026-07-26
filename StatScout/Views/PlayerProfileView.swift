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
    @State private var showPercentileInfo = false
    @State private var selectedTab: PlayerStatTab = .statcast
    @State private var selectedPercentileSeason: Int? = nil
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingPlayerPicker = false
    @State private var comparisonRoute: ComparisonRoute?
    // Contextual trial pitches (compare, recent form, year compare, first-open)
    // all route through the low-friction TrialPitchSheet — its CTA starts the
    // yearly trial directly. PaywallView stays for the deliberate upsell card.
    @State private var trialPitchTrigger: PaywallTrigger?
    @State private var formDisplayMode: FormDisplayMode = .season
    @State private var recentWindowDays: Int = 15
    @State private var recentLogs: [PlayerGameLog] = []
    @State private var recentLoading = false
    @State private var recentLoadError: String?
    @State private var recentCurves: LeaguePercentileCurves?

    private let profileOpenCountKey = "profileOpenCount"

    enum FormDisplayMode: String, CaseIterable {
        case season = "Season"
        case recent = "Recent"
        case both = "Both"
    }

    enum PlayerStatTab: String, CaseIterable {
        case statcast = "Percentiles"
        case standard = "Standard Stats"
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
        activeSeason.map(String.init) ?? "—"
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
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        // First-tap activation: profile renders immediately (no full-screen
        // paywall blocking it), and a native half-sheet TrialPitchSheet
        // floats on top with a "Maybe later" dismiss. PaywallGate caps this
        // at 2 per session so repeat taps don't re-prompt. The old full-page
        // .activation PaywallView was removed for being too intrusive — this
        // is the Vitals-style soft pitch that replaced it.
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .sheet(isPresented: $showPercentileInfo) {
            PercentileInfoSheet()
        }
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerSheet(players: comparablePlayers) { selected in
                comparisonRoute = ComparisonRoute(playerA: player, playerB: selected)
            }
        }
        .sheet(item: $trialPitchTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(playerA: route.playerA, playerB: route.playerB)
        }
        .onAppear {
            // Defer the first-impression pitch: a user verifying one stat from a
            // group chat shouldn't hit a subscription story before scrolling a
            // single row. Show it from the *second* profile open onward (Pro-only
            // controls — Recent Form, past seasons, Compare — still pitch on tap).
            let opens = UserDefaults.standard.integer(forKey: profileOpenCountKey) + 1
            UserDefaults.standard.set(opens, forKey: profileOpenCountKey)
            if !store.isPro, opens >= 2, PaywallGate.shared.shouldPresent(.playerScouting) {
                trialPitchTrigger = .playerScouting
            }
            // Third+ profile visit = engaged browsing; never on open 2 (trial pitch).
            if opens >= 3 {
                ReviewPromptTracker.recordPositiveMoment()
            }
        }
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
                    fetchGameLogs: fetchGameLogs,
                    onUpgradeTap: { trialPitchTrigger = .recentForm }
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
                proPerk("arrow.down.circle.fill", "Saved offline — works on the road")
            }

            Button {
                paywallTrigger = store.defaultUpgradeTrigger
            } label: {
                HStack(spacing: 6) {
                    Text(store.paywallBlurCTA)
                        .font(SavantType.bodyBold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(SavantPalette.savantRed)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let subtext = store.paywallBlurSubtext {
                Text(subtext)
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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
            YearComparePreview(playerName: player.name) {
                trialPitchTrigger = .yearCompare
            }
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
        let seasons = availablePercentileSeasons
        return Group {
            if seasons.count > 1 {
                Menu {
                    ForEach(seasons, id: \.self) { season in
                        let isLocked = season != StatScoutSeason.free && !store.isPro
                        Button {
                            if isLocked {
                                // Explicit tap on a locked season — always answer it.
                                // PaywallGate only caps automatic pop-ups.
                                trialPitchTrigger = .lockedSeason(season)
                            } else {
                                selectedPercentileSeason = season
                            }
                        } label: {
                            HStack {
                                Text(String(season))
                                if isLocked {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.yellow)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(seasonLabel)
                            .font(SavantType.micro)
                            .tracking(0.5)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SavantPalette.inkSecondary)
                    }
                }
                .menuOrder(.fixed)
            } else {
                Text(seasonLabel)
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
        }
    }

    private var formModePicker: some View {
        HStack(spacing: 6) {
            ForEach(FormDisplayMode.allCases, id: \.self) { mode in
                Button {
                    formDisplayMode = mode
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(mode.rawValue)
                        .font(SavantType.smallBold)
                        .foregroundStyle(formDisplayMode == mode ? .white : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(formDisplayMode == mode ? SavantPalette.savantRed : SavantPalette.surface)
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

    private var percentileRankingsCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "PERCENTILE RANKINGS",
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

            // Recent mode only makes sense for the live season — the 7/15/30-day
            // window is anchored to today, so on a historical season it would
            // always read "No games in the last N days".
            if store.isPro, isCurrentSeasonActive {
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

    /// The mode rows actually render in — forced back to `.season` on a
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
        HStack(spacing: 6) {
            ForEach(RecentFormWindow.windows, id: \.days) { w in
                Button {
                    recentWindowDays = w.days
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(w.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(recentWindowDays == w.days ? .white : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(recentWindowDays == w.days ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.bottom, 8)
        .background(SavantPalette.surfaceAlt)
    }

    private func displayedMetrics(in metrics: [Metric]) -> [Metric] {
        // Applies to Both as well as Recent. It used to be Recent-only, so in
        // Both a metric with window data but no season row simply vanished
        // rather than showing its recent bar alone.
        guard effectiveFormDisplayMode != .season, store.isPro else { return metrics }
        // Recent mode: show every season bar — metrics with window data render the
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
    /// absent here even though the game logs now carry them — Savant only
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
            NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
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
                // No game-log data for this metric — fall back to the season bar
                // so the recent view still shows every percentile bar.
                NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
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
                // Recent-only metric — there's no season row to pair it with, so
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
                NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
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
            // Distinguish "no games" from "fetch failed" — otherwise a network
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
    private static func lowerIsBetterStandard(isPitcher: Bool) -> Set<String> {
        isPitcher
            ? ["ERA", "WHIP", "L", "H", "R", "ER", "HR", "BB", "BB/9",
               // On a pitcher's line these are what hitters did against them.
               "AVG", "OBP", "SLG", "OPS"]
            : ["SO", "CS"]
    }

    /// Counting stats. Ranking these is honest but playing-time driven — a
    /// bench bat's 2 HR isn't a talent signal — so they're grouped separately
    /// from the rate stats and captioned as volume.
    private static let countingStats: Set<String> = [
        "HR", "R", "RBI", "H", "2B", "3B", "BB", "SO", "SB", "CS", "PA", "AB",
        "W", "L", "SV", "IP", "ER", "QS", "G", "GS", "BF",
    ]

    /// Percentile rank for a traditional stat against the league.
    ///
    /// Savant publishes percentiles for its Statcast metrics but not for the
    /// traditional line, so these are computed here — a player's position in
    /// the distribution of every same-type player who has the stat. Returns nil
    /// below a usable pool size rather than drawing a bar off five samples.
    private func standardStatPercentile(label: String, value: Double) -> Int? {
        let key = label.uppercased()
        let isPitcherPool = isPitcher
        let values: [Double] = allPlayers.compactMap { other in
            let otherIsPitcher = other.playerType?.lowercased() == "pitcher"
            guard otherIsPitcher == isPitcherPool else { return nil }
            guard let stat = other.standardStats?.first(where: { $0.label.uppercased() == key })
            else { return nil }
            return DashboardViewModel.rawNumeric(stat.value)
        }
        guard values.count >= 20 else { return nil }

        // Midpoint rank, so a cluster of identical values lands mid-band
        // instead of all sharing the top of it.
        let below = values.reduce(0) { $0 + ($1 < value ? 1 : 0) }
        let equal = values.reduce(0) { $0 + ($1 == value ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        let oriented = Self.lowerIsBetterStandard(isPitcher: isPitcher).contains(key) ? 100 - raw : raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    /// Standard stats rendered as the same `Metric` the percentile card uses,
    /// so both tabs read on one ruler. Stats with too small a league pool keep
    /// their value but get no bar.
    private func standardMetrics(counting: Bool) -> [Metric] {
        (displayedPlayer.standardStats ?? [])
            .filter { Self.countingStats.contains($0.label.uppercased()) == counting }
            .map { stat in
                let pct = DashboardViewModel.rawNumeric(stat.value)
                    .flatMap { standardStatPercentile(label: stat.label, value: $0) }
                return Metric(
                    id: "std-\(stat.label)",
                    label: stat.label.uppercased(),
                    value: stat.value,
                    percentile: pct ?? 0,
                    category: isPitcher ? .pitching : .hitting
                )
            }
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            // The season already appears in the picker on the right; printing
            // it in the title too was saying it twice.
            SavantSectionBar(
                title: "STANDARD STATS",
                trailing: AnyView(seasonMenu)
            )

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

    private func standardRows(_ metrics: [Metric], startingIndex: Int = 0) -> some View {
        ForEach(Array(metrics.enumerated()), id: \.element.id) { offset, metric in
            MetricBar(metric: metric)
                .padding(.horizontal, SavantGeo.padCard)
                .padding(.vertical, 12)
                .background((startingIndex + offset) % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                    alignment: .bottom
                )
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
