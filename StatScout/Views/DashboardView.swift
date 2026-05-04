import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var showingAbout = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    unifiedControlBar
                    leaderboardSection
                    aboutFooter
                }
            }
            .scrollBounceBehavior(.basedOnSize)
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
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView(lastUpdated: viewModel.lastUpdated)
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingAbout = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var aboutFooter: some View {
        Button(action: { showingAbout = true }) {
            Text("About StatScout")
                .font(SavantType.micro)
                .tracking(0.4)
                .foregroundStyle(SavantPalette.inkTertiary)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                seasonMenu
                CategoryFilter(selectedCategory: $viewModel.selectedCategory)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)

            SearchField(text: $viewModel.searchText)
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private var seasonMenu: some View {
        Menu {
            ForEach(viewModel.availableSeasons, id: \.self) { season in
                Button {
                    viewModel.selectedSeason = season
                } label: {
                    HStack {
                        Text(String(season))
                        if viewModel.selectedSeason == season {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(viewModel.selectedSeason))
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(SavantPalette.savantRed)
            .clipShape(Capsule())
        }
    }

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            if viewModel.leaderboard.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView {
                    Label("No players found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term.")
                }
                .padding(.vertical, 24)
                .frame(minHeight: 200)
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
                .frame(minHeight: 200)
            } else if viewModel.leaderboard.isEmpty {
                ContentUnavailableView {
                    Label("No players yet", systemImage: "baseball")
                } description: {
                    Text("Check back after the nightly update.")
                }
                .padding(.vertical, 24)
                .frame(minHeight: 200)
            } else {
                Button(action: {
                    viewModel.sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    LeaderboardTableHeader(sortDescending: viewModel.sortDescending, sortLabel: viewModel.sortLabel)
                }
                .buttonStyle(.plain)
                let sortMetric = viewModel.currentSortMetricForDisplay
                ForEach(Array(viewModel.leaderboard.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player,
                            metricLabel: sortMetric.label,
                            metricCategory: sortMetric.category
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let text = viewModel.freshnessText {
                    Text(text)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
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
