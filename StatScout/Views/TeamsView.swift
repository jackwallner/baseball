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
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    @State private var teamsViewModel = TeamsViewModel()
    @State private var searchText = ""
    @State private var showingPaywall = false

    private static let allTeams: [String] = [
        "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
        "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "OAK",
        "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB", "TEX", "TOR", "WSH"
    ]

    private var filteredTeams: [String] {
        let teams = searchText.isEmpty ? viewModel.teamsWithData : viewModel.teamsWithData.filter {
            teamFullName($0).localizedCaseInsensitiveContains(searchText) ||
            $0.localizedCaseInsensitiveContains(searchText)
        }

        // Sort: favorite first, then by team score descending
        guard let favorite = teamsViewModel.favoriteTeam else {
            return teams.sorted { viewModel.teamScore($0) > viewModel.teamScore($1) }
        }

        return teams.sorted {
            let isFav0 = $0 == favorite
            let isFav1 = $1 == favorite
            if isFav0 != isFav1 {
                return isFav1 ? false : true
            }
            return viewModel.teamScore($0) > viewModel.teamScore($1)
        }
    }

    private var nonFavoriteTeams: [String] {
        guard let favorite = teamsViewModel.favoriteTeam else {
            return filteredTeams
        }
        return filteredTeams.filter { $0 != favorite }
    }

    private var isInitiallyLoading: Bool {
        viewModel.isLoading && viewModel.teamsWithData.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                seasonHeader
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                if isInitiallyLoading {
                    teamsLoadingState
                } else {
                    if let favorite = teamsViewModel.favoriteTeam,
                       filteredTeams.contains(favorite),
                       searchText.isEmpty {
                        favoriteTeamSection(favorite: favorite)
                    }

                    allTeamsSection
                }
            }
            .padding(.top, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: .teamView)
        }
    }

    private var teamsLoadingState: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(SavantPalette.surfaceAlt)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SavantPalette.surfaceAlt)
                            .frame(width: 140, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SavantPalette.surfaceAlt)
                            .frame(width: 40, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
            }
        }
        .padding(.horizontal, 12)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .redacted(reason: .placeholder)
    }

    private var seasonHeader: some View {
        HStack {
            seasonMenu
            Spacer()
            Text("\(filteredTeams.count) teams")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var seasonMenu: some View {
        Menu {
            if viewModel.isHistoricalLoading {
                Label("Loading past seasons…", systemImage: "hourglass")
            } else if !viewModel.hasLoadedHistorical {
                Button {
                    if store.isPro {
                        Task { await viewModel.loadHistoricalIfNeeded() }
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label(store.isPro ? "Load past seasons" : "Past seasons require Pro",
                          systemImage: store.isPro ? "clock.arrow.circlepath" : "crown.fill")
                }
            }
            ForEach(viewModel.availableSeasons, id: \.self) { season in
                let isLocked = season != 2026 && !store.isPro
                Button {
                    if isLocked {
                        showingPaywall = true
                    } else {
                        viewModel.selectedSeason = season
                    }
                } label: {
                    HStack {
                        Text(String(season))
                        if isLocked {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SavantPalette.savantRed)
                Text("Season")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkSecondary)
                Text(String(viewModel.selectedSeason))
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
        }
        .menuOrder(.fixed)
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
                    showFavoriteButton: false,
                    teamScore: viewModel.teamScore(favorite)
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
                let noDataForSeason = searchText.isEmpty && viewModel.teamsWithData.isEmpty
                ContentUnavailableView {
                    Label(noDataForSeason ? "No teams available" : "No teams found", systemImage: "magnifyingglass")
                } description: {
                    Text(noDataForSeason
                         ? "No teams have player data for the \(String(viewModel.selectedSeason)) season. Try selecting a different season from the Leaders tab."
                         : "Try a different search term.")
                }
                .padding(.vertical, 48)
            } else {
                // List teams
                let teamsToShow = teamsViewModel.favoriteTeam != nil && searchText.isEmpty
                    ? nonFavoriteTeams
                    : filteredTeams

                ForEach(Array(teamsToShow.enumerated()), id: \.element) { index, abbr in
                    HStack(spacing: 0) {
                        NavigationLink(value: TeamDestination(abbr: abbr)) {
                            TeamRowContent(
                                abbr: abbr,
                                isFavorite: teamsViewModel.isFavorite(abbr),
                                teamScore: viewModel.teamScore(abbr)
                            )
                        }
                        .buttonStyle(.plain)

                        if teamsViewModel.favoriteTeam != abbr {
                            Button {
                                teamsViewModel.setFavorite(abbr)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "star")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(SavantPalette.inkTertiary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.trailing, 12)

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
    let teamScore: Double?
    var onFavoriteTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            TeamRowContent(abbr: abbr, isFavorite: isFavorite, teamScore: teamScore)

            if showFavoriteButton {
                Button(action: { onFavoriteTap?() }) {
                    Image(systemName: "star")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.trailing, 12)
    }
}

struct TeamRowContent: View {
    let abbr: String
    let isFavorite: Bool
    let teamScore: Double?

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(MLBTeamColor.color(abbr))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(abbr)
                        .font(SavantType.smallBold)
                        .foregroundStyle(.white)
                )
                .padding(.trailing, 12)

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

            if let score = teamScore {
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", score))
                        .font(SavantType.statSmall)
                        .foregroundStyle(SavantPalette.inkSecondary)
                    Text("xwOBA")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                .padding(.trailing, 8)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .padding(.leading, 12)
        .frame(height: 56)
        .contentShape(Rectangle())
        .background(isFavorite ? SavantPalette.surfaceAlt : SavantPalette.surface)
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

#if DEBUG
#Preview {
    NavigationStack {
        TeamsView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
