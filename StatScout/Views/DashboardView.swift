import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    CategoryFilter(selectedCategory: $viewModel.selectedCategory)

                    leaderboardSection
                }
            }
            if viewModel.isLoading && viewModel.players.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(SavantPalette.inkTertiary)
            }
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
    }

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "LEADERBOARD",
                trailing: AnyView(
                    HStack(spacing: 12) {
                        Button(action: { viewModel.sortDescending.toggle() }) {
                            HStack(spacing: 4) {
                                Text("Sort")
                                Image(systemName: viewModel.sortDescending ? "arrow.down" : "arrow.up")
                            }
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        }
                        if let text = viewModel.freshnessText {
                            Text(text)
                                .font(SavantType.micro)
                                .tracking(0.4)
                                .foregroundStyle(SavantPalette.inkSecondary)
                        }
                    }
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
