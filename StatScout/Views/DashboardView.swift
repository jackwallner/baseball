import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    /// Set when this board is hosted by `StatsView`, which owns the choice of
    /// board and therefore has to be reachable from this board's own controls.
    var boardBindings: StatsBoardBindings? = nil
    /// Set when a tab host can move the user to Trends. The postseason card's
    /// subscriber variant sends them there instead of pitching an upgrade, so
    /// without a route it has nothing to offer and stays hidden.
    var onOpenTrends: (() -> Void)? = nil
    @AppStorage(PostseasonCampaign.storageKey) private var seenPostseason = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
                            teamResults
                        }
                        postseasonSection
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
                    dataThrough: viewModel.dataThrough,
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
        // Every offer that opens from this screen (the footer upgrade) is a
        // contextual pitch, so it gets the low-friction sheet
        // whose CTA buys the yearly plan in place. The full plan picker stays
        // one quiet "See all plans" tap away inside it.
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    /// The postseason card. Inline in the scroll content, above the board, and
    /// only outside an active search, where it would otherwise push the team
    /// results the user is reading off the screen.
    @ViewBuilder
    private var postseasonSection: some View {
        if !isActiveSearch, let creative = postseasonDecision.creative {
            PostseasonCard(
                creative: creative,
                onUpgrade: { paywallTrigger = .postseason },
                onOpenPostseason: {
                    viewModel.selectPhase(.postseason)
                    onOpenTrends?()
                },
                onDismiss: { seenPostseason = PostseasonCampaign.identifier }
            )
        }
    }

    private var postseasonDecision: PostseasonDecision {
        // The subscriber variant is only worth showing where the postseason
        // boards are one tap away, so a host that can't route there gets no
        // card at all.
        if store.isPro && onOpenTrends == nil { return .hidden }
        return PostseasonCampaign.decision(
            postseasonThrough: viewModel.postseasonThrough,
            hasCompletedOnboarding: hasCompletedOnboarding,
            seenCampaign: seenPostseason,
            customerStateResolved: store.customerInfo != nil,
            isPro: store.isPro
        )
    }

    private var aboutFooter: some View {
        VStack(spacing: 8) {
            if !store.isPro {
                Button(action: { paywallTrigger = store.defaultUpgradeTrigger }) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                        Text(store.upgradeCTALabel)
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

    // Category tabs are the only persistent header row now, season lives in
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

    // Stat, direction, search, and the View menu that holds what's left. The
    // stat is the pill and only the pill: it's the same control Trends puts in
    // the same place, so the two boards are configured the same way rather than
    // looking the same and behaving differently.
    //
    // The column header in the table acts as the live sort indicator, so the
    // controls stay terse, no "Sorted by"/"Highest first" narration.
    private var activeSortChip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let boardBindings {
                        StatsBoardStatPicker(viewModel: viewModel, bindings: boardBindings)
                    }
                    SortDirectionButton(
                        descending: viewModel.sortDescending,
                        statLabel: viewModel.currentSortMetric ?? viewModel.sortLabel
                    ) {
                        viewModel.toggleSortDirection()
                    }
                    // Position moved into the View menu, but an active filter
                    // that only shows up inside a closed menu is an invisible
                    // filter, so the chip comes back as its own indicator once
                    // the board is actually narrowed.
                    if viewModel.positionFilterApplies, viewModel.positionFilter != .all {
                        positionMenu
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 2)
                // Room for the capsule strokes, which a tight frame would clip.
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Fades the chip that's mid-scroll at the boundary instead of
            // guillotining it, which reads as "there's more here" rather than
            // as a clipped control.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            searchToggle
            if let boardBindings {
                StatsViewMenu(
                    viewModel: viewModel,
                    board: boardBindings.$board
                )

            }
        }
        .padding(.trailing, 12)
        .frame(height: SavantControl.height + 2)
        .padding(.top, 8)
    }

    /// The active position filter, as a chip you can tap to change or clear.
    /// Only drawn when a filter is on; picking one starts in the View menu.
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
                isActive: true
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Position")
        .accessibilityValue(viewModel.positionFilter.label)
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

    /// Clubs matching the query, above the filtered players.
    ///
    /// The field has always said "players or teams", and a team query only ever
    /// narrowed the list of players. Someone typing "Mariners" is usually after
    /// Seattle, so the team itself is now a result: one tap to the team page,
    /// with the roster still filtered underneath if that's what they wanted.
    @ViewBuilder
    private var teamResults: some View {
        let teams = viewModel.searchedTeams
        if !teams.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(teams.prefix(3).enumerated()), id: \.element) { index, team in
                    if index > 0 {
                        Rectangle()
                            .fill(SavantPalette.divider)
                            .frame(height: SavantGeo.hairline)
                    }
                    NavigationLink(value: TeamDestination(abbr: team)) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(MLBTeamColor.color(team))
                                    .frame(width: 28, height: 28)
                                Text(team)
                                    .font(SavantFont.condensed(10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text(teamDisplayName(team))
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                            Text("TEAM PAGE")
                                .font(SavantType.micro)
                                .tracking(0.5)
                                .foregroundStyle(SavantPalette.inkTertiary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                        .padding(.horizontal, SavantGeo.padInline)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        }
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
        .padding(.top, 8)
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
