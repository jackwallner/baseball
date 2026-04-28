import SwiftUI

struct TeamView: View {
    let team: String
    let players: [Player]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: players.compactMap(\.season).max())

                VStack(spacing: 0) {
                    SavantSectionBar(title: "ROSTER")

                    if players.isEmpty {
                        ContentUnavailableView {
                            Label("No players tracked", systemImage: "person.2.slash")
                        } description: {
                            Text("No players found for \(team) yet.")
                        }
                        .padding(.vertical, 24)
                    } else {
                        LeaderboardTableHeader()
                        ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                            NavigationLink(value: player) {
                                LeaderboardTableRow(
                                    rank: index + 1,
                                    player: player
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
        }
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
