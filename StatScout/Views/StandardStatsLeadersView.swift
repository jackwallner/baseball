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
    /// Set when arrived at by tapping a specific stat on a player profile, so
    /// the leaderboard opens on the stat that was tapped rather than AVG.
    var season: Int? = nil
    /// Advanced / Standard / Best-Worst, when this board is shown inside
    /// `StatsView`. Rides in this board's own control row, exactly as it does
    /// on the Advanced board, so the two headers are the same header.
    var statsMode: Binding<StatsMode>? = nil
    @State private var selectedCategory: MetricCategory
    @State private var selectedStat: String
    @State private var sortDescending = true

    init(
        players: [Player],
        initialStat: String = "AVG",
        initialCategory: MetricCategory = .hitting,
        season: Int? = nil,
        statsMode: Binding<StatsMode>? = nil
    ) {
        self.players = players
        self.season = season
        self.statsMode = statsMode
        _selectedCategory = State(initialValue: initialCategory)
        _selectedStat = State(initialValue: initialStat)
    }

    /// Stats where lower is the better outcome, sort defaults to ascending so the
    /// leader (lowest ERA, fewest losses, etc.) sits at the top.
    private static let lowerIsBetter: Set<String> = ["ERA", "WHIP", "BB/9", "L", "E", "CS"]

    // SO is contextual: pitcher strikeouts (good) vs batter strikeouts (bad).
    // The pitching tab keeps SO as "more is better"; the hitting tab flips it.
    private func defaultDescending(for stat: String) -> Bool {
        if stat == "SO" {
            return selectedCategory == .pitching
        }
        return !Self.lowerIsBetter.contains(stat)
    }

    // Available stats per category
    var availableStats: [String] {
        switch selectedCategory {
        case .hitting:
            return ["AVG", "HR", "RBI", "OBP", "SLG", "OPS", "H", "R", "2B", "3B", "BB", "SO"]
        case .pitching:
            return ["ERA", "WHIP", "W", "L", "SV", "SO", "IP", "K/9", "BB/9", "QS"]
        case .fielding:
            // Fielding percentage leads, not errors: "fewest errors" sorted
            // ascending is fifty players on zero, and the top of that list is
            // whoever touched the ball least.
            return ["FLD%", "E", "A", "PO", "DP"]
        case .running:
            return ["SB", "SB%", "CS", "3B", "R"]
        }
    }

    /// Rates that are computed here rather than stored, because the pipeline
    /// ships the components and not the ratio.
    private static let derivedStats: Set<String> = ["SB%"]

    // Filter players who have the selected stat
    var filteredPlayers: [Player] {
        players.filter { player in
            guard let stats = player.standardStats else { return false }
            guard matchesPlayerType(player: player) else { return false }
            // A fielding line with no chances is a DH's empty glove, not a
            // perfect one.
            if selectedCategory == .fielding, chances(in: stats, of: player) <= 0 { return false }
            return numericStat(for: player) != nil
        }
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
            let stat = availableStats.first ?? "AVG"
            selectedStat = stat
            sortDescending = defaultDescending(for: stat)
        }
    }

    /// The same underlined four-tab header the Advanced board carries, in the
    /// same place, so the mode chip only changes the stats underneath it.
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

    /// Mode chip, then the sorted stat, then the stat menu. Same row, same
    /// order, same three shapes as the Advanced board's control row: the twelve
    /// capsules that used to live here were a fourth kind of control that only
    /// this screen had.
    private var controlRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let statsMode {
                    StatsModeMenu(mode: statsMode)
                }
                Button {
                    sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    SavantChip(
                        title: selectedStat,
                        trailing: .sortArrow(descending: sortDescending)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sorted by \(selectedStat), \(sortDescending ? "highest first" : "lowest first")")
                .accessibilityHint("Tap to flip sort direction")

                statMenu
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
        Menu {
            Section("Stat") {
                ForEach(availableStats, id: \.self) { stat in
                    Button {
                        selectedStat = stat
                        sortDescending = defaultDescending(for: stat)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if stat == selectedStat {
                            Label(stat, systemImage: "checkmark")
                        } else {
                            Text(stat)
                        }
                    }
                }
            }
        } label: {
            SavantChip(
                title: "Stat",
                systemImage: "line.3.horizontal.decrease.circle",
                trailing: .chevron
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Stat")
        .accessibilityValue(selectedStat)
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
                    Label("No data available", systemImage: "chart.bar")
                } description: {
                    Text("No players have \(selectedStat) data for the current season.")
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

#if DEBUG
#Preview {
    NavigationStack {
        StandardStatsLeadersView(players: SampleData.players)
            .environmentObject(StoreService.shared)
            .navigationTitle("Standard Stats")
    }
}
#endif
