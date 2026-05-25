import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let players: [Player]
    var season: Int? = nil
    var viewModel: DashboardViewModel? = nil
    var fetchTeamGameLogs: ((String, Int, Date) async throws -> [PlayerGameLog])? = nil
    @State private var searchText = ""
    @State private var isSearching = false
    // Default to Hitting so the roster always shows a meaningful sort metric.
    @State private var selectedCategory: MetricCategory? = .hitting
    @State private var sortDescending = true
    @State private var lastDefaultedSortKey: String? = nil
    @State private var showingPaywall = false

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

    private var filteredPlayers: [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        let byType = bySearch.filter { $0.matchesPlayerType(for: selectedCategory) }
        let byCategory = selectedCategory == nil
            ? byType
            : byType.filter { p in p.metrics.contains { $0.category == selectedCategory } }
        guard sortMetric != nil else {
            return byCategory.sorted {
                sortDescending ? fallbackPercentile($0) > fallbackPercentile($1) : fallbackPercentile($0) < fallbackPercentile($1)
            }
        }
        let ranked = byCategory.filter { rawValue($0) != nil }.sorted {
            let v1 = rawValue($0) ?? 0
            let v2 = rawValue($1) ?? 0
            return sortDescending ? v1 > v2 : v1 < v2
        }
        let tail = byCategory.filter { rawValue($0) == nil }.sorted {
            fallbackPercentile($0) > fallbackPercentile($1)
        }
        return ranked + tail
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: displaySeason)

                TeamFormCard(
                    team: team,
                    season: displaySeason,
                    leaguePlayers: leaguePlayers,
                    fetchTeamGameLogs: fetchTeamGameLogs,
                    onUpgradeTap: {
                        if PaywallGate.shared.shouldPresent(.teamView) { showingPaywall = true }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                TeamAveragePlayerCard(
                    team: team,
                    players: players,
                    leaguePlayers: leaguePlayers
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                CategoryFilter(selectedCategory: $selectedCategory)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if !players.isEmpty {
                    sortControlsRow
                    if isSearching || !searchText.isEmpty {
                        searchRow
                    }
                }

                rosterSection

                // Lets the roster scroll under the floating tab bar so the
                // last rows aren't trapped behind it — matches Dashboard.
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
                ToolbarItem(placement: .topBarTrailing) { navSeasonMenu(viewModel: viewModel) }
            }
        }
        .onAppear { applyDefaultDirectionIfMetricChanged() }
        .onChange(of: selectedCategory) { _, _ in applyDefaultDirectionIfMetricChanged() }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: .teamView)
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
    /// metric (tap flips direction), and a magnifying-glass toggle on the
    /// right that expands an inline search row. Replaces the old SavantSectionBar
    /// roster header which read as clunky vs. the other tabs.
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
                            metricCategory: rowDisplayMetric.category
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
        .padding(.top, 8)
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
    /// any other team without popping back to the Teams list. Mirrors the
    /// Weather-app style mode dropdown used on the Stats tab.
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
                        if PaywallGate.shared.shouldPresent(.teamView) { showingPaywall = true }
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

// MARK: - Team Average ("team-as-a-player") Card

/// Aggregates the roster's season metrics into one synthetic "player" so you
/// can see the team's overall offensive and pitching profile as percentile
/// bars on the league ruler. Rate stats (xwOBA, Barrel%, K%, …) are PA-weighted
/// for batters and IP-weighted for pitchers — falling back to equal weight
/// when those workload stats aren't in the feed.
struct TeamAveragePlayerCard: View {
    let team: String
    let players: [Player]
    let leaguePlayers: [Player]

    enum Side: String, CaseIterable, Identifiable {
        case batting, pitching
        var id: String { rawValue }
        var label: String { self == .batting ? "Hitting" : "Pitching" }
        var category: MetricCategory { self == .batting ? .hitting : .pitching }
        var playerType: String { self == .batting ? "batter" : "pitcher" }
    }

    @State private var side: Side = .batting
    @State private var batterCurves: LeaguePercentileCurves?
    @State private var pitcherCurves: LeaguePercentileCurves?

