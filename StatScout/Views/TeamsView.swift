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
    @Binding var path: NavigationPath
    @State private var teamsViewModel = TeamsViewModel()
    @State private var searchText = ""
    @State private var showingPaywall = false
    // Auto-enter the favorite team once per launch; popping back must not
    // re-push it, or the user can never reach the list.
    @State private var didAutoEnterFavorite = false

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
        // Plain alphabetical by full team name — the old score-based / favorite-
        // first ordering was confusing and the score itself was a mislabeled
        // percentile. Favorites now auto-open instead of being pinned here.
        return teams.sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

    private var isInitiallyLoading: Bool {
        viewModel.isLoading && viewModel.teamsWithData.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isInitiallyLoading {
                    teamsLoadingState
                } else {
                    allTeamsSection
                }
            }
            .padding(.top, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { seasonMenu }
        }
        .refreshable {
            await viewModel.load()
        }
        .onAppear(perform: autoEnterFavoriteIfNeeded)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: .teamView)
        }
    }

    /// On first Teams visit, drop the user straight into their favorite team
    /// (the back button returns to the alphabetical list). Guarded so popping
    /// back or revisiting the tab doesn't trap them by re-pushing.
    private func autoEnterFavoriteIfNeeded() {
        guard !didAutoEnterFavorite,
              let favorite = teamsViewModel.favoriteTeam,
              path.isEmpty else { return }
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

    // Nav-bar season selector — matches the Stats tab: a compact red pill with
    // calendar + year, sitting on the navy bar. Replaces the old in-content
    // season header card so Teams and Stats read the same.
    private var seasonMenu: some View {
        Menu {
            if viewModel.isHistoricalLoading {
                Label("Loading past seasons…", systemImage: "hourglass")
            } else if !viewModel.hasLoadedHistorical {
                Button {
                    if store.isPro {
                        Task { await viewModel.loadHistoricalIfNeeded() }
                    } else if PaywallGate.shared.shouldPresent(.teamView) {
                        showingPaywall = true
                    }
                } label: {
                    Label(store.isPro ? "Load past seasons" : "Past seasons require Pro",
                          systemImage: store.isPro ? "clock.arrow.circlepath" : "crown.fill")
                }
            }
            ForEach(viewModel.availableSeasons, id: \.self) { season in
                let isLocked = viewModel.isSeasonLocked(season)
                Button {
                    if isLocked {
                        if PaywallGate.shared.shouldPresent(.teamView) { showingPaywall = true }
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
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(viewModel.selectedSeason))
                    .font(SavantType.smallBold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SavantPalette.savantRed)
            .clipShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Season")
        .accessibilityValue(String(viewModel.selectedSeason))
    }

    private var allTeamsSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "TEAMS",
                trailing: searchText.isEmpty ? AnyView(
                    Text("\(filteredTeams.count) teams")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                ) : AnyView(
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
                ForEach(Array(filteredTeams.enumerated()), id: \.element) { index, abbr in
                    HStack(spacing: 0) {
                        NavigationLink(value: TeamDestination(abbr: abbr)) {
                            TeamRowContent(
                                abbr: abbr,
                                isFavorite: teamsViewModel.isFavorite(abbr)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            let isFav = teamsViewModel.isFavorite(abbr)
                            if isFav {
                                teamsViewModel.removeFavorite()
                            } else {
                                teamsViewModel.setFavorite(abbr)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: teamsViewModel.isFavorite(abbr) ? "star.fill" : "star")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(teamsViewModel.isFavorite(abbr) ? Color.yellow : SavantPalette.inkTertiary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.trailing, 12)

                    if index < filteredTeams.count - 1 {
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
