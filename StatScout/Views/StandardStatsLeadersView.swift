import SwiftUI

/// The traditional-stat leaderboard, split by the same four categories the
/// Statcast board uses.
///
/// It used to offer Hitting and Pitching only, drawn as two big filled buttons,
/// so switching Advanced → Standard replaced a four-tab underlined header with a
/// two-button row and the page appeared to become a different screen. The mode
/// chip changes the vocabulary, not the furniture: same tabs, same order, same
/// control. Fielding and Running are the categories that had no traditional
/// counterpart before, and now do, errors and the glove line for one, the
/// stolen-base line for the other.
struct StandardStatsLeadersView: View {
    @EnvironmentObject private var store: StoreService
    let players: [Player]
    /// The stat being ranked, and the category whose tab is showing. Owned
    /// above this view: inside `StatsView` they're shared with the Statcast
    /// board so switching vocabularies doesn't reshuffle the header, and on the
    /// pushed drill-down screen `StandardStatsLeaderboardScreen` holds them.
    @Binding var selectedStat: String
    @Binding var selectedCategory: MetricCategory
    @Binding var sortDescending: Bool
    /// Set when arrived at by tapping a specific stat on a player profile, so
    /// the leaderboard opens on the stat that was tapped rather than AVG.
    var season: Int? = nil
    /// Present when this board is hosted by `StatsView`, which draws the shared
    /// View menu in this board's own control row.
    var boardBindings: StatsBoardBindings? = nil
    var viewModel: DashboardViewModel? = nil
    /// True while a past season's roster is still being pulled. Without it,
    /// picking 2019 from the drill-down's season pill shows "no players" for the
    /// second or two before the history lands, which reads as "no data".
    var isLoadingSeason: Bool = false

    /// Available stats per category.
    var availableStats: [String] { StandardStatCatalog.stats(for: selectedCategory) }

    /// Rates that are computed here rather than stored, because the pipeline
    /// ships the components and not the ratio.
    private static let derivedStats: Set<String> = ["SB%"]

    // Filter players who have the selected stat
    var filteredPlayers: [Player] {
        // Measured once for the whole board, not per row: it's a league-wide
        // fact, and asking each player for it would make the filter quadratic.
        let teamGames = teamGamesPlayed
        return players.filter { player in
            guard let stats = player.standardStats else { return false }
            guard matchesPlayerType(player: player) else { return false }
            guard hasPlayedEnough(player, stats: stats) else { return false }
            guard meetsRateQualifier(player, stats: stats, teamGames: teamGames) else { return false }
            // A fielding line with no chances is a DH's empty glove, not a
            // perfect one.
            if selectedCategory == .fielding, chances(in: stats, of: player) <= 0 { return false }
            return numericStat(for: player) != nil
        }
    }

    // MARK: - Qualification

    /// Games a player needs on the season before his line belongs on a board at
    /// all.
    ///
    /// Savant's percentile gate is looser than this and lets a call-up with a
    /// 2-for-4 debut onto the leaderboard, which is the one thing that makes a
    /// board obviously untrustworthy. Deliberately automatic rather than a
    /// picker: nobody opens a home-run board wanting the guy with one game in
    /// it, and the caption under the board says the bar is there.
    static let minGamesPlayed = 10

    /// Plate appearances that stand in for a missing games count.
    ///
    /// Bundled historical seasons were written before the pipeline carried a
    /// batting "G", so they'd all be cut by a games test they can't answer.
    /// Ten games is roughly 30 PA for a regular; 20 is the same bar set where a
    /// part-time player who really has played ten games still clears it.
    static let minPlateAppearancesFallback: Double = 20

    /// Boards whose value is a rate, and therefore need a real qualifier rather
    /// than a floor.
    ///
    /// A counting stat ranks itself: nobody with twelve games leads the league
    /// in home runs, so the games floor is all it needs. A rate does the
    /// opposite, the smaller the sample the more extreme the number, which is
    /// how a 25-PA hitter came to sit above Luis Arraez on the AVG board.
    private static let rateStats: Set<String> = [
        "AVG", "OBP", "SLG", "OPS",
        "ERA", "WHIP", "K/9", "BB/9", "K/BB",
    ]

