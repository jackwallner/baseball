import SwiftUI

enum SheetDestination: Identifiable {
    case player(Player)
    case team(String)
    case settings
    case metricLeaders

    var id: String {
        switch self {
        case .player(let p): return "player-\(p.id)"
        case .team(let t): return "team-\(t)"
        case .settings: return "settings"
        case .metricLeaders: return "metric-leaders"
        }
    }
}

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var sheetDestination: SheetDestination?
    @State private var teamSheetPlayer: Player?

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HeroHeaderView(playerCount: viewModel.players.count)

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }

                    SearchField(text: $viewModel.searchText)

                    if !viewModel.allTeams.isEmpty {
                        SectionHeader(title: "Teams", subtitle: "Tap a team to view its roster")
                        TeamChipRow(teams: viewModel.allTeams) { team in
                            sheetDestination = .team(team)
                        }
                    }

                    CategoryFilter(selectedCategory: $viewModel.selectedCategory)

                    HStack {
                        RandomPlayerButton {
                            if let player = viewModel.randomPlayer {
                                sheetDestination = .player(player)
                            }
                        }
                        Spacer()
                        Button(action: { sheetDestination = .metricLeaders }) {
                            HStack(spacing: 6) {
                                Image(systemName: "list.number")
                                Text("Metric Leaders")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(StatScoutTheme.card, in: Capsule())
                            .overlay(Capsule().stroke(StatScoutTheme.stroke))
                        }
                    }

                    SectionHeader(title: "Featured", subtitle: "Top 5 by overall blended percentile")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.featuredPlayers) { player in
                                PlayerCard(player: player)
                                    .frame(width: 300)
                                    .onTapGesture { sheetDestination = .player(player) }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)

                    SectionHeader(title: "Leaderboard", subtitle: "All players sorted by overall percentile (highest first)")

                    VStack(spacing: 12) {
                        ForEach(viewModel.leaderboard) { player in
                            LeaderboardRow(player: player)
                                .onTapGesture { sheetDestination = .player(player) }
                        }
                    }
                }
                .padding(20)
            }
            .background(StatScoutTheme.background.ignoresSafeArea())
            .navigationTitle("StatScout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { sheetDestination = .settings }) {
                        Image(systemName: "gear")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(item: $sheetDestination) { destination in
                switch destination {
                case .player(let player):
                    PlayerProfileView(player: player)
                case .team(let team):
                    TeamView(
                        team: team,
                        players: viewModel.players(forTeam: team),
                        selectedPlayer: .init(
                            get: { teamSheetPlayer },
                            set: { newValue in
                                teamSheetPlayer = newValue
                                if newValue != nil {
                                    sheetDestination = .player(newValue!)
                                }
                            }
                        )
                    )
                case .settings:
                    SettingsView(lastUpdated: viewModel.lastUpdated)
                case .metricLeaders:
                    MetricLeadersView(
                        metrics: viewModel.allMetrics,
                        selectedPlayer: .init(
                            get: { teamSheetPlayer },
                            set: { newValue in
                                teamSheetPlayer = newValue
                                if newValue != nil {
                                    sheetDestination = .player(newValue!)
                                }
                            }
                        )
                    )
                }
            }
            .task {
                await viewModel.load()
            }
        }
        .tint(.white)
    }
}

#Preview {
    DashboardView(viewModel: DashboardViewModel())
}
