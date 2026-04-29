import SwiftUI

struct TeamView: View {
    let team: String
    let players: [Player]
    @State private var searchText = ""

    var filteredPlayers: [Player] {
        if searchText.isEmpty {
            return players.sorted { $0.name < $1.name }
        } else {
            return players.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: players.compactMap(\.season).max())

                VStack(spacing: 0) {
                    SavantSectionBar(title: "ROSTER")

                    SearchField(text: $searchText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if filteredPlayers.isEmpty {
                        ContentUnavailableView {
                            Label("No players found", systemImage: "person.2.slash")
                        } description: {
                            Text(players.isEmpty ? "No players tracked for \(team) yet." : "Try a different search term.")
                        }
                        .padding(.vertical, 24)
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
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(SavantPalette.inkTertiary)
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
}

#Preview {
    NavigationStack {
        TeamView(
            team: "NYY",
            players: SampleData.players.filter { $0.team == "NYY" }
        )
    }
}
