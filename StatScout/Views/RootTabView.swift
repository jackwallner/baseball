import StoreKit
import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

/// A player link carries the slate that produced it. A plain `Player` route
/// works on regular-season screens, but it loses context when a pushed
/// leaderboard switches to Postseason without changing the tab behind it.
struct PlayerRoute: Hashable {
    let player: Player
    let phase: SeasonPhase
    let season: Int?

    init(player: Player, phase: SeasonPhase = .regular, season: Int? = nil) {
        self.player = player
        self.phase = phase
        self.season = season
    }
}

struct MetricRoute: Hashable {
    let label: String
    let category: MetricCategory
    var phase: SeasonPhase = .regular
    /// Which season's leaderboard to open. The player profile has its own
    /// season selector, so a route from a 2024 profile has to carry 2024,
    /// otherwise tapping K% there opened the current-season leaderboard.
    var season: Int? = nil
}

/// Drill-down from a traditional stat row to its league leaderboard.
struct StandardStatRoute: Hashable {
    let stat: String
    let category: MetricCategory
    var phase: SeasonPhase = .regular
    var season: Int? = nil
}

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService
    @Environment(\.requestReview) private var requestReview
    /// False while onboarding or an update showcase covers the tabs.
    @Environment(\.isEnabled) private var isEnabled
    @State private var viewModel: DashboardViewModel
    @State private var selection = 0
    @State private var reviewPromptShownThisSession = false
    // Owned here so TeamsView can auto-push the favorite team and the user can
    // still pop back to the list.
    @State private var teamsPath = NavigationPath()
    @State private var statsPath = NavigationPath()

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        tabView
            .tint(SavantPalette.savantRed)
            .onReceive(NotificationCenter.default.publisher(for: .statscoutPositiveMomentForReview)) { _ in
                scheduleReviewRequestAfterPositiveMoment()
            }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .duoRoute)) { note in
                openDuoRoute(note.object as? String ?? "")
            }
            #endif
    }

    #if DEBUG
    private func openDuoRoute(_ route: String) {
        statsPath = NavigationPath()
        teamsPath = NavigationPath()
        switch route {
        case "stats": selection = Tab.stats.rawValue
        case "trends": selection = Tab.trends.rawValue
        case "teams": selection = Tab.teams.rawValue
        case "compare": selection = Tab.compare.rawValue
        case "team":
            selection = Tab.teams.rawValue
            teamsPath.append(TeamDestination(abbr: "NYY"))
        case "player":
            selection = Tab.stats.rawValue
            if let player = viewModel.filteredPlayers.first {
                statsPath.append(PlayerRoute(player: player))
            }
        default: break
        }
    }
    #endif

    /// Nothing sits over the tabs: onboarding and the update showcase are done,
    /// and no sheet, alert, paywall or trial pitch is up. Those sheets belong
    /// to the screens that raise them, so ask UIKit rather than tracking flags.
    private var isScreenClear: Bool {
        guard hasCompletedOnboarding, isEnabled else { return false }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .allSatisfy { $0.rootViewController?.presentedViewController == nil }
    }

    /// The system rating prompt, straight after a positive moment, with no
    /// question in front of it (App Review 5.6.1). Apple decides whether it
    /// shows. If something is on screen the moment stays pending and the next
    /// one asks.
    private func scheduleReviewRequestAfterPositiveMoment() {
        guard ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding),
              !reviewPromptShownThisSession
        else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard isScreenClear,
                  !reviewPromptShownThisSession,
                  ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding)
            else { return }
            reviewPromptShownThisSession = true
            ReviewPromptTracker.markShown()
            requestReview()
        }
    }

    /// Hand-rolled tab bar rather than `TabView`.
    ///
    /// On iOS 26 a `TabView` always draws its own Liquid Glass "platter" behind
    /// the items, and `.toolbarBackground(.hidden, for: .tabBar)` is a no-op
    /// against it, which is what made the bar read as a gray box sitting on
    /// the canvas. Owning the bar outright means there is no system background
    /// to fight: the capsule below is the only chrome drawn.
    ///
    /// Each tab stays alive and toggles visibility (matching Vitals' MainTabView)
    /// so navigation stacks and scroll positions survive switching. The inactive
    /// tabs are hidden from VoiceOver as well as from sight, at `opacity(0)`
    /// they'd otherwise still be reachable via the rotor.
    private var tabView: some View {
        ZStack(alignment: .bottom) {
            ForEach(Tab.allCases) { tab in
                tabContent(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selection == tab.rawValue ? 1 : 0)
                    .allowsHitTesting(selection == tab.rawValue)
                    .accessibilityHidden(selection != tab.rawValue)
            }

            floatingTabBar
        }
        .ignoresSafeArea(edges: .bottom)
        // Every tab stays mounted, so a tab's own `.task` fires once at launch
        // and never again. Trends is the one that depends on a fetch it doesn't
        // own the trigger for, and if that single launch attempt lost its race
        // the board sat empty until the user poked a control. Asking on arrival
        // is cheap: the model returns immediately when the window is cached.
        .onChange(of: selection) { _, tab in
            guard tab == Tab.trends.rawValue else { return }
            Task { await viewModel.loadRecentFormIfNeeded() }
        }
    }

    private enum Tab: Int, CaseIterable, Identifiable {
        case stats, trends, teams, compare

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .stats: return "Stats"
            case .trends: return "Trends"
            case .teams: return "Teams"
            case .compare: return "Compare"
            }
        }

        var icon: String {
            switch self {
            case .stats: return "chart.bar.fill"
            case .trends: return "flame.fill"
            case .teams: return "shield.lefthalf.filled"
            case .compare: return "arrow.left.arrow.right"
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .stats: statsTab
        case .trends: trendsTab
        case .teams: teamsTab
        case .compare: compareTab
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                TabBarButton(
                    icon: tab.icon,
                    label: tab.title,
                    isSelected: selection == tab.rawValue
                ) {
                    guard selection != tab.rawValue else { return }
                    selection = tab.rawValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.bottom, 12)
    }

    private var statsTab: some View {
        NavigationStack(path: $statsPath) {
            StatsView(viewModel: viewModel)
                .navigationTitle("Stats")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataThrough: viewModel.dataThrough, postseasonThrough: viewModel.postseasonThrough))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var trendsTab: some View {
        NavigationStack {
            HotColdView(viewModel: viewModel)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataThrough: viewModel.dataThrough, postseasonThrough: viewModel.postseasonThrough))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack(path: $teamsPath) {
            TeamsView(viewModel: viewModel, path: $teamsPath)
                .navigationTitle("Teams")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataThrough: viewModel.dataThrough, postseasonThrough: viewModel.postseasonThrough))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var compareTab: some View {
        NavigationStack {
            // CompareView declares its own ComparisonRoute / YearCompareRoute
            // destinations, so StandardDestinations is intentionally omitted
            // here to avoid a duplicate navigationDestination for the same type.
            CompareView(viewModel: viewModel)
                .navigationTitle("Compare")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataThrough: viewModel.dataThrough, postseasonThrough: viewModel.postseasonThrough))
        }
    }

}