    /// How many games the clubs have played, which is what MLB's qualifier is a
    /// multiple of (3.1 PA or 1.0 IP per team game).
    ///
    /// Measured off the board's own pool rather than assumed from the calendar,
    /// so it's right in April, right in a strike year, and right on a past
    /// season. The league's games-played leader has appeared in all but a
    /// handful of his club's games; before the pipeline carried a batting G,
    /// the PA leader's ~4.7 trips a game is the next best ruler.
    private var teamGamesPlayed: Double {
        var maxGames = 0.0
        var maxPA = 0.0
        for player in players {
            guard let stats = player.standardStats else { continue }
            if let stat = stats.stat("G", category: .hitting, playerType: player.playerType),
               let games = Double(stat.value.trimmingCharacters(in: .whitespaces)) {
                maxGames = max(maxGames, games)
            }
            if let stat = stats.first(where: { $0.label == "PA" }),
               let pa = Double(stat.value.trimmingCharacters(in: .whitespaces)) {
                maxPA = max(maxPA, pa)
            }
        }
        if maxGames > 0 { return maxGames }
        return maxPA / 4.7
    }

    /// True when this player has enough season behind him for the board.
    ///
    /// The games line is read off the *side* rather than off the board's
    /// category: fielding and running are position-player boards, and a hitter's
    /// G lives on his hitting line, not a fielding one.
    private func hasPlayedEnough(_ player: Player, stats: [StandardStat]) -> Bool {
        let gamesCategory: MetricCategory = selectedCategory == .pitching ? .pitching : .hitting
        if let stat = stats.stat("G", category: gamesCategory, playerType: player.playerType),
           let games = Double(stat.value.trimmingCharacters(in: .whitespaces)) {
            return games >= Double(Self.minGamesPlayed)
        }
        // No G on the line: a season written before the pipeline carried one.
        if gamesCategory == .pitching {
            return (rawValue("IP", in: stats, of: player) ?? 0) >= 10
        }
        return (rawValue("PA", in: stats, of: player) ?? 0) >= Self.minPlateAppearancesFallback
    }

    /// MLB's own rate-stat qualifier, applied only to the boards that are rates.
    ///
    /// SB% and FLD% are deliberately not in here: they're rates of chances
    /// rather than of playing time, and they already carry their own volume
    /// tests (a stolen-base attempt, a fielding chance).
    private func meetsRateQualifier(_ player: Player, stats: [StandardStat], teamGames: Double) -> Bool {
        guard Self.rateStats.contains(selectedStat), teamGames > 0 else { return true }
        if selectedCategory == .pitching {
            return (rawValue("IP", in: stats, of: player) ?? 0) >= teamGames
        }
        return (rawValue("PA", in: stats, of: player) ?? 0) >= 3.1 * teamGames
    }

    /// What the board is currently hiding, in its own words.
    private var qualifierCaption: String {
        guard Self.rateStats.contains(selectedStat) else {
            return "Ranks players with at least \(Self.minGamesPlayed) games this season."
        }
        let teamGames = teamGamesPlayed
        guard teamGames > 0 else {
            return "Ranks players with at least \(Self.minGamesPlayed) games this season."
        }
        if selectedCategory == .pitching {
            return "\(selectedStat) is a rate, so this board ranks qualified pitchers only: 1 inning per team game (\(Int(teamGames.rounded()))+ IP)."
        }
        return "\(selectedStat) is a rate, so this board ranks qualified hitters only: 3.1 PA per team game (\(Int((3.1 * teamGames).rounded()))+ PA)."
    }

    /// Total fielding chances: the volume behind a glove stat, and the only
    /// honest tie-break for one. Zero errors on 300 chances is a season; zero
    /// on four is a cameo.
    private func chances(in stats: [StandardStat], of player: Player) -> Double {
        ["PO", "A", "E"].reduce(0) { $0 + (rawValue($1, in: stats, of: player) ?? 0) }
    }