    private static let battingMetrics: [String] = ["xwOBA", "Barrel%", "Hard-Hit%", "EV", "K%", "BB%"]
    private static let pitchingMetrics: [String] = ["xwOBA", "K%", "BB%", "Whiff%", "Barrel%", "Hard-Hit%"]

    var body: some View {
        VStack(spacing: 0) {
            header
            barList
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
    }

    private func rebuildCurves() {
        let labels = Array(Set(Self.battingMetrics + Self.pitchingMetrics))
        batterCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "batter", labels: labels)
        pitcherCurves = LeaguePercentileCurves(players: leaguePlayers, playerType: "pitcher", labels: labels)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SavantPalette.savantRed)
                Text("TEAM AVERAGE")
                    .font(SavantType.micro)
                    .tracking(0.6)
                    .foregroundStyle(SavantPalette.inkSecondary)
                Spacer()
                Text("WEIGHTED BY \(side == .pitching ? "IP" : "PA")")
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .padding(.horizontal, SavantGeo.padInline)
            .padding(.top, 12)

            sidePicker
                .padding(.horizontal, SavantGeo.padInline)
                .padding(.bottom, 10)
        }
        .background(SavantPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
    }

    private var sidePicker: some View {
        HStack(spacing: 0) {
            ForEach(Side.allCases) { s in
                Button {
                    side = s
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(s.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(side == s ? SavantPalette.ink : SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(
                            Rectangle()
                                .fill(side == s ? SavantPalette.savantRed : Color.clear)
                                .frame(height: 2)
                                .padding(.top, 32),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var barList: some View {
        let rows = aggregateRows()
        if rows.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 22))
                    .foregroundStyle(SavantPalette.inkTertiary)
                Text("Not enough \(side.label.lowercased()) data to aggregate")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                    MetricBar(metric: metric)
                        .padding(.horizontal, SavantGeo.padCard)
                        .padding(.vertical, 12)
                        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                            alignment: .bottom
                        )
                }
            }
        }
    }

    /// One bar per spec metric. For each metric we pull every roster player's
    /// raw season value, weight by PA (batters) / IP (pitchers), take the
    /// weighted mean, then map onto the league curve so the bar shares the
    /// same ruler as individual players' season bars.
    private func aggregateRows() -> [Metric] {
        let curves = side == .pitching ? pitcherCurves : batterCurves
        let labels = side == .pitching ? Self.pitchingMetrics : Self.battingMetrics
        let pool = players.filter { ($0.playerType ?? "") == side.playerType }
        guard !pool.isEmpty, let curves else { return [] }

        return labels.compactMap { label -> Metric? in
            var weightedSum = 0.0
            var weightTotal = 0.0
            for player in pool {
                guard let m = player.metrics.first(where: { $0.label == label && $0.category == side.category }),
                      let v = DashboardViewModel.rawNumeric(m.value) else { continue }
                let w = workload(player) ?? 1.0
                weightedSum += v * w
                weightTotal += w
            }
            guard weightTotal > 0 else { return nil }
            let avg = weightedSum / weightTotal
            guard let pct = curves.curve(for: label)?.percentile(for: avg) else { return nil }
            return Metric(
                id: "teamavg-\(label)",
                label: label,
                value: formattedValue(avg, label: label),
                percentile: pct,
                category: side.category
            )
        }
    }

    /// Workload for weighting — PA for batters, IP for pitchers. Read from the
    /// standard-stats block when present; nil falls back to equal weighting.
    private func workload(_ player: Player) -> Double? {
        let key = side == .pitching ? "IP" : "PA"
        guard let raw = player.standardStats?.first(where: { $0.label == key })?.value else { return nil }
        return DashboardViewModel.rawNumeric(raw)
    }

    private func formattedValue(_ v: Double, label: String) -> String {
        if label == "xwOBA" { return String(format: "%.3f", v) }
        if label == "EV"     { return String(format: "%.1f mph", v) }
        if label.hasSuffix("%") { return String(format: "%.1f%%", v) }
        return String(format: "%.2f", v)
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
