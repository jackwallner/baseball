import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @State private var showingAbout = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var isSearching = false

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    unifiedControlBar
                    if !viewModel.players.isEmpty {
                        activeSortChip
                        if isSearching || !viewModel.searchText.isEmpty {
                            searchRow
                        }
                        if viewModel.showingRecent {
                            recentWindowRow
                        }
                    }
                    leaderboardSection
                    if !viewModel.players.isEmpty {
                        aboutFooter
                    }
                    // Lets the leaderboard scroll through the floating tab bar instead of
                    // stopping above it with canvas gray showing underneath the glass pill.
                    Color.clear.frame(height: 88)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .scrollClipDisabled()
            .refreshable {
                await viewModel.load()
            }
            if viewModel.isLoading && viewModel.players.isEmpty {
                loadingCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SavantPalette.canvas)
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView(
                    lastUpdated: viewModel.lastUpdated,
                    onRequestReview: {
                        showingAbout = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                        }
                    }
                )
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
                        Text("Unlock StatScout+")
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

    // Category tabs are the only persistent header row now — season lives in
    // the nav bar, search collapses behind an icon, and sort/qualifier sit in
    // the controls row below. A loading strip animates in above the tabs only
    // while data is refreshing, so the header never reserves empty space.
    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            if (viewModel.isLoading || viewModel.isHistoricalLoading) && !viewModel.players.isEmpty {
                loadingStatusBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            CategoryFilter(selectedCategory: $viewModel.selectedCategory)
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
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
            SavantChip(
                title: "Filters",
                systemImage: "line.3.horizontal.decrease.circle",
                trailing: .chevron,
                isActive: viewModel.qualifierLevel != .qualified
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filters")
    }

    // Compact sort chip on the left (tap to flip direction), then a search
    // toggle and the Filters menu trailing. The column header in the table
    // acts as the live sort indicator, so the chip stays terse — no
    // "Sorted by"/"Highest first" narration.
    private var activeSortChip: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleSortDirection()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                SavantChip(
                    title: viewModel.currentSortMetric ?? viewModel.sortLabel,
                    trailing: .sortArrow(descending: viewModel.sortDescending)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sorted by \(viewModel.currentSortMetric ?? viewModel.sortLabel), \(viewModel.sortDescending ? "highest first" : "lowest first")")
            .accessibilityHint("Tap to flip sort direction")
            if viewModel.positionFilterApplies {
                positionMenu
            }
            Spacer(minLength: 0)
            recentToggle
            searchToggle
            filtersMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Narrows the board to one position, or to the infield / outfield as a
    /// group. Sits beside the sort chip because it answers the same shape of
    /// question — which slice of the league am I ranking — where the trailing
    /// chips are modes and search.
    ///
    /// Hidden on the pitching board, where every player is a P.
    private var positionMenu: some View {
        Menu {
            ForEach(viewModel.availablePositionFilters) { option in
                Button {
                    viewModel.positionFilter = option
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if option == viewModel.positionFilter {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            SavantChip(
                title: viewModel.positionFilter.chipLabel,
                systemImage: "figure.baseball",
                trailing: .chevron,
                isActive: viewModel.positionFilter != .all
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Position")
        .accessibilityValue(viewModel.positionFilter.label)
    }

    /// Flips the leaderboard from season totals to a rolling window, and (when
    /// active) exposes the window length. Reads the pre-aggregated
    /// player_recent_form table, so switching is a single small fetch rather
    /// than an on-device aggregation of the whole league's game logs.
    ///
    /// StatScout+ only: a free tap pitches the trial instead of loading, since
    /// "who's hot right now" is the thing the subscription is actually for.
    private var recentToggle: some View {
        Button {
            if store.isPro {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showingRecent.toggle()
                }
                if viewModel.showingRecent {
                    Task { await viewModel.loadRecentFormIfNeeded() }
                }
            } else {
                paywallTrigger = .recentForm
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            SavantChip(
                // "Last 15", not "15d" — the same wording the window picker
                // right below it and every other screen uses.
                title: viewModel.showingRecent ? viewModel.recentWindow.label : "Recent",
                systemImage: "flame.fill",
                isActive: viewModel.showingRecent,
                isLocked: !store.isPro
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent form")
        .accessibilityValue(viewModel.showingRecent ? viewModel.recentWindow.label : "off")
    }

    /// Window lengths, shown only while Recent is on — a picker for a mode
    /// you're not in is just noise in the header.
    private var recentWindowRow: some View {
        HStack(spacing: 6) {
            SavantSegmented(
                segments: RecentWindow.allCases.map { .init(value: $0, label: $0.label) },
                selection: $viewModel.recentWindow
            )
            if viewModel.isRecentFormLoading {
                ProgressView().scaleEffect(0.6).frame(width: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onChange(of: viewModel.recentWindow) { _, _ in
            Task { await viewModel.loadRecentFormIfNeeded() }
        }
    }

    // Magnifier that expands the inline search row. When a query is active it
    // stays visually "on" so the user knows results are filtered.
    private var searchToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
            if !isSearching { viewModel.searchText = "" }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            SavantChip(systemImage: "magnifyingglass", isActive: isActiveSearch)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }

    private var isActiveSearch: Bool { isSearching || !viewModel.searchText.isEmpty }

    private var searchRow: some View {
        HStack(spacing: 8) {
            SearchField(text: $viewModel.searchText, focusOnAppear: true)
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    viewModel.searchText = ""
                }
            }
            .font(SavantType.small)
            .foregroundStyle(SavantPalette.savantRed)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
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
                                metricCategory: sortMetric.category,
                                trendDelta: trendDelta(for: player, metric: sortMetric.label),
                                trendDecimals: sortMetric.label.map { RecentMetricKey.decimals(for: $0) } ?? 3,
                                trendLocked: !store.isPro
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
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Recent-vs-prior change in the displayed metric for one row.
    ///
    /// Free users get a value too — blurred by `TrendArrow` — so the column
    /// reads as "there is information here" rather than as an empty gutter.
    /// Nothing is shown at all until a window is loaded, which only happens
    /// once Recent has been switched on.
    private func trendDelta(for player: Player, metric label: String?) -> Double? {
        guard let label, let form = viewModel.recentForm(for: player.playerId) else { return nil }
        let key = RecentMetricKey.key(
            for: label,
            isPitcher: player.playerType?.lowercased() == "pitcher"
        )
        return form.delta[key]
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