    private func matchesPlayerType(player: Player) -> Bool {
        // Pitchers carry batter-shaped standardStats (HR allowed, etc.) and a few
        // position players have appeared in mop-up pitching, so a permissive `!=`
        // filter leaks both directions. Whitelist by role, AND require a Savant
        // percentile in the matching category, that's Savant's qualification
        // signal. Without it the AVG board fills with 1-metric, sub-sample
        // players (e.g. .366 on 42 AB whose only metric is Sprint Speed) ranked
        // above real regulars. `qualifiedSeasonPlayers` can't catch this: ingest
        // already prunes metric-less rows, so that gate passes everyone.
        let type = player.playerType?.lowercased()
        switch selectedCategory {
        case .hitting:
            return type != "pitcher"
                && player.metrics.contains { $0.category == .hitting }
        case .pitching:
            return (type == "pitcher" || type == "two_way")
                && player.metrics.contains { $0.category == .pitching }
        case .fielding, .running:
            // The glove and the legs belong to position players, and the
            // qualification signal is still a hitting percentile: requiring a
            // *fielding* percentile would cut the board to the handful of
            // players Savant publishes OAA for.
            return type != "pitcher"
                && player.metrics.contains { $0.category == .hitting }
        }
    }

    // Sort players by the selected stat value, then by the playing time behind
    // it, so a board full of identical values (every 0-error fielder, every
    // 1.000 fielding percentage) leads with the players who earned it.
    var sortedPlayers: [Player] {
        filteredPlayers.sorted { p1, p2 in
            let v1 = numericStat(for: p1) ?? 0
            let v2 = numericStat(for: p2) ?? 0
            if v1 != v2 { return sortDescending ? v1 > v2 : v1 < v2 }
            return volume(for: p1) > volume(for: p2)
        }
    }

    /// The workload a tied value sits on: chances for the glove, plate
    /// appearances or innings for everything else.
    private func volume(for player: Player) -> Double {
        guard let stats = player.standardStats else { return 0 }
        switch selectedCategory {
        case .fielding: return chances(in: stats, of: player)
        case .pitching: return rawValue("IP", in: stats, of: player) ?? 0
        case .hitting, .running: return rawValue("PA", in: stats, of: player) ?? 0
        }
    }

    /// Numeric value of the selected stat, nil when this player has no figure
    /// for it. Derived rates are computed from their components.
    private func numericStat(for player: Player) -> Double? {
        guard let stats = player.standardStats else { return nil }
        if selectedStat == "SB%" {
            let sb = rawValue("SB", in: stats, of: player)
            let cs = rawValue("CS", in: stats, of: player)
            guard let sb, let cs, sb + cs > 0 else { return nil }
            return sb / (sb + cs) * 100
        }
        return rawValue(selectedStat, in: stats, of: player)
    }

    /// Reads the value off the line this board is about. On the Pitching board
    /// a two-way player's "H" has to be hits allowed, not hits collected.
    private func rawValue(_ label: String, in stats: [StandardStat], of player: Player) -> Double? {
        guard let stat = stats.stat(label, category: selectedCategory, playerType: player.playerType) else { return nil }
        let cleaned = stat.value.hasPrefix(".") ? "0" + stat.value : stat.value
        return Double(cleaned)
    }

