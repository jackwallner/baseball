import SwiftUI

struct TeamView: View {
    let team: String
    let players: [Player]
    @State private var searchText = ""
    @State private var sortOption: SortOption = .percentile
    @State private var sortDescending = true

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case percentile = "Percentile"
    }

    var filteredPlayers: [Player] {
        let filtered = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        return filtered.sorted {
            switch sortOption {
            case .name:
                return sortDescending ? $0.name > $1.name : $0.name < $1.name
            case .percentile:
                return sortDescending ? $0.overallPercentile > $1.overallPercentile : $0.overallPercentile < $1.overallPercentile
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: players.compactMap(\.season).max())

                VStack(spacing: 0) {
                    SavantSectionBar(
                        title: "ROSTER",
                        trailing: players.isEmpty ? nil : AnyView(
                            HStack(spacing: 12) {
                                Menu {
                                    ForEach(SortOption.allCases, id: \.self) { option in
                                        Button(action: {
                                            sortOption = option
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.impactOccurred()
                                        }) {
                                            HStack {
                                                Text(option.rawValue)
                                                if sortOption == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(sortOption.rawValue)
                                            .font(SavantType.micro)
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(SavantPalette.inkSecondary)
                                }

                                Button(action: {
                                    sortDescending.toggle()
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }) {
                                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                                        .font(.caption)
                                        .foregroundStyle(SavantPalette.inkSecondary)
                                }
                            }
                        )
                    )

                    if players.isEmpty {
                        emptyStateView(
                            icon: "person.2.slash",
                            title: "No players tracked",
                            description: "No players are currently tracked for \(teamFullName(team)). Check back after the nightly update."
                        )
                    } else {
                        SearchField(text: $searchText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                        if filteredPlayers.isEmpty {
                            emptyStateView(
                                icon: "magnifyingglass",
                                title: "No players found",
                                description: "Try a different search term."
                            )
                        } else {
                            // Leaderboard-style header (custom for team view)
                            TeamTableHeader(sortDescending: sortDescending)

                            // Leaderboard-style rows with alternating backgrounds
                            ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                                NavigationLink(value: player) {
                                    TeamPlayerRow(
                                        rank: index + 1,
                                        player: player
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
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(teamFullName(team))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func emptyStateView(icon: String, title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        }
        .padding(.vertical, 48)
    }
}

// MARK: - Team Table Header (Leaderboard style)

struct TeamTableHeader: View {
    let sortDescending: Bool

    var body: some View {
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

            Text("POS")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 60, alignment: .leading)

            HStack(spacing: 4) {
                Text("OVERALL")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
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
}

// MARK: - Team Player Row (Leaderboard style)

struct TeamPlayerRow: View {
    let rank: Int
    let player: Player

    var body: some View {
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
                Text(player.name)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Position column (replaces team since all same team)
            Text(player.position)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 60, alignment: .leading)

            // Percentile with bar
            HStack(spacing: 8) {
                PercentileBarMini(percentile: player.overallPercentile)
                    .frame(width: 40)
                Text("\(player.overallPercentile)")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.color(forPercentile: player.overallPercentile))
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }
            .frame(width: 80, alignment: .trailing)
        }
        .frame(height: SavantGeo.rowHeight)
        .padding(.horizontal, SavantGeo.padInline)
        .background(rank % 2 == 1 ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        TeamView(
            team: "NYY",
            players: SampleData.players.filter { $0.team == "NYY" }
        )
    }
}
