import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let store: StoreManager
    @State private var showingAbout = false
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    unifiedControlBar
                    leaderboardSection
                    if !viewModel.players.isEmpty {
                        aboutFooter
                    }
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
                AboutView(lastUpdated: viewModel.lastUpdated, store: store)
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
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store)
        }
    }

    private var aboutFooter: some View {
        VStack(spacing: 8) {
            if store.proStatus != .purchased {
                Button(action: { showingPaywall = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                        Text("Unlock Pro")
                            .font(SavantType.micro)
                            .tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(SavantPalette.savantRed)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Button(action: { showingAbout = true }) {
                Text("About StatScout")
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            if let text = viewModel.freshnessText {
                Text(text)
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                seasonMenu
                Spacer()
                SearchField(text: $viewModel.searchText)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)

            CategoryFilter(selectedCategory: $viewModel.selectedCategory)
        }
        .padding(.top, 8)
    }

    private var seasonMenu: some View {
        Menu {
            Picker("Season", selection: $viewModel.selectedSeason) {
                ForEach(viewModel.availableSeasons, id: \.self) { season in
                    Text(String(season)).tag(season)
                }
            }
        } label: {
            seasonMenuLabel
        }
        .menuOrder(.fixed)
        .fixedSize()
        .accessibilityLabel("Season")
        .accessibilityValue(String(viewModel.selectedSeason))
        .accessibilityHint("Choose which season's stats to view")
    }

    private var seasonMenuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Season")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text(String(viewModel.selectedSeason))
                .font(SavantType.bodyBold)
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(SavantPalette.savantRed)
        .clipShape(Capsule())
    }

    private var sortHeaderMenu: some View {
        Menu {
            let metrics = viewModel.availableSortMetrics
            if !metrics.isEmpty {
                Section("Sort by") {
                    ForEach(metrics, id: \.self) { metric in
                        Button {
                            viewModel.setUserSortMetric(metric)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            if metric == viewModel.currentSortMetric {
                                Label(metric, systemImage: "checkmark")
                            } else {
                                Text(metric)
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    viewModel.sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(
                        viewModel.sortDescending ? "Highest first" : "Lowest first",
                        systemImage: viewModel.sortDescending ? "arrow.down" : "arrow.up"
                    )
                }
            }
        } label: {
            LeaderboardTableHeader(sortDescending: viewModel.sortDescending, sortLabel: viewModel.sortLabel)
        }
        .menuOrder(.fixed)
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
            } else if viewModel.leaderboard.isEmpty && !viewModel.isLoading {
                let noCategoryData = viewModel.selectedCategory != nil && !viewModel.seasonPlayers.isEmpty
                ContentUnavailableView {
                    Label(noCategoryData ? "No players in category" : "No players yet", systemImage: "baseball")
                } description: {
                    Text(noCategoryData
                         ? "No players match the selected category for the \(String(viewModel.selectedSeason)) season."
                         : "No player data is available for the \(String(viewModel.selectedSeason)) season.")
                }
                .padding(.vertical, 24)
                .frame(minHeight: 200)
            } else {
                sortHeaderMenu
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

#if DEBUG
#Preview {
    NavigationStack {
        DashboardView(viewModel: DashboardViewModel(), store: StoreManager())
    }
}
#endif
