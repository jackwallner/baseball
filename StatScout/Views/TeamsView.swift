import SwiftUI

@Observable
final class TeamsViewModel {
    private static let favoritesKey = "favoriteTeam"
    
    var favoriteTeam: String? {
        didSet {
            if let team = favoriteTeam {
                UserDefaults.standard.set(team, forKey: Self.favoritesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.favoritesKey)
            }
        }
    }
    
    init() {
        self.favoriteTeam = UserDefaults.standard.string(forKey: Self.favoritesKey)
    }
    
    func isFavorite(_ team: String) -> Bool {
        favoriteTeam == team
    }
    
    func toggleFavorite(_ team: String) {
        if favoriteTeam == team {
            favoriteTeam = nil
        } else {
            favoriteTeam = team
        }
    }
}

struct TeamsView: View {
    let viewModel: DashboardViewModel
    @State private var teamsViewModel = TeamsViewModel()

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
    
    private var sortedTeams: [String] {
        guard let favorite = teamsViewModel.favoriteTeam else {
            return Self.allTeams
        }
        // Move favorite to front, keep rest alphabetical
        var teams = Self.allTeams.filter { $0 != favorite }
        return [favorite] + teams
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerBar

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sortedTeams, id: \.self) { abbr in
                        let count = viewModel.teamCounts[abbr] ?? 0
                        let isFav = teamsViewModel.isFavorite(abbr)
                        NavigationLink(value: TeamDestination(abbr: abbr)) {
                            TeamTile(
                                abbr: abbr,
                                playerCount: count,
                                isFavorite: isFav
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            favoriteContextMenu(for: abbr)
                        }
                    }
                }
                .padding(12)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
    }
    
    private var headerBar: some View {
        HStack {
            Text("TEAMS")
                .font(SavantType.sectionTitle)
                .foregroundStyle(SavantPalette.inkTertiary)
                .tracking(0.5)
            
            Spacer()
            
            if let favorite = teamsViewModel.favoriteTeam {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("\(favorite) favorite")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SavantPalette.surface)
    }
    
    private func favoriteContextMenu(for team: String) -> some View {
        Group {
            if teamsViewModel.isFavorite(team) {
                Button {
                    teamsViewModel.toggleFavorite(team)
                } label: {
                    Label("Remove from favorites", systemImage: "star.slash")
                }
            } else {
                Button {
                    teamsViewModel.toggleFavorite(team)
                } label: {
                    Label("Set as favorite", systemImage: "star")
                }
            }
        }
    }
}

struct TeamTile: View {
    let abbr: String
    var playerCount: Int = 0
    var isFavorite: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MLBTeamColor.color(abbr))
                    .frame(width: 44, height: 44)
                Text(abbr)
                    .font(SavantType.statSmall)
                    .foregroundStyle(.white)
                
                if isFavorite {
                    // Star badge
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                                .shadow(radius: 1)
                                .offset(x: 4, y: -4)
                        }
                        Spacer()
                    }
                    .frame(width: 44, height: 44)
                }
            }
            
            VStack(spacing: 2) {
                Text(teamFullName(abbr))
                    .font(SavantType.smallBold)
                    .foregroundStyle(isFavorite ? SavantPalette.savantRed : SavantPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if playerCount > 0 {
                    Text("\(playerCount) players")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(isFavorite ? SavantPalette.surfaceAlt : SavantPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(isFavorite ? SavantPalette.savantRed : SavantPalette.hairline, lineWidth: isFavorite ? 2 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
    }
}

#Preview {
    NavigationStack {
        TeamsView(viewModel: DashboardViewModel())
    }
}
