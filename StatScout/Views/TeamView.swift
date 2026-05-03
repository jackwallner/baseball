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
                            ForEach(filteredPlayers, id: \.id) { player in
                                NavigationLink(value: player) {
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
                                        Spacer()
                                        HStack(spacing: 6) {
                                            Text("\(player.overallPercentile)")
                                                .font(SavantType.statSmall)
                                                .foregroundStyle(SavantPalette.color(forPercentile: player.overallPercentile))
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(SavantPalette.inkTertiary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(SavantPalette.surface)
                                    .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .bottom)
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

#Preview {
    NavigationStack {
        TeamView(
            team: "NYY",
            players: SampleData.players.filter { $0.team == "NYY" }
        )
    }
}
