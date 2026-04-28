import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    CategoryFilter(selectedCategory: $viewModel.selectedCategory)

                    if !viewModel.biggestRisers.isEmpty || !viewModel.biggestFallers.isEmpty {
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
            SavantSectionBar(title: "BIGGEST MOVERS")
            VStack(spacing: 0) {
                if !viewModel.biggestRisers.isEmpty {
                    moverRow(title: "TRENDING UP", players: viewModel.biggestRisers)
                }
                if !viewModel.biggestFallers.isEmpty {
                    moverRow(title: "TRENDING DOWN", players: viewModel.biggestFallers)
                }
            }
            .background(SavantPalette.surfaceAlt)
            .overlay(Rectangle().fill(SavantPalette.hairline).frame(height: SavantGeo.hairline), alignment: .bottom)
        }
    }

    private func moverRow(title: String, players: [Player]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SavantType.micro)
                .tracking(0.6)
                .foregroundStyle(SavantPalette.inkSecondary)
                .padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(players) { player in
                        NavigationLink(value: player) {
                            FeaturedTile(player: player, weeklyDelta: player.weeklyDelta)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
    }

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "LEADERBOARD")

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
            } else if let errorMessage = viewModel.errorMessage, viewModel.leaderboard.isEmpty {
                ContentUnavailableView {
                    Label("Data Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SavantPalette.inkTertiary)
                }
                .padding(.vertical, 24)
            } else if viewModel.leaderboard.isEmpty {
                ContentUnavailableView {
                    Label("No players yet", systemImage: "baseball")
                } description: {
                    Text("Check back after the nightly update.")
                }
                .padding(.vertical, 24)
            } else {
                LeaderboardTableHeader()
                ForEach(Array(viewModel.leaderboard.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player
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