/// One item in the hand-rolled floating tab bar. The selected pill uses the
/// Savant red at low opacity rather than a filled capsule so the bar stays
/// light over whatever content scrolls beneath it.
private struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(SavantType.small)
                    .tracking(0.2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isSelected ? SavantPalette.savantRed : SavantPalette.inkSecondary)
            .frame(width: 78, height: 52)
            .background(
                isSelected ? SavantPalette.savantRed.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

private struct SavantNavBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(SavantPalette.savantNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .modifier(ReadableColumn())
    }
}

/// Trailing toolbar group shared by the three home tabs: a settings gear, then
/// the upgrade CTA when the user isn't subscribed.
///
/// The gear is the only entry point to Settings that isn't buried, it used to
/// live only in a link under the bottom of the leaderboard, which nobody
/// scrolls to. Trailing rather than leading because Stats already owns the
/// leading slot with its season pill, and a control that moves between tabs
/// isn't an anchor.
private struct HomeTabToolbar: ViewModifier {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    let dataThrough: Date?
    let postseasonThrough: Date?
    /// Owned per tab, not shared. All three tabs stay alive in the ZStack, so a
    /// single shared flag would push Settings onto all three stacks at once.
    @State private var showingSettings = false
    @State private var paywallTrigger: PaywallTrigger?

    /// Yellow crown + short action verb on a filled pill. The old version was
    /// a bare yellow "Pro" label that read as a status badge rather than a
    /// button, tap-through rates were correspondingly weak. The verb makes
    /// the CTA unambiguous, and the trial-aware label appears when an intro
    /// offer is available.
    private var ctaLabel: String { store.upgradeCTALabel }

    private var upgradeButton: some View {
        Button {
            paywallTrigger = store.defaultUpgradeTrigger
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(ctaLabel)
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .fontWeight(.bold)
            }
            .foregroundStyle(SavantPalette.savantNavy)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.yellow)
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(ctaLabel), unlock all features")
    }

    /// Outline cog, no filled circle behind it. The Liquid Glass container
    /// gave it a pale blue disc that made a secondary control louder than the
    /// content it sits above.
    private var settingsButton: some View {
        Button {
            showingSettings = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
        .accessibilityLabel("Settings")
    }

    func body(content: Content) -> some View {
        content
            // A push rather than a bottom sheet: Settings is a place in the
            // app, not a modal interruption over what you were reading.
            .navigationDestination(isPresented: $showingSettings) {
                AboutView(
                    lastUpdated: lastUpdated,
                    dataThrough: dataThrough,
                    postseasonThrough: postseasonThrough
                )
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
            }
            .toolbar {
                // Declared before the CTA so the gear sits to its left.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { settingsButton }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { settingsButton }
                }
                if !store.isPro {
                    // The yellow pill is its own capsule; suppress the iOS 26
                    // Liquid Glass container so it doesn't read as a double-pill.
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarTrailing) { upgradeButton }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarTrailing) { upgradeButton }
                    }
                }
            }
            // The one place that opens the full plan picker. Every other pitch
            // in the app interrupts something the user reached for, so it stays
            // a half sheet; this pill is the user going looking for the offer,
            // and someone who taps it wants to see what the plans cost.
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
    }
}

