import SwiftUI

struct TeamsView: View {
    let viewModel: DashboardViewModel

    private static let allTeams: [String] = [
        "ARI","ATL","BAL","BOS","CHC","CWS","CIN","CLE","COL","DET",
        "HOU","KC","LAA","LAD","MIA","MIL","MIN","NYM","NYY","OAK",
        "PHI","PIT","SD","SEA","SF","STL","TB","TEX","TOR","WSH"
    ]

    private var rosteredTeams: Set<String> {
        Set(viewModel.players.map(\.team))
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SavantSectionBar(
                    title: "MLB CLUBS",
                    trailing: AnyView(
                        Text("\(rosteredTeams.count)/30 tracked")
                            .font(SavantType.micro)
                            .tracking(0.5)
                            .foregroundStyle(SavantPalette.inkSecondary)
                    )
                )

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.allTeams, id: \.self) { abbr in
                        let count = viewModel.players(forTeam: abbr).count
                        NavigationLink(value: TeamDestination(abbr: abbr)) {
                            TeamTile(abbr: abbr, playerCount: count)
                        }
                        .buttonStyle(.plain)
                        .disabled(count == 0)
                        .opacity(count == 0 ? 0.45 : 1)
                    }
                }
                .padding(12)
            }
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
    }
}

struct TeamTile: View {
    let abbr: String
    let playerCount: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MLBTeamColor.color(abbr))
                    .frame(width: 44, height: 44)
                Text(abbr)
                    .font(SavantType.statSmall)
                    .foregroundStyle(.white)
            }
            Text(teamFullName(abbr))
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(playerCount) tracked")
                .font(SavantType.micro)
                .tracking(0.4)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(SavantPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
    }
}

#Preview {
    NavigationStack {
        TeamsView(viewModel: DashboardViewModel())
    }
}
