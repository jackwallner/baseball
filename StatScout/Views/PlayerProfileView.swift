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

    private var availablePercentileSeasons: [Int] {
        let fromHistory = history.compactMap(\.season)
        var set = Set(fromHistory)
        if let s = player.season { set.insert(s) }
        return Array(set).sorted(by: >)
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
                                if PaywallGate.shared.shouldPresent(.pastSeason) {
                                    trialPitchTrigger = .pastSeason
                                }
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

            if store.isPro {
                formModePicker
            }

            if formDisplayMode != .season, store.isPro {
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
        .task(id: "\(formDisplayMode)-\(recentWindowDays)-\(player.playerId)") {
            guard store.isPro, formDisplayMode != .season else { return }
            rebuildRecentCurves()
            await loadRecentLogs()
        }
        .onAppear { rebuildRecentCurves() }
        .onChange(of: allPlayers.count) { _, _ in rebuildRecentCurves() }
    }

    private var isPitcher: Bool { player.playerType == "pitcher" }

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
        guard formDisplayMode == .recent, store.isPro else { return metrics }
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

    private var recentSpecs: [(key: String, label: String, seasonLabel: String, format: String)] {
        isPitcher
            ? [
                ("opp_xwoba", "xwOBA", "xwOBA", "%.3f"),
                ("k_pct", "K%", "K%", "%.1f%%"),
                ("bb_pct", "BB%", "BB%", "%.1f%%"),
                ("opp_hardhit_pct", "Hard-Hit%", "Hard-Hit%", "%.1f%%"),
                ("opp_barrel_pct", "Barrel%", "Barrel%", "%.1f%%"),
                ("opp_ev_avg", "EV", "Avg EV Against", "%.1f mph"),
            ]
            : [
                ("xwoba", "xwOBA", "xwOBA", "%.3f"),
                ("barrel_pct", "Barrel%", "Barrel%", "%.1f%%"),
                ("hardhit_pct", "Hard-Hit%", "Hard-Hit%", "%.1f%%"),
                ("ev_avg", "EV", "EV", "%.1f mph"),
                ("ev_max", "Max EV", "Max EV", "%.1f mph"),
                ("k_pct", "K%", "K%", "%.1f%%"),
                ("bb_pct", "BB%", "BB%", "%.1f%%"),
            ]
    }

    @ViewBuilder
    private func percentileMetricRow(metric: Metric, index: Int) -> some View {
        let recentMetric = recentMetric(for: metric)
        let rowBackground = index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt

        switch formDisplayMode {
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

    private func rebuildRecentCurves() {
        // Pitchers' season exit velocity is labeled "Avg EV Against", not "EV".
        let evLabel = isPitcher ? "Avg EV Against" : "EV"
        var labels = ["xwOBA", "Barrel%", "Hard-Hit%", evLabel, "K%", "BB%"]
        if !isPitcher { labels.append("Max EV") }
        recentCurves = LeaguePercentileCurves(
            players: allPlayers,
            playerType: player.playerType ?? (isPitcher ? "pitcher" : "batter"),
            labels: labels
        )
    }

    private func loadRecentLogs() async {
        guard store.isPro, let fetch = fetchGameLogs,
              let season = activeSeason ?? player.season else { return }
        recentLoading = true
        do {
            recentLogs = try await fetch(player.playerId, season)
        } catch {
            recentLogs = []
        }
        recentLoading = false
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "STANDARD STATS · \(seasonLabel)",
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
                let stats = displayedPlayer.standardStats ?? []
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1)
                    ],
                    spacing: 1
                ) {
                    ForEach(stats) { stat in
                        VStack(spacing: 4) {
                            Text(stat.label.uppercased())
                                .font(SavantType.micro)
                                .tracking(0.4)
                                .foregroundStyle(SavantPalette.inkTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(stat.value)
                                .font(SavantType.statMed)
                                .foregroundStyle(SavantPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SavantPalette.surface)
                    }
                }
                .background(SavantPalette.divider)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
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