    // Get formatted stat value for display
    private func statDisplay(for player: Player) -> String {
        if Self.derivedStats.contains(selectedStat) {
            guard let value = numericStat(for: player) else { return "-" }
            return String(format: "%.1f%%", value)
        }
        guard let stats = player.standardStats,
              let stat = stats.first(where: { $0.label == selectedStat }) else {
            return "-"
        }
        return stat.value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                categorySelector
                controlRow
                leadersList
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                // A board that quietly drops players has to say so, otherwise a
                // missing name reads as missing data.
                Text(qualifierCaption)
                    .font(SavantType.micro)
                    .tracking(0.2)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                // Lets the last row scroll through the floating tab bar.
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedCategory) { _, _ in
            guard !availableStats.contains(selectedStat) else { return }
            let stat = StandardStatCatalog.defaultStat(for: selectedCategory)
            selectedStat = stat
            sortDescending = StandardStatCatalog.defaultDescending(for: stat, category: selectedCategory)
        }
    }

    /// The same underlined four-tab header the Statcast board carries, in the
    /// same place, so moving between the two vocabularies doesn't move the
    /// furniture.
    private var categorySelector: some View {
        CategoryFilter(
            selectedCategory: Binding(
                get: { selectedCategory },
                set: { selectedCategory = $0 ?? .hitting }
            )
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Stat, direction, then the View menu: the same three shapes, in the same
    /// order, as the Statcast board's control row and the Trends header.
    private var controlRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let boardBindings, let viewModel {
                    StatsBoardStatPicker(viewModel: viewModel, bindings: boardBindings)
                } else {
                    // Pushed on its own, with no Stats tab behind it to hold
                    // the Statcast half, so the same pill carries one section.
                    statMenu
                }

                SortDirectionButton(descending: sortDescending, statLabel: selectedStat) {
                    sortDescending.toggle()
                }

                if let boardBindings, let viewModel {
                    StatsViewMenu(
                        viewModel: viewModel,
                        board: boardBindings.$board
                    )

                }
            }
            .padding(.horizontal, 12)
            // Room for the capsule strokes, which a tight frame would clip.
            .padding(.vertical, 1)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .frame(height: SavantControl.height + 2)
        .padding(.top, 8)
    }

    private var statMenu: some View {
        StatPickerMenu(
            standard: availableStats.map {
                .init(id: $0, label: $0, isSelected: $0 == selectedStat)
            },
            activeLabel: selectedStat,
            onSelectStandard: { option in
                selectedStat = option.id
                sortDescending = StandardStatCatalog.defaultDescending(
                    for: option.id,
                    category: selectedCategory
                )
            }
        )
    }

    private var leadersList: some View {
        VStack(spacing: 0) {
            // Header - tap stat column to toggle sort direction
            Button {
                sortDescending.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 0) {
                    Text("RANK")
                        .font(SavantType.micro)
                        .tracking(0.5)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(width: 42, alignment: .leading)

                    Text("PLAYER")
                        .font(SavantType.micro)
                        .tracking(0.5)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("TEAM")
                        .font(SavantType.micro)
                        .tracking(0.5)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(width: 44, alignment: .leading)

                    HStack(spacing: 4) {
                        Text(selectedStat.uppercased())
                            .font(SavantType.micro)
                            .tracking(0.5)
                            .foregroundStyle(SavantPalette.savantRed)
                        Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(SavantPalette.savantRed)
                    }
                    .frame(width: 80, alignment: .trailing)
                }
                .frame(height: SavantGeo.rowHeightHeader)
                .padding(.horizontal, SavantGeo.padInline)
                .background(SavantPalette.surfaceAlt)
                .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .bottom)
            }
            .buttonStyle(.plain)

            // Players
            if sortedPlayers.isEmpty {
                ContentUnavailableView {
                    Label(
                        isLoadingSeason ? "Loading season…" : "No data available",
                        systemImage: isLoadingSeason ? "clock" : "chart.bar"
                    )
                } description: {
                    Text(isLoadingSeason
                         ? "Pulling \(season.map(String.init) ?? "this season")'s players."
                         : "No players with \(Self.minGamesPlayed)+ games have \(selectedStat) data for this season.")
                }
                .padding(.vertical, 48)
                .background(SavantPalette.surface)
            } else {
                ForEach(Array(sortedPlayers.prefix(50).enumerated()), id: \.element.id) { index, player in
                    playerRow(rank: index + 1, player: player)
                }
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func playerRow(rank: Int, player: Player) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 0) {
                // Rank
                Text("\(rank)")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .frame(width: 36, alignment: .leading)
                    .monospacedDigit()

                // Player info
                HStack(spacing: 10) {
                    PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .truncationMode(.tail)
                        Text(player.displayPosition)
                            .font(SavantType.micro)
                            .tracking(0.4)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Team with color dot
                HStack(spacing: 4) {
                    TeamColorDot(abbr: player.team, size: 6)
                    Text(displayTeamAbbr(player.team))
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                .frame(width: 44, alignment: .leading)

                // Stat value
                Text(statDisplay(for: player))
                    .font(SavantType.statMed)
                    .foregroundStyle(SavantPalette.savantRed)
                    .frame(width: 70, alignment: .trailing)
                    .monospacedDigit()
            }
            .frame(height: SavantGeo.rowHeight)
            .padding(.horizontal, SavantGeo.padInline)
            .background(rank % 2 == 1 ? SavantPalette.surface : SavantPalette.surfaceAlt)
            .overlay(
                Rectangle()
                    .fill(SavantPalette.divider)
                    .frame(height: SavantGeo.hairline),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

/// The standard board as its own pushed screen, reached by tapping a
/// traditional stat on a player or team page.
///
/// It owns the selection that `StatsView` owns on the Stats tab: a drill-down
/// is a fresh question ("who leads the league in RBI"), not a change to what
/// the tab behind it was showing. That includes the year: the screen used to
/// print the season it was opened on and offer no way to move it, so answering
/// "who led the league in home runs in 2024" meant backing all the way out to
/// the Stats tab, changing the season there, and finding the stat again.
struct StandardStatsLeaderboardScreen: View {
    let viewModel: DashboardViewModel
    /// Fallback roster for previews and any caller without a view model.
    var fallbackPlayers: [Player] = []
    @State private var stat: String
    @State private var category: MetricCategory
    @State private var sortDescending: Bool
    @State private var season: Int
    @State private var paywallTrigger: PaywallTrigger?

    init(
        viewModel: DashboardViewModel,
        fallbackPlayers: [Player] = [],
        initialStat: String = "AVG",
        initialCategory: MetricCategory = .hitting,
        initialSeason: Int
    ) {
        self.viewModel = viewModel
        self.fallbackPlayers = fallbackPlayers
        _stat = State(initialValue: initialStat)
        _category = State(initialValue: initialCategory)
        _season = State(initialValue: initialSeason)
        _sortDescending = State(
            initialValue: StandardStatCatalog.defaultDescending(for: initialStat, category: initialCategory)
        )
    }

    private var players: [Player] {
        let roster = viewModel.players(forSeason: season)
        return roster.isEmpty ? fallbackPlayers : roster
    }

    var body: some View {
        StandardStatsLeadersView(
            players: players,
            selectedStat: $stat,
            selectedCategory: $category,
            sortDescending: $sortDescending,
            season: season,
            isLoadingSeason: players.isEmpty && viewModel.isHistoricalLoading
        )
        // String(), not the Int: interpolating a number into a
        // `LocalizedStringKey` runs it through the number formatter, which is
        // how this title read "2,026".
        .navigationTitle("\(stat) · \(String(season))")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(DrillDownSeasonPill(
            viewModel: viewModel,
            season: $season,
            paywallTrigger: $paywallTrigger
        ))
        // Past seasons only exist once the history load has run.
        .task(id: season) {
            guard season != viewModel.selectedSeason else { return }
            await viewModel.loadHistoricalIfNeeded()
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }
}

/// The season pill the pushed leaderboards carry in their trailing toolbar slot.
///
/// Same control, same place, as the Teams page's own season switcher, so a year
/// can be changed wherever a year is being shown.
struct DrillDownSeasonPill: ViewModifier {
    let viewModel: DashboardViewModel
    @Binding var season: Int
    @Binding var paywallTrigger: PaywallTrigger?

    private var pill: some View {
        SeasonMenu(
            seasons: viewModel.availableSeasons,
            selected: season,
            isLocked: { viewModel.isSeasonLocked($0) },
            onSelect: { picked in
                if viewModel.isSeasonLocked(picked) {
                    paywallTrigger = .lockedSeason(picked)
                } else {
                    season = picked
                }
            }
        ) {
            SavantNavPill(systemImage: "calendar", title: String(season))
        }
        .accessibilityHint("Choose which season this leaderboard ranks")
    }

    func body(content: Content) -> some View {
        content.toolbar {
            // The red pill draws its own capsule; suppress the iOS 26 Liquid
            // Glass container so it doesn't read as a double-pill.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { pill }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { pill }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StandardStatsLeaderboardScreen(
            viewModel: DashboardViewModel(),
            fallbackPlayers: SampleData.players,
            initialSeason: StatScoutSeason.current
        )
        .environmentObject(StoreService.shared)
    }
}
#endif
