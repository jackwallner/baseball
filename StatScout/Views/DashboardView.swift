import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    CategoryFilter(selectedCategory: $viewModel.selectedCategory, counts: viewModel.categoryCounts)

                    if !viewModel.featuredPlayers.isEmpty {
                        featuredStrip
                    }

                    leaderboardSection
                }
            }
            .refreshable {
                await viewModel.load()
            }

            if viewModel.isLoading && viewModel.players.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(SavantPalette.inkTertiary)
            }
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
    }

    private var featuredStrip: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "FEATURED")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.featuredPlayers) { player in
                        NavigationLink(value: player) {
                            FeaturedTile(player: player) { }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(SavantPalette.surfaceAlt)
            .overlay(Rectangle().fill(SavantPalette.hairline).frame(height: SavantGeo.hairline), alignment: .bottom)
        }
    }

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "LEADERBOARD",
                trailing: AnyView(
                    Text("\(viewModel.leaderboard.count) players")
                        .font(SavantType.micro)
                        .tracking(0.5)
                        .foregroundStyle(SavantPalette.inkSecondary)
                )
            )

            SearchField(text: $viewModel.searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if viewModel.leaderboard.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView {
                    Label("No players found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term.")
                }
                .padding(.vertical, 24)
            } else if viewModel.leaderboard.isEmpty {
                ContentUnavailableView {
                    Label("No players yet", systemImage: "baseball")
                } description: {
                    Text("Pull down to refresh or check back after the nightly update.")
                }
                .padding(.vertical, 24)
            } else {
                LeaderboardTableHeader()
                ForEach(Array(viewModel.leaderboard.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player,
                            onTap: {}
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

#Preview {
    NavigationStack {
        DashboardView(viewModel: DashboardViewModel())
    }
}
