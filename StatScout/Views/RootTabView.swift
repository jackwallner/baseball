import StoreKit
import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct MetricRoute: Hashable {
    let label: String
    let category: MetricCategory
    /// Which season's leaderboard to open. The player profile has its own
    /// season selector, so a route from a 2024 profile has to carry 2024 —
    /// otherwise tapping K% there opened the current-season leaderboard.
    var season: Int? = nil
}

/// Drill-down from a traditional stat row to its league leaderboard.
struct StandardStatRoute: Hashable {
    let stat: String
    let category: StandardStatCategory
    var season: Int? = nil
}

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService
    @Environment(\.requestReview) private var requestReview
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var viewModel: DashboardViewModel
    @State private var selection = 0
    @State private var showReviewPrompt = false
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false
    @State private var pendingNativeReviewAfterDismiss = false
    // Owned here so TeamsView can auto-push the favorite team and the user can
    // still pop back to the list.
    @State private var teamsPath = NavigationPath()

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        tabView
            .tint(SavantPalette.savantRed)
            .sheet(isPresented: $showReviewPrompt, onDismiss: {
            ReviewPromptTracker.markShown()
            if pendingNativeReviewAfterDismiss {
                pendingNativeReviewAfterDismiss = false
                requestReview()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptInitialStep, onFinish: handleReviewPromptFinish)
        }
        .onReceive(NotificationCenter.default.publisher(for: .statscoutPositiveMomentForReview)) { _ in
            scheduleReviewPromptAfterPositiveMoment()
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            guard !showReviewPrompt else { return }
            switch presentation {
            case .enjoymentPrompt:
                presentReviewPrompt(step: .enjoyment)
            case .feedbackOnly:
                presentReviewPrompt(step: .feedback)
            }
        }
    }

    private func scheduleReviewPromptAfterPositiveMoment() {
        guard ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding),
              !reviewPromptShownThisSession,
              !showReviewPrompt
        else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !showReviewPrompt,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding)
            else { return }
            ReviewPromptTracker.consumePendingPositiveMoment()
            reviewPromptInitialStep = .enjoyment
            reviewPromptShownThisSession = true
            showReviewPrompt = true
        }
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        showReviewPrompt = false
        if outcome == .enjoyedMaybeLater {
            pendingNativeReviewAfterDismiss = true
        }
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    /// Hand-rolled tab bar rather than `TabView`.
    ///
    /// On iOS 26 a `TabView` always draws its own Liquid Glass "platter" behind
    /// the items, and `.toolbarBackground(.hidden, for: .tabBar)` is a no-op
    /// against it — which is what made the bar read as a gray box sitting on
    /// the canvas. Owning the bar outright means there is no system background
    /// to fight: the capsule below is the only chrome drawn.
    ///
    /// Each tab stays alive and toggles visibility (matching Vitals' MainTabView)
    /// so navigation stacks and scroll positions survive switching. The inactive
    /// tabs are hidden from VoiceOver as well as from sight — at `opacity(0)`
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
    }

    private enum Tab: Int, CaseIterable, Identifiable {
        case stats, teams, compare

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .stats: return "Stats"
            case .teams: return "Teams"
            case .compare: return "Compare"
            }
        }

        var icon: String {
            switch self {
            case .stats: return "chart.bar.fill"
            case .teams: return "shield.lefthalf.filled"
            case .compare: return "arrow.left.arrow.right"
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .stats: statsTab
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.bottom, 12)
    }

    private var statsTab: some View {
        NavigationStack {
            StatsView(viewModel: viewModel)
                .navigationTitle("Stats")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack(path: $teamsPath) {
            TeamsView(viewModel: viewModel, path: $teamsPath)
                .navigationTitle("Teams")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated))
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
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated))
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
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isSelected ? SavantPalette.savantRed : SavantPalette.inkSecondary)
            .frame(width: 84, height: 44)
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
    }
}

/// Trailing toolbar group shared by the three home tabs: a settings gear, then
/// the upgrade CTA when the user isn't subscribed.
///
/// The gear is the only entry point to Settings that isn't buried — it used to
/// live only in a link under the bottom of the leaderboard, which nobody
/// scrolls to. Trailing rather than leading because Stats already owns the
/// leading slot with its season pill, and a control that moves between tabs
/// isn't an anchor.
private struct HomeTabToolbar: ViewModifier {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    /// Owned per tab, not shared. All three tabs stay alive in the ZStack, so a
    /// single shared flag would push Settings onto all three stacks at once.
    @State private var showingSettings = false
    @State private var paywallTrigger: PaywallTrigger?

    /// Yellow crown + short action verb on a filled pill. The old version was
    /// a bare yellow "Pro" label that read as a status badge rather than a
    /// button — tap-through rates were correspondingly weak. The verb makes
    /// the CTA unambiguous, and the trial-aware label appears when an intro
    /// offer is available.
    private var ctaLabel: String {
        if let yearly = store.products.first(where: { $0.productKind == .yearly }),
           store.isEligibleForIntroOffer(yearly),
           yearly.introOfferLabel != nil {
            return "Try Free"
        }
        return "Upgrade"
    }

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
        .accessibilityLabel("\(ctaLabel) — unlock all features")
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
                    onRequestReview: {
                        showingSettings = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                        }
                    }
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
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
    }
}

private struct StandardDestinations: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Player.self) { player in
                let history = viewModel.playerHistories[player.playerId] ?? []
                let seasonPlayer = history.first { $0.season == viewModel.selectedSeason } ?? player
                PlayerProfileView(
                    player: seasonPlayer,
                    history: history,
                    allPlayers: viewModel.seasonPlayers,
                    isHistoricalLoading: viewModel.isHistoricalLoading,
                    hasLoadedHistorical: viewModel.hasLoadedHistorical,
                    historicalLoadingMessage: viewModel.loadingMessage,
                    historicalLoadingProgress: viewModel.loadingProgress,
                    loadHistorical: { await viewModel.loadHistoricalIfNeeded() },
                    fetchGameLogs: { id, season in
                        try await viewModel.fetchGameLogs(playerId: id, season: season)
                    }
                )
                    .modifier(SavantNavBar())
            }
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
                let season = route.season ?? viewModel.selectedSeason
                MetricRankingView(
                    metricLabel: route.label,
                    metricCategory: route.category,
                    players: viewModel.players(forSeason: season),
                    season: season
                )
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: StandardStatRoute.self) { route in
                let season = route.season ?? viewModel.selectedSeason
                StandardStatsLeadersView(
                    players: viewModel.players(forSeason: season),
                    initialStat: route.stat,
                    initialCategory: route.category,
                    season: season
                )
                    .navigationTitle("\(route.stat) · \(season)")
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                PlayerComparisonView(playerA: route.playerA, playerB: route.playerB)
                    .modifier(SavantNavBar())
            }
    }
}