/// Just the player-profile route. Split out of `StandardDestinations` so the
/// Compare tab, which owns its own comparison routes and so can't take the
/// whole bundle, can still push a player page. Following a player is free, and
/// a followed name that can't be tapped through to its own numbers is a dead
/// row on the one screen the user curated themselves.
struct PlayerProfileDestination: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Player.self) { player in
                profileView(player: player)
            }
            .navigationDestination(for: PlayerRoute.self) { route in
                profileView(
                    player: route.player,
                    requestedPhase: route.phase,
                    requestedSeason: route.season
                )
            }
    }

    @ViewBuilder
    private func profileView(
        player: Player,
        requestedPhase: SeasonPhase? = nil,
        requestedSeason: Int? = nil
    ) -> some View {
        let history = viewModel.playerHistories[player.playerId] ?? []
        let inferredPostseason = viewModel.selectedPhase == .postseason
            && viewModel.postseasonPlayers.contains { $0.id == player.id }
        let profilePhase = requestedPhase ?? (inferredPostseason ? .postseason : .regular)
        let profileSeason = requestedSeason
            ?? (profilePhase == .postseason ? StatScoutSeason.current : viewModel.selectedSeason)
        let activePhase: SeasonPhase = profilePhase == .postseason && profileSeason == StatScoutSeason.current
            ? .postseason
            : .regular
        let seasonPlayer = activePhase == .postseason
            ? player
            : history.first { $0.season == profileSeason } ?? player

        PlayerProfileView(
            player: seasonPlayer,
            history: history,
            phase: activePhase,
            allPlayers: viewModel.players(forSeason: profileSeason, phase: activePhase),
            regularSeasonPlayers: viewModel.players(
                forSeason: StatScoutSeason.current,
                phase: .regular
            ),
            isHistoricalLoading: viewModel.isHistoricalLoading,
            hasLoadedHistorical: viewModel.hasLoadedHistorical,
            historicalLoadingMessage: viewModel.loadingMessage,
            historicalLoadingProgress: viewModel.loadingProgress,
            loadHistorical: { await viewModel.loadHistoricalIfNeeded() },
            fetchGameLogs: { id, season in
                // The profile can switch to a historical year. Let the view
                // model resolve that year to regular season instead of pinning
                // every request to the profile's opening phase.
                let phase: SeasonPhase = activePhase == .postseason && season == StatScoutSeason.current
                    ? .postseason
                    : .regular
                return try await viewModel.fetchGameLogs(playerId: id, season: season, phase: phase)
            },
            recentFormLookup: { id, window in
                viewModel.recentForm(for: id, window: window)
            },
            loadRecentForm: { window in
                await viewModel.loadRecentFormIfNeeded(window: window)
            },
            recentAnchor: activePhase == .postseason
                ? viewModel.postseasonThrough
                : viewModel.dataThrough,
            comparisonCatalog: ComparisonCatalog(viewModel: viewModel, phase: activePhase)
        )
            .modifier(SavantNavBarPublic())
    }
}

private struct StandardDestinations: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .modifier(PlayerProfileDestination(viewModel: viewModel))
            .navigationDestination(for: TeamDestination.self) { dest in
                TeamView(
                    team: dest.abbr,
                    players: viewModel.players(forTeam: dest.abbr),
                    season: viewModel.selectedSeason,
                    viewModel: viewModel,
                    fetchTeamGameLogs: { team, season, since in
                        try await viewModel.fetchTeamGameLogs(team: team, season: season, sinceDate: since)
                    }
                )
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: MetricRoute.self) { route in
                MetricRankingScreen(
                    viewModel: viewModel,
                    metricLabel: route.label,
                    metricCategory: route.category,
                    initialSeason: route.season ?? viewModel.selectedSeason,
                    phase: route.phase
                )
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: StandardStatRoute.self) { route in
                StandardStatsLeaderboardScreen(
                    viewModel: viewModel,
                    initialStat: route.stat,
                    initialCategory: route.category,
                    initialSeason: route.season ?? viewModel.selectedSeason,
                    phase: route.phase
                )
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                PlayerComparisonView(
                    playerA: route.playerA,
                    playerB: route.playerB,
                    phase: route.phase,
                    catalog: ComparisonCatalog(viewModel: viewModel, phase: route.phase)
                )
                    .modifier(SavantNavBar())
            }
    }
}
