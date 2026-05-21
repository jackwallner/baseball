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
                        activeSortChip
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

    // Two-row header: season + search up top, category + Filters menu below.
    // The Filters menu hides qualifier and sort controls behind one button so
    // the surface stays calm. Data freshness sits above as a thin caption so
    // users can see at a glance how stale the leaderboard is.
    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            freshnessStrip

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

            CategoryFilter(selectedCategory: $viewModel.selectedCategory)
                .padding(.horizontal, 12)
        }
        .padding(.top, 4)
    }

    private var freshnessStrip: some View {
        HStack(spacing: 6) {
            Spacer()
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SavantPalette.inkTertiary)
            Text(freshnessLabel)
                .font(SavantType.micro)
                .tracking(0.3)
                .foregroundStyle(SavantPalette.inkTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Data \(freshnessLabel)")
    }

    private var freshnessLabel: String {
        guard let lastUpdated = viewModel.lastUpdated else { return "Data not yet loaded" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: lastUpdated, relativeTo: .now))"
    }

    // Single button that hosts every secondary control — qualifier scope plus
    // the active sort metric and direction. Keeps the header to two visible
    // rows while still putting the controls one tap away.
    private var filtersMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(viewModel.availableSortMetrics, id: \.self) { metric in
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

            Section("Direction") {
                Button {
                    if !viewModel.sortDescending { viewModel.toggleSortDirection() }
                } label: {
                    if viewModel.sortDescending {
                        Label("Highest first", systemImage: "checkmark")
                    } else {
                        Text("Highest first")
                    }
                }
                Button {
                    if viewModel.sortDescending { viewModel.toggleSortDirection() }
                } label: {
                    if !viewModel.sortDescending {
                        Label("Lowest first", systemImage: "checkmark")
                    } else {
                        Text("Lowest first")
                    }
                }
            }

            Section("Qualifier") {
                ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                    Button {
                        viewModel.qualifierLevel = level
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if level == viewModel.qualifierLevel {
                            Label("\(level.rawValue) · \(level.description)", systemImage: "checkmark")
                        } else {
                            Text("\(level.rawValue) · \(level.description)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("Filters")
                    .font(SavantType.micro)
                    .tracking(0.4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(SavantPalette.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(SavantPalette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filters")
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

    // Compact, centered indicator of the active sort, with the Filters menu
    // sitting at the trailing edge. Picker + qualifier live in the menu;
    // tapping the chip flips the direction inline.
    private var activeSortChip: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                viewModel.toggleSortDirection()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Text("Sorted by")
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkSecondary)
                    Text(viewModel.currentSortMetric ?? viewModel.sortLabel)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                    Image(systemName: viewModel.sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SavantPalette.savantRed)
                    Text(viewModel.sortDescending ? "Highest first" : "Lowest first")
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(SavantPalette.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            filtersMenu
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
