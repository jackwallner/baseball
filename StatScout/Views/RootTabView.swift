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

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        TabView(selection: $selection) {
            leadersTab
                .tabItem { Label("Leaders", systemImage: "list.number") }
                .tag(0)

            teamsTab
                .tabItem { Label("Teams", systemImage: "shield.lefthalf.filled") }
                .tag(1)

            compareTab
                .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right") }
                .tag(2)

            metricsTab
                .tabItem { Label("StatScout", systemImage: "chart.bar.fill") }
                .tag(3)

            standardStatsTab
                .tabItem { Label("Box Score", systemImage: "tablecells.fill") }
                .tag(4)
        }
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

    private var leadersTab: some View {
        NavigationStack {
            DashboardView(viewModel: viewModel)
                .navigationTitle("Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(ProToolbarButton())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack {
            TeamsView(viewModel: viewModel)
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

    private var metricsTab: some View {
        NavigationStack {
            MetricLeadersView(metrics: selection == 3 ? viewModel.allMetrics : [])
                .navigationTitle("StatScout Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(ProToolbarButton())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var standardStatsTab: some View {
        NavigationStack {
            StandardStatsLeadersView(players: selection == 4 ? viewModel.qualifiedSeasonPlayers : [])
                .navigationTitle("Box Score Stats")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(ProToolbarButton())
                .modifier(StandardDestinations(viewModel: viewModel))
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

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !store.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            paywallTrigger = store.defaultUpgradeTrigger
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11))
                                Text("Pro")
                                    .font(SavantType.micro)
                                    .tracking(0.3)
                            }
                            .foregroundStyle(Color.yellow)
                        }
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
                    loadHistorical: { await viewModel.loadHistoricalIfNeeded() }
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
