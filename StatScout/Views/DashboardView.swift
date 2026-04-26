import SwiftUI

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var selectedPlayer: Player?

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HeroHeaderView(updatedAt: viewModel.players.first?.updatedAt ?? Date())

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }

                    SearchField(text: $viewModel.searchText)

                    CategoryFilter(selectedCategory: $viewModel.selectedCategory)

                    SectionHeader(title: "Tonight's watchlist", subtitle: "Elite percentile snapshots for names fans are talking about")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.featuredPlayers) { player in
                                PlayerCard(player: player)
                                    .frame(width: 300)
                                    .onTapGesture { selectedPlayer = player }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)

                    SectionHeader(title: "Leaderboard", subtitle: "Sorted by blended Statcast percentile")

                    VStack(spacing: 12) {
                        ForEach(viewModel.leaderboard) { player in
                            LeaderboardRow(player: player)
                                .onTapGesture { selectedPlayer = player }
                        }
                    }
                }
                .padding(20)
            }
            .background(StatScoutTheme.background.ignoresSafeArea())
            .navigationTitle("StatScout")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPlayer) { player in
                PlayerProfileView(player: player)
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
