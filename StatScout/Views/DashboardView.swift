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
                    if !viewModel.leaderboard.isEmpty {
                        sortControlsRow
                    }
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

    // Compact header. Previously stacked 5 rows (freshness, upsell banner,
    // season+search, category filter, qualifier toggle). The freshness text is
    // shown only while data is actually loading (the rest of the time it's
    // just noise); the upsell banner is gone (toolbar Pro chip + in-content
    // cards already promote Pro); and the qualifier picker sits inline at the
    // tail of the category row, recovering a full row of vertical space.
    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            if (viewModel.isLoading || viewModel.isHistoricalLoading) && !viewModel.players.isEmpty {
                loadingStatusBar
            }

            HStack(spacing: 10) {
                seasonMenu
                Spacer()
                SearchField(text: $viewModel.searchText)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                CategoryFilter(selectedCategory: $viewModel.selectedCategory)
                    .layoutPriority(1)
                QualifierMenu(selection: $viewModel.qualifierLevel)
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
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

    // Explicit, always-visible sort controls. The old design buried both the
    // metric picker and the direction toggle inside a single Menu wrapping the
    // whole table header — undiscoverable, and the menu was unreliable inside
    // the ScrollView (the "no descending option" report). Now: a "Sort by"
    // chip for the metric, and a direct tap-to-toggle on the header itself.
    private var sortControlsRow: some View {
        HStack(spacing: 8) {
            let metrics = viewModel.availableSortMetrics
            if !metrics.isEmpty {
                Menu {
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
                } label: {
                    HStack(spacing: 4) {
                        Text("Sort by")
                            .font(SavantType.micro)
                            .tracking(0.4)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        Text(viewModel.currentSortMetric ?? viewModel.sortLabel)
                            .font(SavantType.smallBold)
                            .foregroundStyle(SavantPalette.ink)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(SavantPalette.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .menuOrder(.fixed)
            }

            Spacer()

            Button {
                viewModel.toggleSortDirection()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                    Text(viewModel.sortDescending ? "Highest first" : "Lowest first")
                        .font(SavantType.micro)
                        .tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(SavantPalette.savantRed)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var sortHeader: some View {
        // Direct tap-to-toggle (matches Box Score, which works reliably).
        Button {
            viewModel.toggleSortDirection()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            LeaderboardTableHeader(sortDescending: viewModel.sortDescending, sortLabel: viewModel.currentSortMetric ?? viewModel.sortLabel)
        }
        .buttonStyle(.plain)
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
                sortHeader
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
