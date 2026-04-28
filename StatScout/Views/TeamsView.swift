import SwiftUI

struct TeamsView: View {
    let viewModel: DashboardViewModel

    private static let allTeams: [String] = [
        "ARI","ATL","BAL","BOS","CHC","CWS","CIN","CLE","COL","DET",
        "HOU","KC","LAA","LAD","MIA","MIL","MIN","NYM","NYY","OAK",
        "PHI","PIT","SD","SEA","SF","STL","TB","TEX","TOR","WSH"
    ]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SavantSectionBar(title: "TEAMS")

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.allTeams, id: \.self) { abbr in
                        let count = viewModel.teamCounts[abbr] ?? 0
                        NavigationLink(value: TeamDestination(abbr: abbr)) {
                            TeamTile(abbr: abbr, playerCount: count)
                        }
                        .buttonStyle(.plain)
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
    var playerCount: Int = 0

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
            .overlay(alignment: .topTrailing) {
                if playerCount > 0 {
                    Text("\(playerCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(SavantPalette.savantRed)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
            Text(teamFullName(abbr))
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
