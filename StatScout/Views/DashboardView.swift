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
                HStack(spacing: 6) {
                    Text(viewModel.currentSortMetric ?? viewModel.sortLabel)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                    Image(systemName: viewModel.sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SavantPalette.savantRed)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(SavantPalette.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sorted by \(viewModel.currentSortMetric ?? viewModel.sortLabel), \(viewModel.sortDescending ? "highest first" : "lowest first")")
            .accessibilityHint("Tap to flip sort direction")
            Spacer(minLength: 0)
            recentToggle
            searchToggle
            filtersMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(viewModel.showingRecent ? viewModel.recentWindow.shortLabel : "Recent")
                    .font(SavantType.micro)
                    .tracking(0.4)
                if !store.isPro {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(viewModel.showingRecent ? .white : SavantPalette.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(viewModel.showingRecent ? SavantPalette.savantRed : SavantPalette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(viewModel.showingRecent ? Color.clear : SavantPalette.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent form")
        .accessibilityValue(viewModel.showingRecent ? viewModel.recentWindow.label : "off")
    }

    /// Window lengths, shown only while Recent is on — a picker for a mode
    /// you're not in is just noise in the header.
    private var recentWindowRow: some View {
        HStack(spacing: 6) {
            ForEach(RecentWindow.allCases) { window in
                Button {
                    viewModel.recentWindow = window
                    Task { await viewModel.loadRecentFormIfNeeded() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(window.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(viewModel.recentWindow == window ? .white : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(viewModel.recentWindow == window ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            if viewModel.isRecentFormLoading {
                ProgressView().scaleEffect(0.6).frame(width: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // Magnifier that expands the inline search row. When a query is active it
    // stays visually "on" so the user knows results are filtered.
    private var searchToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
            if !isSearching { viewModel.searchText = "" }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActiveSearch ? .white : SavantPalette.inkSecondary)
                .frame(width: 30, height: 30)
                .background(isActiveSearch ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isActiveSearch ? Color.clear : SavantPalette.hairline, lineWidth: 0.5))
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
        return form.delta[Self.recentKey(for: label, isPitcher: player.playerType?.lowercased() == "pitcher")]
    }

    /// Season metric label → the rollup's key for it. Pitcher rows read the
    /// opponent-facing variants.
    private static func recentKey(for label: String, isPitcher: Bool) -> String {
        switch label {
        case "xwOBA": return isPitcher ? "opp_xwoba" : "xwoba"
        case "xBA": return isPitcher ? "opp_xba" : "xba"
        case "xSLG": return isPitcher ? "opp_xslg" : "xslg"
        case "xISO": return "xiso"
        case "Barrel%": return isPitcher ? "opp_barrel_pct" : "barrel_pct"
        case "Hard-Hit%": return isPitcher ? "opp_hardhit_pct" : "hardhit_pct"
        case "EV", "Avg EV Against": return isPitcher ? "opp_ev_avg" : "ev_avg"
        case "Max EV", "Max EV Against": return isPitcher ? "opp_ev_max" : "ev_max"
        case "K%": return "k_pct"
        case "BB%": return "bb_pct"
        case "Whiff%": return "whiff_pct"
        case "Chase%": return "chase_pct"
        case "Bat Speed": return "bat_speed"
        case "Swing Length": return "swing_length"
        case "Fastball Velo": return "fb_velo_avg"
        case "Fastball Spin": return "fb_spin_avg"
        default: return label.lowercased()
        }
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
