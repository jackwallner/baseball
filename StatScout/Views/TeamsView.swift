import SwiftUI

/// Thin wrapper over the shared `FavoritesStore` so the Teams tab and the
/// player profile can't drift apart on what "favorite" means.
@MainActor
struct TeamsViewModel {
    private let store = FavoritesStore.shared

    var favoriteTeam: String? { store.team }

    func isFavorite(_ team: String) -> Bool { store.isFavorite(team: team) }

    func setFavorite(_ team: String) { store.setFavorite(team: team) }

    func removeFavorite() { store.setFavorite(team: nil) }
}

struct TeamsView: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    @Binding var path: NavigationPath
    private let teamsViewModel = TeamsViewModel()
    @State private var favorites = FavoritesStore.shared
    @State private var searchText = ""
    @State private var showingTrial = false
    // Auto-enter the favorite team once per launch; popping back must not
    // re-push it, or the user can never reach the list.
    @State private var didAutoEnterFavorite = false
    @State private var lockedSeasonTrigger: PaywallTrigger?

    private static let allTeams: [String] = [
        "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
        "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "OAK",
        "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB", "TEX", "TOR", "WSH"
    ]

    /// Six divisions of five, in standings order. Grouping this way is what
    /// lets all thirty teams fit one screen without scrolling, and it's how
    /// people already hold the league in their heads, so it reads faster than
    /// an alphabetical wall even before the space saving.
    static let divisions: [(name: String, teams: [String])] = [
        ("AL East",    ["BAL", "BOS", "NYY", "TB", "TOR"]),
        ("AL Central", ["CWS", "CLE", "DET", "KC", "MIN"]),
        ("AL West",    ["HOU", "LAA", "OAK", "SEA", "TEX"]),
        ("NL East",    ["ATL", "MIA", "NYM", "PHI", "WSH"]),
        ("NL Central", ["CHC", "CIN", "MIL", "PIT", "STL"]),
        ("NL West",    ["ARI", "COL", "LAD", "SD", "SF"]),
    ]

    private var filteredTeams: [String] {
        let teams = searchText.isEmpty ? activeTeams : activeTeams.filter {
            teamMatchesQuery($0, query: searchText)
        }
        // Plain alphabetical by full team name, the old score-based ordering was
        // confusing and the score itself was a mislabeled percentile. The
        // favorite is lifted into its own pinned section above the grid.
        return teams.sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

    private var activeTeams: [String] {
        Set(viewModel.seasonPlayers.map { normalizedTeamAbbreviation($0.team) }).sorted()
    }

    /// The favorite, shown only when not actively searching so search results
    /// stay a single uninterrupted list.
    private var pinnedFavorite: String? {
        guard searchText.isEmpty, let fav = teamsViewModel.favoriteTeam else { return nil }
        return fav
    }

    /// All-teams grid with the pinned favorite removed so it isn't listed twice.
    private var gridTeams: [String] {
        guard let fav = pinnedFavorite else { return filteredTeams }
        return filteredTeams.filter { $0 != fav }
    }

    private var isInitiallyLoading: Bool {
        (viewModel.isLoading && activeTeams.isEmpty)
            || (viewModel.selectedPhase == .postseason
                && (viewModel.isLoadingPostseason || viewModel.postseasonLoadPending)
                && activeTeams.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isInitiallyLoading {
                    teamsLoadingState
                } else {
                    allTeamsSection
                }
                // Scroll-under spacer so the last grid row isn't trapped behind
                // the floating tab bar, matches the Dashboard pattern.
                Color.clear.frame(height: 88)
            }
            .padding(.top, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Red pill draws its own capsule, see StatsView.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { seasonMenu }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { seasonMenu }
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .onAppear(perform: autoEnterFavoriteIfNeeded)
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .teamView)
        }
        .sheet(item: $lockedSeasonTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    /// On first Teams visit, drop the user straight into their favorite team
    /// (the back button returns to the alphabetical list). Guarded so popping
    /// back or revisiting the tab doesn't trap them by re-pushing.
    private func autoEnterFavoriteIfNeeded() {
        guard !didAutoEnterFavorite,
              let favorite = teamsViewModel.favoriteTeam,
              path.isEmpty,
              activeTeams.contains(normalizedTeamAbbreviation(favorite)) else { return }
        didAutoEnterFavorite = true
        path.append(TeamDestination(abbr: favorite))
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

    // Nav-bar season selector, matches the Stats tab: a compact red pill with
    // calendar + year, sitting on the navy bar. Replaces the old in-content
    // season header card so Teams and Stats read the same.
    private var seasonMenu: some View {
        SeasonPhaseMenu(
            seasons: viewModel.availableSeasons,
            selectedSeason: viewModel.selectedSeason,
            selectedPhase: viewModel.selectedPhase,
            postseasonAvailable: viewModel.offersPhaseChoice,
            isLocked: { viewModel.isSeasonLocked($0) },
            onSelectSeason: { season in
                if viewModel.isSeasonLocked(season) {
                    lockedSeasonTrigger = .lockedSeason(season)
                } else {
                    viewModel.selectSeason(season)
                }
            },
            onSelectPhase: { viewModel.selectPhase($0) }
        ) {
            SavantNavPill(
                systemImage: "calendar",
                title: viewModel.selectedPhase == .postseason
                    ? "\(viewModel.selectedSeason) POST"
                    : String(viewModel.selectedSeason)
            )
        }
        .accessibilityHint("Choose which season's teams to view")
    }

    /// Logo grid replaces the old single-column list of rows. Each tile is a
    /// big colored disk with the abbreviation + full name, a corner star for
    /// favorites, and a long-press toggle so the row stays one-tap-to-navigate.
    private var allTeamsSection: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, accessibilityIdentifier: "teamsSearchField")
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            if let fav = pinnedFavorite {
                HStack {
                    Text("FAVORITE TEAM")
                        .font(SavantType.micro)
                        .tracking(0.6)
                        .foregroundStyle(SavantPalette.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                FavoriteTeamCard(
                    abbr: fav,
                    destination: TeamDestination(abbr: fav),
                    onRemove: {
                        teamsViewModel.removeFavorite()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }

            HStack {
                Text("ALL TEAMS")
                    .font(SavantType.micro)
                    .tracking(0.6)
                    .foregroundStyle(SavantPalette.inkSecondary)
                Spacer()
                if searchText.isEmpty {
                    Text("\(filteredTeams.count) teams")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                } else {
                    Button("Clear") { searchText = "" }
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if viewModel.selectedPhase == .postseason,
               let error = viewModel.postseasonErrorMessage,
               activeTeams.isEmpty {
                ContentUnavailableView {
                    Label("Postseason data unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.reloadPostseason() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SavantPalette.savantRed)
                }
                .padding(.vertical, 48)
            } else if viewModel.selectedPhase == .postseason,
                      viewModel.postseasonLoadCompleted,
                      activeTeams.isEmpty {
                ContentUnavailableView {
                    Label("Postseason teams not ready", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("The playoff games are in, but the latest team lines have not landed yet.")
                } actions: {
                    Button("Refresh") {
                        Task { await viewModel.reloadPostseason() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SavantPalette.savantRed)
                }
                .padding(.vertical, 48)
            } else if filteredTeams.isEmpty {
                let noDataForSeason = searchText.isEmpty && activeTeams.isEmpty
                ContentUnavailableView {
                    Label(noDataForSeason ? "No teams available" : "No teams found", systemImage: "magnifyingglass")
                } description: {
                    Text(noDataForSeason
                         ? "No teams have player data for the \(String(viewModel.selectedSeason)) \(viewModel.selectedPhase.label.lowercased())."
                         : "Try a different search term.")
                }
                .padding(.vertical, 48)
            } else if searchText.isEmpty {
                divisionGrid
            } else {
                // A search result has no meaningful division shape, so it falls
                // back to a flat run of whatever matched.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(gridTeams, id: \.self) { abbr in
                        teamDot(abbr)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    /// Six labelled rows of five. Sized so the whole league sits on one screen.
    private var divisionGrid: some View {
        VStack(spacing: 10) {
            ForEach(Self.divisions, id: \.name) { division in
                let teams = division.teams.filter { gridTeams.contains($0) }
                if !teams.isEmpty {
                    VStack(spacing: 6) {
                        HStack {
                            Text(division.name.uppercased())
                                .font(SavantType.micro)
                                .tracking(0.6)
                                .foregroundStyle(SavantPalette.inkTertiary)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            ForEach(teams, id: \.self) { abbr in
                                teamDot(abbr)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// One team: the color disk with its abbreviation, a favorite star when
    /// set, and a long-press to toggle it. No full team name, at five across
    /// there isn't room, and the cap colors plus abbreviation are how people
    /// recognise a club anyway.
    private func teamDot(_ abbr: String) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: TeamDestination(abbr: abbr)) {
                // The disk already carries the abbreviation, so no caption beneath,
                // it printed the same three letters twice and ate the vertical room
                // the six division rows need.
                VStack(spacing: 4) {
                    TeamAbbrDisk(abbr: abbr)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("team-\(abbr)")
            .accessibilityLabel(teamDisplayName(abbr))
            .accessibilityHint("View team details")

            Button {
                if teamsViewModel.isFavorite(abbr) {
                    teamsViewModel.removeFavorite()
                } else {
                    teamsViewModel.setFavorite(abbr)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: teamsViewModel.isFavorite(abbr) ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(teamsViewModel.isFavorite(abbr) ? Color.yellow : SavantPalette.inkTertiary)
                    .frame(width: 24, height: 24)
                    .background(SavantPalette.surface, in: Circle())
                    .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(teamsViewModel.isFavorite(abbr) ? "Remove favorite" : "Set as favorite")
            .offset(x: 4, y: -4)
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button {
                if teamsViewModel.isFavorite(abbr) {
                    teamsViewModel.removeFavorite()
                } else {
                    teamsViewModel.setFavorite(abbr)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(teamsViewModel.isFavorite(abbr) ? "Remove Favorite" : "Set as Favorite",
                      systemImage: teamsViewModel.isFavorite(abbr) ? "star.slash" : "star.fill")
            }
        }
    }
}

/// Team color disk with the abbreviation centered, the compact unit the
/// division grid is built from.
private struct TeamAbbrDisk: View {
    let abbr: String

    var body: some View {
        ZStack {
            Circle().fill(MLBTeamColor.color(abbr))
            Text(displayTeamAbbr(abbr))
                .font(SavantFont.condensed(13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
        .frame(width: 52, height: 52)
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Team Grid Tile

/// Large logo-led tile for the redesigned Teams grid. Tap to navigate; the
/// favorite star sits in the upper-right corner and the full team name reads
/// below the abbreviation disk. Long-press surfaces the favorite toggle.
struct TeamGridTile: View {
    let abbr: String
    let isFavorite: Bool
    var onFavoriteTap: (() -> Void)? = nil
    let destination: TeamDestination

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: destination) {
                tileBody
            }
            .buttonStyle(.plain)

            Button {
                onFavoriteTap?()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isFavorite ? Color.yellow : SavantPalette.inkTertiary)
                    .padding(6)
                    .background(Circle().fill(SavantPalette.surface))
                    .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? "Remove favorite" : "Set as favorite")
            .padding(6)
        }
    }

    private var tileBody: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MLBTeamColor.color(abbr))
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                Text(abbr)
                    .font(SavantFont.condensed(20, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(height: 64)

            Text(teamFullName(abbr))
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(isFavorite ? SavantPalette.surfaceAlt : SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(isFavorite ? SavantPalette.savantRed : SavantPalette.hairline,
                        lineWidth: isFavorite ? 1.5 : 0.5)
        )
    }
}

// MARK: - Favorite Team Card

/// Full-width "hero" row for the pinned favorite team. Reads as a featured item
/// distinct from the grid below, tap anywhere to open the team, tap the star to
/// unpin. This is what makes Favorite do something visible: your team is always
/// one tap away at the top of the list.
struct FavoriteTeamCard: View {
    let abbr: String
    let destination: TeamDestination
    var onRemove: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: destination) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(MLBTeamColor.color(abbr))
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                        Text(abbr)
                            .font(SavantFont.condensed(18, weight: .black))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR TEAM")
                            .font(SavantType.micro)
                            .tracking(0.6)
                            .foregroundStyle(SavantPalette.savantRed)
                        Text(teamFullName(abbr))
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .padding(.trailing, 36)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(SavantPalette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                        .stroke(SavantPalette.savantRed, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            Button {
                onRemove?()
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .padding(8)
                    .background(Circle().fill(SavantPalette.surface))
                    .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove favorite")
            .padding(10)
        }
    }
}

// MARK: - Team Row

struct TeamRowContent: View {
    let abbr: String
    let isFavorite: Bool

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
        TeamsView(viewModel: DashboardViewModel(), path: .constant(NavigationPath()))
            .environmentObject(StoreService.shared)
    }
}
#endif
