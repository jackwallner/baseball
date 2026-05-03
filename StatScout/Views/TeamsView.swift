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

    func setFavorite(_ team: String) {
        favoriteTeam = team
    }

    func removeFavorite() {
        favoriteTeam = nil
    }
}

struct TeamsView: View {
    let viewModel: DashboardViewModel
    @State private var teamsViewModel = TeamsViewModel()
    @State private var searchText = ""

    private static let allTeams: [String] = [
        "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
        "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "OAK",
        "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB", "TEX", "TOR", "WSH"
    ]

    private var filteredTeams: [String] {
        let teams = searchText.isEmpty ? Self.allTeams : Self.allTeams.filter {
            teamFullName($0).localizedCaseInsensitiveContains(searchText) ||
            $0.localizedCaseInsensitiveContains(searchText)
        }

        // Sort: favorite first, then alphabetical
        guard let favorite = teamsViewModel.favoriteTeam else {
            return teams.sorted { teamFullName($0) < teamFullName($1) }
        }

        return teams.sorted {
            let isFav0 = $0 == favorite
            let isFav1 = $1 == favorite
            if isFav0 != isFav1 {
                return isFav1 ? false : true
            }
            return teamFullName($0) < teamFullName($1)
        }
    }

    private var nonFavoriteTeams: [String] {
        guard let favorite = teamsViewModel.favoriteTeam else {
            return filteredTeams
        }
        return filteredTeams.filter { $0 != favorite }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Favorite Team Section (if set and not filtered out)
                if let favorite = teamsViewModel.favoriteTeam,
                   filteredTeams.contains(favorite),
                   searchText.isEmpty {
                    favoriteTeamSection(favorite: favorite)
                }

                // All Teams Section
                allTeamsSection
            }
            .padding(.top, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func favoriteTeamSection(favorite: String) -> some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "FAVORITE TEAM",
                trailing: AnyView(
                    Button(action: {
                        teamsViewModel.removeFavorite()
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.slash")
                                .font(.caption)
                            Text("Remove")
                                .font(SavantType.micro)
                        }
                        .foregroundStyle(SavantPalette.inkSecondary)
                    }
                )
            )

            NavigationLink(value: TeamDestination(abbr: favorite)) {
                TeamRow(
                    abbr: favorite,
                    isFavorite: true,
                    showFavoriteButton: false
                )
            }
            .buttonStyle(.plain)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }

    private var allTeamsSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: teamsViewModel.favoriteTeam != nil ? "ALL TEAMS" : "TEAMS",
                trailing: searchText.isEmpty ? nil : AnyView(
                    Button(action: { searchText = "" }) {
                        Text("Clear")
                            .font(SavantType.micro)
                            .foregroundStyle(SavantPalette.inkSecondary)
                    }
                )
            )

            SearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if filteredTeams.isEmpty {
                ContentUnavailableView {
                    Label("No teams found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term.")
                }
                .padding(.vertical, 48)
            } else {
                // List teams
                let teamsToShow = teamsViewModel.favoriteTeam != nil && searchText.isEmpty
                    ? nonFavoriteTeams
                    : filteredTeams

                ForEach(Array(teamsToShow.enumerated()), id: \.element) { index, abbr in
                    NavigationLink(value: TeamDestination(abbr: abbr)) {
                        TeamRow(
                            abbr: abbr,
                            isFavorite: teamsViewModel.isFavorite(abbr),
                            showFavoriteButton: teamsViewModel.favoriteTeam != abbr,
                            onFavoriteTap: {
                                teamsViewModel.setFavorite(abbr)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                        )
                    }
                    .buttonStyle(.plain)

                    if index < teamsToShow.count - 1 {
                        Divider()
                            .padding(.leading, 68)
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

// MARK: - Team Row

struct TeamRow: View {
    let abbr: String
    let isFavorite: Bool
    let showFavoriteButton: Bool
    var onFavoriteTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Team logo/color circle
            Circle()
                .fill(MLBTeamColor.color(abbr))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(abbr)
                        .font(SavantType.smallBold)
                        .foregroundStyle(.white)
                )
                .padding(.trailing, 12)

            // Team name
            VStack(alignment: .leading, spacing: 2) {
                Text(teamFullName(abbr))
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                    .lineLimit(1)

                Text(abbr)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Favorite button (if showing)
            if showFavoriteButton {
                Button(action: {
                    onFavoriteTap?()
                }) {
                    Image(systemName: "star")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SavantPalette.inkTertiary)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(isFavorite && !showFavoriteButton ? SavantPalette.surfaceAlt : SavantPalette.surface)
    }
}

// MARK: - Legacy Team Tile (for reference/previews)

struct TeamTile: View {
    let abbr: String
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

            Text(teamFullName(abbr))
                .font(SavantType.smallBold)
                .foregroundStyle(isFavorite ? SavantPalette.savantRed : SavantPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
