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
    @State private var showingPaywall = false

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

            metricsTab
                .tabItem { Label("StatScout", systemImage: "chart.bar.fill") }
                .tag(2)

            standardStatsTab
                .tabItem { Label("Box Score", systemImage: "tablecells.fill") }
                .tag(3)
        }
        .tint(SavantPalette.savantRed)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: .upgrade)
        }
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

    private var metricsTab: some View {
        NavigationStack {
            MetricLeadersView(metrics: selection == 2 ? viewModel.allMetrics : [])
                .navigationTitle("StatScout Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(ProToolbarButton())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var standardStatsTab: some View {
        NavigationStack {
            StandardStatsLeadersView(players: selection == 3 ? viewModel.qualifiedSeasonPlayers : [])
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
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !store.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingPaywall = true
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView(trigger: .upgrade)
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
