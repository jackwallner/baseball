import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @State private var showingAbout = false
    @State private var paywallTrigger: PaywallTrigger?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    unifiedControlBar
                    leaderboardSection
                    if !viewModel.players.isEmpty {
                        aboutFooter
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await viewModel.load()
            }
            if viewModel.isLoading && viewModel.players.isEmpty {
                loadingCard
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
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
    }

    private var aboutFooter: some View {
        VStack(spacing: 8) {
            if !store.isPro {
                Button(action: { paywallTrigger = store.defaultUpgradeTrigger }) {
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

    private var proUpsellBanner: some View {
        Button {
            paywallTrigger = store.defaultUpgradeTrigger
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)

                Text("Unlock past seasons, comparisons & trends")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.ink)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SavantPalette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                Color.clear.frame(height: 22)
                if (viewModel.isLoading || viewModel.isHistoricalLoading) && !viewModel.players.isEmpty {
                    loadingStatusBar
                } else if let text = viewModel.freshnessText {
                    Text(text)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 12)
                }
            }

            if !store.isPro && !viewModel.players.isEmpty {
                proUpsellBanner
            }

            HStack(spacing: 10) {
                seasonMenu
                Spacer()
                SearchField(text: $viewModel.searchText)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)

            CategoryFilter(selectedCategory: $viewModel.selectedCategory)

            qualifierToggle
        }
        .padding(.top, 8)
    }

    private var qualifierToggle: some View {
        QualifierPicker(selection: $viewModel.qualifierLevel)
            .padding(.horizontal, 12)
    }

    private var seasonMenu: some View {
        Menu {
            if viewModel.isHistoricalLoading {
                Label("Loading past seasons…", systemImage: "hourglass")
            } else if !viewModel.hasLoadedHistorical {
                Button {
                    if store.isPro {
                        Task { await viewModel.loadHistoricalIfNeeded() }
                    } else if PaywallGate.shared.shouldPresent(.pastSeasonsLoad) {
                        paywallTrigger = .pastSeasonsLoad
                    }
                } label: {
                    Label(store.isPro ? "Load past seasons" : "Past seasons require Pro", systemImage: store.isPro ? "clock.arrow.circlepath" : "crown.fill")
                }
            }
            ForEach(viewModel.availableSeasons, id: \.self) { season in
                let isLocked = viewModel.isSeasonLocked(season)
                Button {
                    if isLocked {
                        if PaywallGate.shared.shouldPresent(.pastSeason) { paywallTrigger = .pastSeason }
                    } else {
                        viewModel.selectedSeason = season
                    }
                } label: {
                    HStack {
                        Text(String(season))
                        if isLocked {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                    }
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
            // Ranked by raw value — header carries the active metric name so
            // the column matches the values shown per row. The "Sort by" menu
            // above still picks which metric drives the rank.
            LeaderboardTableHeader(sortDescending: viewModel.sortDescending, sortLabel: viewModel.currentSortMetric ?? viewModel.sortLabel)
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
                LazyVStack(spacing: 0) {
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

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: min(max(viewModel.loadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(SavantPalette.savantRed)
            Text(viewModel.loadingMessage)
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("\(Int(min(max(viewModel.loadingProgress, 0), 1) * 100))%")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .padding(.horizontal, 24)
    }

    private var loadingStatusBar: some View {
        HStack(spacing: 10) {
            ProgressView(value: min(max(viewModel.loadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(SavantPalette.savantRed)
                .frame(maxWidth: .infinity)
            Text(viewModel.loadingMessage)
                .font(SavantType.micro)
                .tracking(0.4)
                .foregroundStyle(SavantPalette.inkSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SavantPalette.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DashboardView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
