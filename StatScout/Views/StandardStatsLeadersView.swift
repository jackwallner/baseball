import SwiftUI

enum StandardStatCategory: String, CaseIterable {
    case hitting = "Hitting"
    case pitching = "Pitching"
}

struct StandardStatsLeadersView: View {
    let players: [Player]
    @State private var selectedCategory: StandardStatCategory = .hitting
    @State private var selectedStat: String = "AVG"
    @State private var sortDescending = true
    
    // Available stats per category
    var availableStats: [String] {
        switch selectedCategory {
        case .hitting:
            return ["AVG", "HR", "RBI", "OBP", "SLG", "OPS", "H", "R", "2B", "3B", "SB", "BB", "SO"]
        case .pitching:
            return ["ERA", "WHIP", "W", "L", "SV", "SO", "IP", "K/9", "BB/9", "QS"]
        }
    }
    
    // Filter players who have the selected stat
    var filteredPlayers: [Player] {
        players.filter { player in
            guard let stats = player.standardStats else { return false }
            // Check if player has the selected stat
            return stats.contains { $0.label == selectedStat }
        }
    }
    
    // Sort players by the selected stat value
    var sortedPlayers: [Player] {
        filteredPlayers.sorted { p1, p2 in
            let v1 = statValue(for: p1)
            let v2 = statValue(for: p2)
            return sortDescending ? v1 > v2 : v1 < v2
        }
    }
    
    // Get numeric value for sorting
    private func statValue(for player: Player) -> Double {
        guard let stats = player.standardStats,
              let stat = stats.first(where: { $0.label == selectedStat }) else {
            return 0
        }
        return Double(stat.value) ?? 0
    }
    
    // Get formatted stat value for display
    private func statDisplay(for player: Player) -> String {
        guard let stats = player.standardStats,
              let stat = stats.first(where: { $0.label == selectedStat }) else {
            return "—"
        }
        return stat.value
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Category selector
                categorySelector

                // Stat selector
                statSelector

                // Leaders list
                leadersList
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var categorySelector: some View {
        HStack(spacing: 8) {
            ForEach(StandardStatCategory.allCases, id: \.self) { category in
                Button(action: {
                    selectedCategory = category
                    selectedStat = availableStats.first ?? "AVG"
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    Text(category.rawValue)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(selectedCategory == category ? .white : SavantPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selectedCategory == category ? SavantPalette.savantRed : SavantPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var statSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableStats, id: \.self) { stat in
                    Button(action: {
                        selectedStat = stat
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        Text(stat)
                            .font(SavantType.body)
                            .foregroundStyle(selectedStat == stat ? .white : SavantPalette.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedStat == stat ? SavantPalette.savantNavy : SavantPalette.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var leadersList: some View {
        VStack(spacing: 0) {
            // Header - matches LeaderboardTableHeader style
            HStack(spacing: 0) {
                Text("RANK")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 50, alignment: .leading)

                Text("PLAYER")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("TEAM")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 50, alignment: .leading)

                // Sort indicator - display only, use section bar controls to change
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
            
            // Players
            if sortedPlayers.isEmpty {
                ContentUnavailableView {
                    Label("No data available", systemImage: "chart.bar")
                } description: {
                    Text("Standard stats are not available for the current season yet.")
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
                    .frame(width: 50, alignment: .leading)
                    .monospacedDigit()

                // Player info
                HStack(spacing: 10) {
                    PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                            .lineLimit(1)
                        Text(player.position)
                            .font(SavantType.micro)
                            .tracking(0.4)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Team with color dot
                HStack(spacing: 4) {
                    TeamColorDot(abbr: player.team, size: 6)
                    Text(player.team)
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                .frame(width: 50, alignment: .leading)

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

#Preview {
    NavigationStack {
        StandardStatsLeadersView(players: SampleData.players)
            .navigationTitle("Standard Stats")
    }
}
