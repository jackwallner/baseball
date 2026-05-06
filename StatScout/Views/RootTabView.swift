import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct MetricRoute: Hashable {
    let label: String
    let category: MetricCategory
}

struct RootTabView: View {
    @State private var viewModel: DashboardViewModel
    let store: StoreManager
    @State private var selection = 0
    @State private var showingAbout = false
    @State private var showingPaywall = false

    init(viewModel: DashboardViewModel, store: StoreManager) {
        _viewModel = State(initialValue: viewModel)
        self.store = store
    }

    var body: some View {
        TabView(selection: $selection) {
            leadersTab
                .tabItem { Label("Leaders", systemImage: "list.number") }
                .tag(0)

            teamsTab
                .tabItem { Label("Teams", systemImage: store.proStatus == .purchased ? "shield.lefthalf.filled" : "lock.shield.fill") }
                .tag(1)

            metricsTab
                .tabItem { Label("Metrics", systemImage: store.proStatus == .purchased ? "chart.bar.fill" : "lock.fill") }
                .tag(2)
        }
        .tint(SavantPalette.savantRed)
        .task { await viewModel.load() }
        .onChange(of: selection) { _, newValue in
            if newValue != 0 && store.proStatus != .purchased {
                selection = 0
                showingPaywall = true
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store)
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView(lastUpdated: viewModel.lastUpdated, store: store)
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
            DashboardView(viewModel: viewModel, store: store)
                .navigationTitle("Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel, store: store))
        }
    }

    private var teamsTab: some View {
        NavigationStack {
            TeamsView(viewModel: viewModel)
                .navigationTitle("Teams")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel, store: store))
        }
    }

    private var metricsTab: some View {
        NavigationStack {
            MetricLeadersView(metrics: viewModel.allMetrics)
                .navigationTitle("Metric Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel, store: store))
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

private struct StandardDestinations: ViewModifier {
    let viewModel: DashboardViewModel
    let store: StoreManager

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Player.self) { player in
                // Get player data for the currently selected season
                let history = viewModel.playerHistories[player.playerId] ?? []
                let seasonPlayer = history.first { $0.season == viewModel.selectedSeason } ?? player
                PlayerProfileView(player: seasonPlayer, history: history, store: store)
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
    }
}
