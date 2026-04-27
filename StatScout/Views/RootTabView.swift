import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct MetricRoute: Hashable {
    let label: String
}

struct RootTabView: View {
    @State private var viewModel: DashboardViewModel
    @State private var selection = 0

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

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(3)
        }
        .tint(SavantPalette.savantRed)
        .onChange(of: selection) { _, _ in
            viewModel.searchText = ""
        }
        .task { await viewModel.load() }
    }

    private var leadersTab: some View {
        NavigationStack {
            DashboardView(viewModel: viewModel)
                .navigationTitle("Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack {
            TeamsView(viewModel: viewModel)
                .navigationTitle("Teams")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var metricsTab: some View {
        NavigationStack {
            MetricLeadersView(metrics: viewModel.allMetrics)
                .navigationTitle("Metric Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var aboutTab: some View {
        NavigationStack {
            AboutView(lastUpdated: viewModel.lastUpdated)
                .navigationTitle("About")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(SavantNavBar())
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
                PlayerProfileView(player: player)
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: TeamDestination.self) { dest in
                TeamView(team: dest.abbr, players: viewModel.players(forTeam: dest.abbr))
                    .modifier(SavantNavBar())
            }
            .navigationDestination(for: MetricRoute.self) { route in
                MetricRankingView(metricLabel: route.label, players: viewModel.players)
                    .modifier(SavantNavBar())
            }
    }
}
