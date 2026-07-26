import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let players: [Player]
    var season: Int? = nil
    var viewModel: DashboardViewModel? = nil
    var fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])? = nil
    @State private var selectedTab: TeamTab = .percentiles
    @State private var searchText = ""
    @State private var isSearching = false
    // Defaults to All (nil). Hitting used to be the default, which quietly hid
    // most of the roster: a Hitting filter drops every pitcher and also every
    // position player Savant hasn't given hitting percentiles to, so a 40-man
    // roster rendered as ~10 rows with no hint that anyone was missing.
    @State private var selectedCategory: MetricCategory? = nil
    @State private var sortDescending = true
    @State private var lastDefaultedSortKey: String? = nil
    @State private var showingTrial = false
    @State private var rosterSide: RosterSide = .all
    @State private var qualifierLevel: DashboardViewModel.QualifierLevel = .all

    enum TeamTab: String, CaseIterable {
        case percentiles = "Percentiles"
        case roster = "Roster"
    }

    /// Which half of the roster to show. Independent of the metric category —
    /// a user looking for a specific reliever shouldn't have to know that
    /// "Pitching" is also the name of a percentile group.
    enum RosterSide: String, CaseIterable, Identifiable {
        case all = "All"
        case hitters = "Hitters"
        case pitchers = "Pitchers"

        var id: String { rawValue }

        func matches(_ player: Player) -> Bool {
            let isPitcher = player.playerType?.lowercased() == "pitcher"
            switch self {
            case .all: return true
            case .hitters: return !isPitcher
            case .pitchers: return isPitcher
            }
        }
    }

    private var displaySeason: Int {
        season ?? players.compactMap(\.season).max() ?? Calendar.current.component(.year, from: Date())
    }

    private var leaguePlayers: [Player] {
        viewModel?.seasonPlayers ?? []
    }

    private var sortMetric: (label: String, category: MetricCategory)? {
        guard let category = selectedCategory else { return nil }
        for label in priorityMetrics(for: category) {
            if players.contains(where: { p in p.metrics.contains { $0.label == label && $0.category == category } }) {
                return (label, category)
            }
        }
        return nil
    }

    private var sortLabel: String {
        // "All" ranks hitters and pitchers together, which only works on
        // percentile — see LeaderboardTableRow.showsPercentileValue.
        if selectedCategory == nil { return "PCTL" }
        return sortMetric?.label ?? "Top Category"
    }

    private var rowDisplayMetric: (label: String?, category: MetricCategory?) {
        if let m = sortMetric { return (m.label, m.category) }
        if selectedCategory == nil { return ("xwOBA", nil) }
        return (nil, nil)
    }

    private func rawValue(_ player: Player) -> Double? {
        guard let m = sortMetric,
              let metric = player.metrics.first(where: { $0.label == m.label && $0.category == m.category })
        else { return nil }
        return DashboardViewModel.rawNumeric(metric.value)
    }

    private func fallbackPercentile(_ player: Player) -> Int {
        if let category = selectedCategory, let p = player.percentile(for: category) { return p }
        return player.metrics.first(where: { $0.label == "xwOBA" })?.percentile ?? 0
    }

    private var filteredPlayers: [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.displayPosition.localizedCaseInsensitiveContains(searchText)
        }
        let bySide = bySearch.filter { rosterSide.matches($0) }
        let byType = bySide.filter { $0.matchesPlayerType(for: selectedCategory) }
        let byCategory = selectedCategory == nil
            ? byType
            : byType.filter { p in p.metrics.contains { $0.category == selectedCategory } }
        let byQualifier = byCategory.filter { isQualified($0) }
        guard sortMetric != nil else {
            return byQualifier.sorted {
                sortDescending ? fallbackPercentile($0) > fallbackPercentile($1) : fallbackPercentile($0) < fallbackPercentile($1)
            }
        }
        let ranked = byQualifier.filter { rawValue($0) != nil }.sorted {
            let v1 = rawValue($0) ?? 0
            let v2 = rawValue($1) ?? 0
            return sortDescending ? v1 > v2 : v1 < v2
        }
        let tail = byQualifier.filter { rawValue($0) == nil }.sorted {
            fallbackPercentile($0) > fallbackPercentile($1)
        }
        return ranked + tail
    }

    /// Roster-local qualifier. Mirrors DashboardViewModel.isQualified but reads
    /// this view's own picker — the roster defaults to All so a bench bat or a
    /// September call-up still appears.
    private func isQualified(_ player: Player) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            // Savant only assigns percentiles above its own thresholds, so
            // "has a percentile here" is the authoritative signal.
            if let selectedCategory {
                return player.metrics.contains { $0.category == selectedCategory }
            }
            return !player.metrics.isEmpty
        case .any:
            let stats = player.standardStats ?? []
            let value: (Set<String>) -> Double = { labels in
                guard let stat = stats.first(where: { labels.contains($0.label.uppercased()) }) else { return 0 }
                return Double(stat.value.filter { "0123456789.".contains($0) }) ?? 0
            }
            if player.playerType?.lowercased() == "pitcher" {
                return value(["IP"]) >= DashboardViewModel.QualifierLevel.any.minIP
            }
            return value(["PA", "AB"]) >= Double(DashboardViewModel.QualifierLevel.any.minPA)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: displaySeason)

                tabSelector
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                switch selectedTab {
                case .percentiles:
                    percentilesContent
                case .roster:
                    rosterContent
                }

                // Lets content scroll under the floating tab bar so the last
                // rows aren't trapped behind it — matches Dashboard.
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { teamSwitcherMenu }
            if let viewModel {
                // Red season pill draws its own capsule — see StatsView.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { navSeasonMenu(viewModel: viewModel) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { navSeasonMenu(viewModel: viewModel) }
                }
            }
        }
        .onAppear { applyDefaultDirectionIfMetricChanged() }
        .onChange(of: selectedCategory) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        // Season changes through the nav-bar menu rotate the roster data beneath
        // us; re-default the sort direction so the chip never displays a metric
        // the new season doesn't have.
        .onChange(of: displaySeason) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .teamView)
        }
    }

    // MARK: - Tabs

    /// Mirrors the player profile's tab selector — equal-width red pills that
    /// swap the card content below. Two tabs: the team's percentile profile and
    /// its sortable roster.
    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(TeamTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(tab.rawValue)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var percentilesContent: some View {
        VStack(spacing: 12) {
            TeamRankingsCard(
                team: team,
                season: displaySeason,
                players: players,
                leaguePlayers: leaguePlayers,
                fetchTeamGameLogs: fetchTeamGameLogs,
                onUpgradeTap: {
                    // Explicit tap — always answer it; the gate only caps
                    // automatic pop-ups.
                    showingTrial = true
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var rosterContent: some View {
        VStack(spacing: 0) {
            CategoryFilter(selectedCategory: $selectedCategory, showAllOption: true)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if !players.isEmpty {
                sortControlsRow
                if isSearching || !searchText.isEmpty {
                    searchRow
                }
            }

            rosterSection
        }
    }

    private func applyDefaultDirectionIfMetricChanged() {
        let key = sortMetric.map { "\($0.category.rawValue)|\($0.label)" } ?? "—"
        guard key != lastDefaultedSortKey else { return }
        lastDefaultedSortKey = key
        sortDescending = DashboardViewModel.defaultSortDescending(
            label: sortMetric?.label,
            category: sortMetric?.category
        )
    }

    /// Mirrors the Stats tab's sort UI — left-side chip showing the active
    /// metric (tap flips direction), and a magnifying-glass toggle on the right
    /// that expands an inline search row.
    private var sortControlsRow: some View {
        HStack(spacing: 8) {
            Button {
                sortDescending.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Text(sortLabel)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
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
            .accessibilityLabel("Sorted by \(sortLabel), \(sortDescending ? "highest first" : "lowest first")")
            .accessibilityHint("Tap to flip sort direction")

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
                if !isSearching { searchText = "" }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                let active = isSearching || !searchText.isEmpty
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? .white : SavantPalette.inkSecondary)
                    .frame(width: 30, height: 30)
                    .background(active ? SavantPalette.savantRed : SavantPalette.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(active ? Color.clear : SavantPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            rosterFiltersMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    /// Mirrors the Stats page's Filters menu so the two leaderboards behave the
    /// same way. Hitters/Pitchers is the roster-specific addition — it's the
    /// question people actually ask of a team page.
    private var rosterFiltersMenu: some View {
        Menu {
            Section("Show") {
                ForEach(RosterSide.allCases) { side in
                    Button {
                        rosterSide = side
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if side == rosterSide {
                            Label(side.rawValue, systemImage: "checkmark")
                        } else {
                            Text(side.rawValue)
                        }
                    }
                }
            }

            Section("Minimum playing time") {
                ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                    Button {
                        qualifierLevel = level
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if level == qualifierLevel {
                            Label("\(level.rawValue) · \(level.description)", systemImage: "checkmark")
                        } else {
                            Text("\(level.rawValue) · \(level.description)")
                        }
                    }
                }
            }

            Section("Direction") {
                Button {
                    if !sortDescending { sortDescending = true }
                } label: {
                    if sortDescending {
                        Label("Highest first", systemImage: "checkmark")
                    } else {
                        Text("Highest first")
                    }
                }
                Button {
                    if sortDescending { sortDescending = false }
                } label: {
                    if !sortDescending {
                        Label("Lowest first", systemImage: "checkmark")
                    } else {
                        Text("Lowest first")
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
            .foregroundStyle(isFiltered ? .white : SavantPalette.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isFiltered ? SavantPalette.savantRed : SavantPalette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isFiltered ? Color.clear : SavantPalette.hairline, lineWidth: 0.5))
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filters")
    }

    /// Highlights the Filters pill whenever something is actually being hidden,
    /// so a short roster is never a mystery.
    private var isFiltered: Bool {
        rosterSide != .all || qualifierLevel != .all || selectedCategory != nil
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            SearchField(text: $searchText, focusOnAppear: true)
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    searchText = ""
                }
            }
            .font(SavantType.small)
            .foregroundStyle(SavantPalette.savantRed)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var rosterSection: some View {
        VStack(spacing: 0) {
            if players.isEmpty {
                emptyStateView(
                    icon: "person.2.slash",
                    title: "No players tracked",
                    description: "No players are tracked for \(teamFullName(team)) in the \(String(displaySeason)) season."
                )
            } else if filteredPlayers.isEmpty {
                let noCategoryMatch = searchText.isEmpty && selectedCategory != nil
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "No players found",
                    description: noCategoryMatch
                        ? "No players match the selected category for this team."
                        : "Try a different search term."
                )
            } else {
                Button {
                    sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    LeaderboardTableHeader(sortDescending: sortDescending, sortLabel: sortLabel)
                }
                .buttonStyle(.plain)

                ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player,
                            metricLabel: rowDisplayMetric.label,
                            metricCategory: rowDisplayMetric.category,
                            showsPercentileValue: selectedCategory == nil
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
    }

    private func emptyStateView(icon: String, title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        }
        .padding(.vertical, 48)
    }

    /// Team name in the nav title doubles as a switcher menu — tap to jump to
    /// any other team without popping back to the Teams list.
    private var teamSwitcherMenu: some View {
        Menu {
            ForEach(allTeams, id: \.self) { abbr in
                NavigationLink(value: TeamDestination(abbr: abbr)) {
                    HStack {
                        Text(teamFullName(abbr))
                        if abbr == team {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(teamFullName(team))
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Team")
        .accessibilityValue(teamFullName(team))
        .accessibilityHint("Switch to another team")
    }

    private static let allTeamAbbrs: [String] = [
        "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
        "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "OAK",
        "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB", "TEX", "TOR", "WSH"
    ]

    private var allTeams: [String] {
        Self.allTeamAbbrs.sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

    private func navSeasonMenu(viewModel: DashboardViewModel) -> some View {
        Menu {
            ForEach(viewModel.availableSeasons, id: \.self) { season in
                let isLocked = viewModel.isSeasonLocked(season)
                Button {
                    if isLocked {
                        showingTrial = true
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
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(viewModel.selectedSeason))
                    .font(SavantType.smallBold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SavantPalette.savantRed)
            .clipShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Season")
        .accessibilityValue(String(viewModel.selectedSeason))
    }

    private func priorityMetrics(for category: MetricCategory) -> [String] {
        switch category {
        case .hitting: return ["xwOBA", "xSLG", "xBA"]
        case .pitching: return ["xwOBA", "K%", "Barrel%", "Whiff%", "Chase%"]
        case .fielding: return ["Range (OAA)", "Arm Strength", "Arm Value"]
        case .running: return ["Sprint Speed"]
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TeamView(
            team: "NYY",
            players: SampleData.players.filter { $0.team == "NYY" },
            season: 2026
        )
    }
}
#endif
