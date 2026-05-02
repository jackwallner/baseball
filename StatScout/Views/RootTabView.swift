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

            metricsTab
                .tabItem { Label("Metrics", systemImage: "chart.bar.fill") }
                .tag(2)
        }
        .tint(SavantPalette.savantRed)
        .task { await viewModel.load() }
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
                .modifier(StandardDestinations(viewModel: viewModel))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingAbout = true }) {
                            Image(systemName: "gear")
                        }
                        .tint(.white)
                    }
                }
        }
    }

    private var teamsTab: some View {
        NavigationStack {
            TeamsView(viewModel: viewModel)
                .navigationTitle("Teams")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingAbout = true }) {
                            Image(systemName: "gear")
                        }
                        .tint(.white)
                    }
                }
        }
    }

    private var metricsTab: some View {
        NavigationStack {
            MetricLeadersView(metrics: viewModel.allMetrics)
                .navigationTitle("Metric Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingAbout = true }) {
                            Image(systemName: "gear")
                        }
                        .tint(.white)
                    }
                }
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

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Player.self) { player in
                PlayerProfileView(player: player, history: viewModel.playerHistories[player.playerId] ?? [])
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: TeamDestination.self) { dest in
                TeamView(team: dest.abbr, players: viewModel.players(forTeam: dest.abbr))
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: MetricRoute.self) { route in
                MetricRankingView(metricLabel: route.label, metricCategory: route.category, players: viewModel.players)
                    .modifier(SavantNavBar())
            }
    }
}
