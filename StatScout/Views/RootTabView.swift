import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct MetricRoute: Hashable {
    let label: String
    let category: MetricCategory
}

struct RootTabView: View {
    @EnvironmentObject private var store: StoreService
    @State private var viewModel: DashboardViewModel
    @State private var selection = 0
    @State private var showingAbout = false
    // Owned here so TeamsView can auto-push the favorite team and the user can
    // still pop back to the list.
    @State private var teamsPath = NavigationPath()

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        tabView
            .tint(SavantPalette.savantRed)
            .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView(lastUpdated: viewModel.lastUpdated)
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(SavantNavBar())
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingAbout = false }
                                .tint(.white)
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var tabView: some View {
        // iOS 26 adds a Liquid Glass floating tab bar that minimizes on
        // scroll-down — adopt natively where available and fall back to the
        // default tab bar everywhere else. No custom bar to maintain.
        if #available(iOS 26.0, *) {
            TabView(selection: $selection) {
                statsTab
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    .tag(0)

                teamsTab
                    .tabItem { Label("Teams", systemImage: "shield.lefthalf.filled") }
                    .tag(1)

                compareTab
                    .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right") }
                    .tag(2)
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            TabView(selection: $selection) {
                statsTab
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    .tag(0)

                teamsTab
                    .tabItem { Label("Teams", systemImage: "shield.lefthalf.filled") }
                    .tag(1)

                compareTab
                    .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right") }
                    .tag(2)
            }
        }
    }

    private var statsTab: some View {
        NavigationStack {
            StatsView(viewModel: viewModel)
                .navigationTitle("Stats")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(ProToolbarButton())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack(path: $teamsPath) {
            TeamsView(viewModel: viewModel, path: $teamsPath)
                .navigationTitle("Teams")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(ProToolbarButton())
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
                .modifier(ProToolbarButton())
        }
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

private struct ProToolbarButton: ViewModifier {
    @EnvironmentObject private var store: StoreService
    @State private var paywallTrigger: PaywallTrigger?

    /// Yellow crown + short action verb on a filled pill. The old version was
    /// a bare yellow "Pro" label that read as a status badge rather than a
    /// button — tap-through rates were correspondingly weak. The verb makes
    /// the CTA unambiguous, and the trial-aware label appears when an intro
    /// offer is available.
    private var ctaLabel: String {
        store.products.contains(where: { $0.introOfferLabel != nil }) ? "Try Pro" : "Get Pro"
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !store.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
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
                    viewModel: viewModel
                )
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: MetricRoute.self) { route in
                MetricRankingView(metricLabel: route.label, metricCategory: route.category, players: viewModel.seasonPlayers, season: viewModel.selectedSeason)
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                PlayerComparisonView(playerA: route.playerA, playerB: route.playerB)
                    .modifier(SavantNavBar())
            }
    }
}
