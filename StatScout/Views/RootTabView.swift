import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct RootTabView: View {
    @State private var viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        TabView {
            leadersTab
                .tabItem { Label("Leaders", systemImage: "list.number") }

            teamsTab
                .tabItem { Label("Teams", systemImage: "shield.lefthalf.filled") }

            metricsTab
                .tabItem { Label("Metrics", systemImage: "chart.bar.fill") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(SavantPalette.savantRed)
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
    }
}
