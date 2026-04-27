import SwiftUI

struct TeamView: View {
    let team: String
    let players: [Player]
    @Binding var selectedPlayer: Player?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(team)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(players.count) players")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    SectionHeader(title: "Roster", subtitle: "Sorted by overall percentile")
                        .padding(.horizontal, 20)

                    if players.isEmpty {
                        ContentUnavailableView {
                            Label("No players tracked", systemImage: "person.2.slash")
                        } description: {
                            Text("No players found for \(team) yet.")
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(players) { player in
                                LeaderboardRow(player: player)
                                    .onTapGesture { selectedPlayer = player }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(StatScoutTheme.background.ignoresSafeArea())
            .navigationTitle(team)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .tint(.white)
    }
}

#Preview {
    TeamView(
        team: "NYY",
        players: SampleData.players.filter { $0.team == "NYY" },
        selectedPlayer: .constant(nil)
    )
}
