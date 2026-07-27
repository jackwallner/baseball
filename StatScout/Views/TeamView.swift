import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let players: [Player]
    var season: Int? = nil
    var viewModel: DashboardViewModel? = nil
    var fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])? = nil
    @State private var selectedTab: TeamTab = .advanced
    @State private var searchText = ""
    @State private var isSearching = false
    // Which percentile group the list ranks by, scoped to the active side.
    // This no longer decides roster membership — it used to, which quietly hid
    // most of the team: a Hitting filter dropped every pitcher and also every
    // position player Savant hasn't given hitting percentiles to, so a 40-man
    // roster rendered as ~10 rows with no hint that anyone was missing.
    @State private var selectedCategory: MetricCategory? = .hitting
    @State private var sortDescending = true
    @State private var lastDefaultedSortKey: String? = nil
    @State private var showingTrial = false
    @State private var trialTrigger: PaywallTrigger?
    @State private var rosterSide: RosterSide = .hitters
    @State private var qualifierLevel: DashboardViewModel.QualifierLevel = .all
    /// Whether the roster ranks on the season line or on a rolling window.
    @State private var rosterMode: RosterMode = .season
    @State private var rosterWindow: RecentWindow = .fortnight
    /// An explicit "Sort by" pick from the Filters menu. Nil falls back to the
    /// category's headline metric, which is what the list opens on.
    @State private var userSortLabel: String?

    /// "Advanced", not "Percentiles": the Standard tab draws percentile bars
    /// too, so naming one of them after the bars said nothing about what
    /// separates them. What separates them is the vocabulary — Statcast's
    /// expected stats on one side, the box score on the other.
    enum TeamTab: String, CaseIterable {
        case advanced = "Advanced"
        case standard = "Standard"
        case roster = "Roster"
    }

    /// Season totals or a rolling window, the same pair the team cards and the
    /// player page offer.
    enum RosterMode: String, CaseIterable, Identifiable {
        case season = "Season"
        case recent = "Recent"

        var id: String { rawValue }
    }

    /// Which half of the roster to show. Deliberately never "both": raw stats
    /// run in opposite directions for the two sides (a low xwOBA is good for a
    /// pitcher, bad for a hitter), so a single combined ranking can't present a
    /// coherent value column. Two-way players appear under both.
    enum RosterSide: String, CaseIterable, Identifiable {
        case hitters = "Hitters"
        case pitchers = "Pitchers"

        var id: String { rawValue }

        var categories: [MetricCategory] {
            switch self {
            case .hitters: return [.hitting, .fielding, .running]
            case .pitchers: return [.pitching]
            }
        }

        func matches(_ player: Player) -> Bool {
            switch player.playerType?.lowercased() {
            case "pitcher": return self == .pitchers
            case "two_way": return true
            default: return self == .hitters
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
        if let userSortLabel, availableSortLabels.contains(userSortLabel) {
            return (userSortLabel, category)
        }
        for label in priorityMetrics(for: category) {
            if players.contains(where: { p in p.metrics.contains { $0.label == label && $0.category == category } }) {
                return (label, category)
            }
        }
        return nil
    }

    /// Every metric this roster actually carries for the active category, in the
    /// same priority order the rest of the app uses. Feeds the Filters menu's
    /// "Sort by" section — the Stats leaderboard has always let you choose the
    /// column; the roster ranked on a metric it picked for you.
    private var availableSortLabels: [String] {
        guard let category = selectedCategory else { return [] }
        let present = Set(players.flatMap { p in
            p.metrics.filter { $0.category == category }.map(\.label)
        })
        let ordered = category.metricPriorityOrder.filter { present.contains($0) }
        return ordered + present.subtracting(category.metricPriorityOrder).sorted()
    }

    private var sortLabel: String {
        if selectedCategory == nil { return "xwOBA" }
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

    // MARK: - Recent window

    /// This player's rolling window for the sorted metric, when one is loaded.
    private func recentForm(_ player: Player) -> RecentForm? {
        viewModel?.recentForm(for: player.playerId, window: rosterWindow)
    }

    private func recentKey(_ player: Player) -> String? {
        guard let label = sortMetric?.label else { return nil }
        return RecentMetricKey.key(
            for: label,
            isPitcher: player.playerType?.lowercased() == "pitcher"
        )
    }

    private func recentValue(_ player: Player) -> Double? {
        guard let key = recentKey(player) else { return nil }
        return recentForm(player)?.metrics[key]
    }

    private func recentDelta(_ player: Player) -> Double? {
        guard let key = recentKey(player) else { return nil }
        return recentForm(player)?.delta[key]
    }

    /// The window value for the ranked column, or an em dash for a player who
    /// hasn't played inside it.
    private func recentValueText(_ player: Player) -> String {
        guard let label = sortMetric?.label, let value = recentValue(player) else { return "—" }
        return RecentMetricKey.format(value, label: label)
    }

    /// True once the window this roster is ranking on has arrived.
    private var hasRecentData: Bool {
        viewModel?.recentFormByWindow[rosterWindow.rawValue] != nil
    }

    private var isRosterRecent: Bool {
        rosterMode == .recent && store.isPro
    }

    private var filteredPlayers: [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.displayPosition.localizedCaseInsensitiveContains(searchText)
        }
        // Side is the only membership rule. Deliberately no filter on "has a
        // percentile in the selected category": Savant withholds percentiles
        // below its qualifying thresholds, so filtering on them silently drops
        // bench bats, call-ups and low-inning relievers from their own team's
        // roster. They still have standard stats worth showing, and they sort
        // to the tail with an em dash in the metric column.
        let bySide = bySearch.filter { rosterSide.matches($0) }
        let byQualifier = bySide.filter { isQualified($0) }
        // Recent mode ranks on the rolling window instead of the season number.
        // Players with no games in the window keep their place on the roster but
        // fall to the tail — a bench bat you're checking on shouldn't vanish
        // because he hasn't started in a fortnight.
        if isRosterRecent, sortMetric != nil {
            let ranked = byQualifier.filter { recentValue($0) != nil }.sorted {
                let v1 = recentValue($0) ?? 0
                let v2 = recentValue($1) ?? 0
                return sortDescending ? v1 > v2 : v1 < v2
            }
            let tail = byQualifier.filter { recentValue($0) == nil }.sorted {
                fallbackPercentile($0) > fallbackPercentile($1)
            }
            return ranked + tail
        }
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
                // No identity strip: the nav bar already shows the team name
                // (as the switcher) and the season pill, so it was repeating
                // both and pushing the first real stat past halfway down.
                tabSelector
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                switch selectedTab {
                case .advanced:
                    advancedContent
                case .standard:
                    standardContent
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
            userSortLabel = nil
            applyDefaultDirectionIfMetricChanged()
        }
        // Season changes through the nav-bar menu rotate the roster data beneath
        // us; re-default the sort direction so the chip never displays a metric
        // the new season doesn't have.
        .onChange(of: displaySeason) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        // Only fetches once per window per season — the view model caches, and
        // free users never reach recent mode at all.
        .task(id: "\(rosterMode.rawValue)-\(rosterWindow.rawValue)-\(displaySeason)-\(store.isPro)") {
            guard isRosterRecent else { return }
            await viewModel?.loadRecentFormIfNeeded(window: rosterWindow)
        }
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .teamView)
        }
        .sheet(item: $trialTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
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
                        // Three tabs where there were two, so the label has to
                        // give a little rather than truncate on a small phone.
                        .font(SavantType.smallBold)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
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

    private var advancedContent: some View {
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

    private var standardContent: some View {
        TeamStandardCard(
            team: team,
            season: displaySeason,
            players: players,
            leaguePlayers: leaguePlayers,
            fetchTeamGameLogs: fetchTeamGameLogs,
            onUpgradeTap: { showingTrial = true }
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var rosterContent: some View {
        VStack(spacing: 0) {
            // Side and season/recent share a row, sized so all four capsules
            // come out the same width — the same control pair the Advanced and
            // Standard cards carry above.
            SavantPickerRow {
                sidePicker.segmentCount(RosterSide.allCases.count)
                rosterModePicker.segmentCount(RosterMode.allCases.count)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if isRosterRecent {
                SavantSegmented(
                    segments: RecentWindow.allCases.map { .init(value: $0, label: $0.label) },
                    selection: $rosterWindow
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            // Only the categories that mean anything for the active side, so a
            // pitcher list never offers a Running tab that would empty it.
            if rosterSide.categories.count > 1 {
                SavantTabs(
                    tabs: rosterSide.categories.map(\.rawValue),
                    selected: Binding(
                        get: { (selectedCategory ?? rosterSide.categories[0]).rawValue },
                        set: { newValue in
                            selectedCategory = MetricCategory.allCases.first { $0.rawValue == newValue }
                        }
                    )
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

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
                SavantChip(
                    title: sortLabel,
                    trailing: .sortArrow(descending: sortDescending)
                )
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
                SavantChip(
                    systemImage: "magnifyingglass",
                    isActive: isSearching || !searchText.isEmpty
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            rosterFiltersMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    /// Hitters / Pitchers as a first-class control rather than a menu item —
    /// it's the primary question asked of a team page, and it decides what the
    /// whole list means.
    private var sidePicker: some View {
        SavantSegmented(
            segments: RosterSide.allCases.map { .init(value: $0, label: $0.rawValue) },
            selection: $rosterSide
        )
        .onChange(of: rosterSide) { _, side in
            selectedCategory = side.categories[0]
            userSortLabel = nil
        }
    }

    /// Season or the rolling window, locked for free users. Ranking the roster
    /// by the last 7 / 15 / 30 days is the team-page version of what the Trends
    /// board does for the league: who on *this* club is actually going well now.
    private var rosterModePicker: some View {
        SavantSegmented(
            segments: RosterMode.allCases.map {
                .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 == .recent)
            },
            selection: $rosterMode,
            onLockedTap: { _ in trialTrigger = .recentForm }
        )
    }

    /// Mirrors the Stats page's Filters menu so the two leaderboards behave the
    /// same way.
    private var rosterFiltersMenu: some View {
        Menu {
            if !availableSortLabels.isEmpty {
                Section("Sort by") {
                    ForEach(availableSortLabels, id: \.self) { label in
                        Button {
                            userSortLabel = label
                            // Chase% and xwOBA don't want the same arrow, so a
                            // new column starts pointed the useful way.
                            applyDefaultDirectionIfMetricChanged()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            if label == sortMetric?.label {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
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
            SavantChip(
                title: "Filters",
                systemImage: "line.3.horizontal.decrease.circle",
                trailing: .chevron,
                isActive: isFiltered
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filters")
    }

    /// Highlights the Filters pill whenever something is actually being hidden,
    /// so a short roster is never a mystery.
    private var isFiltered: Bool {
        qualifierLevel != .all
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
            } else if isRosterRecent && !hasRecentData {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.75)
                    Text("Loading the last \(rosterWindow.rawValue) days…")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                Button {
                    sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    LeaderboardTableHeader(
                        sortDescending: sortDescending,
                        sortLabel: isRosterRecent ? "\(sortLabel) · \(rosterWindow.rawValue)d" : sortLabel
                    )
                }
                .buttonStyle(.plain)

                ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player,
                            metricLabel: rowDisplayMetric.label,
                            metricCategory: rowDisplayMetric.category,
                            trendDelta: isRosterRecent ? recentDelta(player) : nil,
                            trendDecimals: rowDisplayMetric.label.map { RecentMetricKey.decimals(for: $0) } ?? 3,
                            valueOverride: isRosterRecent ? recentValueText(player) : nil
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

    /// The same pill + menu the Stats and Teams tabs use.
    private func navSeasonMenu(viewModel: DashboardViewModel) -> some View {
        SeasonMenu(
            seasons: viewModel.availableSeasons,
            selected: viewModel.selectedSeason,
            isLocked: { viewModel.isSeasonLocked($0) },
            onSelect: { season in
                if viewModel.isSeasonLocked(season) {
                    trialTrigger = .lockedSeason(season)
                } else {
                    viewModel.selectedSeason = season
                }
            }
        ) {
            SavantNavPill(systemImage: "calendar", title: String(viewModel.selectedSeason))
        }
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
