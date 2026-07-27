import SwiftUI

/// Year-over-year history destination. Carries just the player id; the
/// destination rebuilds the season history from the view model so the route
/// stays cheap and Hashable.
struct YearCompareRoute: Hashable {
    let playerId: Int
    let playerName: String
}

/// Dedicated "Compare" tab, and the home of the players you follow.
///
/// The comparison flows also live inside the player profile (Year Compare tab +
/// the compare toolbar button); this tab doesn't replace those, it puts both
/// head-to-head and year-over-year one tap away, and blurs them behind a trial
/// pitch for non-Pro users.
///
/// Following used to be managed from the Trends board, which made Trends do two
/// jobs, a league leaderboard and a personal list, and left the tab you'd
/// look for your own players in with no mention of them. The list lives here
/// now, above the comparison cards it feeds, and stays free: following is what
/// makes the app feel like yours, and what's paid is the payoff.
struct CompareView: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel

    private enum PickerTarget: Identifiable {
        case playerA, playerB, yearPlayer
        var id: Int { hashValue }
    }

    @State private var playerA: Player?
    @State private var playerB: Player?
    @State private var picker: PickerTarget?
    @State private var comparisonRoute: ComparisonRoute?
    @State private var yearRoute: YearCompareRoute?
    @State private var showingTrial = false
    @State private var showingFollowSheet = false
    @State private var favorites = FavoritesStore.shared
    // Each slot carries its own season, so a comparison can cross years,
    // 2025 Raleigh against 2026 Dingler. Nil means "whatever season the app is
    // currently on", resolved lazily so a season change elsewhere doesn't
    // silently pin these to a stale year.
    @State private var seasonA: Int?
    @State private var seasonB: Int?

    private var activeSeasonA: Int { seasonA ?? viewModel.selectedSeason }
    private var activeSeasonB: Int { seasonB ?? viewModel.selectedSeason }

    private func players(forSeason season: Int) -> [Player] {
        viewModel.players(forSeason: season).sorted { $0.name < $1.name }
    }

    /// The slot's player as he was in the slot's season. A player picked in one
    /// year and then moved to another resolves through his own history rather
    /// than carrying the wrong season's numbers into the comparison.
    private func resolved(_ player: Player?, season: Int) -> Player? {
        guard let player else { return nil }
        if player.season == season { return player }
        return viewModel.playerHistories[player.playerId]?.first { $0.season == season }
    }

    private var resolvedA: Player? { resolved(playerA, season: activeSeasonA) }
    private var resolvedB: Player? { resolved(playerB, season: activeSeasonB) }

    /// Why the Compare button is off, when a slot is filled but unusable.
    private var slotWarning: String? {
        if viewModel.isHistoricalLoading, resolvedA == nil || resolvedB == nil {
            return "Loading past seasons…"
        }
        if let playerA, resolvedA == nil {
            return "No \(activeSeasonA) data for \(playerA.name)."
        }
        if let playerB, resolvedB == nil {
            return "No \(activeSeasonB) data for \(playerB.name)."
        }
        return nil
    }

    /// The followed players that exist in the selected season, in the order
    /// they were followed.
    private var followedPlayers: [Player] {
        let roster = viewModel.players(forSeason: viewModel.selectedSeason)
        return favorites.playerIds.compactMap { id in
            roster.first { $0.playerId == id }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                yourPlayersCard

                // Only the comparison cards blur. Following is free, so putting
                // the whole page behind the gate would have hidden the one
                // thing a free user can actually do here.
                ZStack(alignment: .bottom) {
                    VStack(spacing: 12) {
                        playerVsPlayerCard
                        yearOverYearCard
                    }
                    .blur(radius: store.isPro ? 0 : 5)
                    .disabled(!store.isPro)
                    .allowsHitTesting(store.isPro)

                    if !store.isPro {
                        // The same gate every other locked module uses, rather
                        // than this screen's own floating panel.
                        BlurGateUnlock(
                            headline: "Stack any two players, or any player against his own past seasons",
                            trigger: .playerComparison
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
            // Scroll-under spacer so content can pass behind the floating tab
            // bar, matches the Dashboard / Teams pattern.
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFollowSheet) {
            FollowPlayersSheet(viewModel: viewModel)
        }
        .onAppear {
            if store.isPro, !viewModel.hasLoadedHistorical, !viewModel.isHistoricalLoading {
                Task { await viewModel.loadHistoricalIfNeeded() }
            }
        }
        // Past seasons only exist once the history load has run, and a slot
        // pinned to 2025 is useless without it.
        .task(id: "\(activeSeasonA)-\(activeSeasonB)") {
            guard store.isPro,
                  activeSeasonA != viewModel.selectedSeason || activeSeasonB != viewModel.selectedSeason
            else { return }
            await viewModel.loadHistoricalIfNeeded()
        }
        .sheet(item: $picker) { target in
            // Each slot picks from its own season's roster, and the other
            // slot's pick is hidden so a player can't be compared to himself.
            let season: Int = {
                switch target {
                case .playerA: return activeSeasonA
                case .playerB: return activeSeasonB
                case .yearPlayer: return viewModel.selectedSeason
                }
            }()
            ComparePlayerPicker(
                players: players(forSeason: season).filter { candidate in
                    switch target {
                    case .playerA: return candidate.playerId != playerB?.playerId
                    case .playerB: return candidate.playerId != playerA?.playerId
                    case .yearPlayer: return true
                    }
                },
                season: season,
                isLoading: viewModel.isHistoricalLoading
            ) { selected in
                switch target {
                case .playerA: playerA = selected
                case .playerB: playerB = selected
                case .yearPlayer:
                    comparisonRoute = nil
                    yearRoute = YearCompareRoute(playerId: selected.playerId, playerName: selected.name)
                }
            }
        }
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .playerComparison)
        }
        // Just the player route, not the whole StandardDestinations bundle,
        // this file declares its own ComparisonRoute destination, and two
        // registrations for one type is a runtime conflict.
        .modifier(PlayerProfileDestination(viewModel: viewModel))
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(playerA: route.playerA, playerB: route.playerB)
                .modifier(SavantNavBarPublic())
        }
        .navigationDestination(item: $yearRoute) { route in
            YearCompareDestination(route: route, viewModel: viewModel)
                .modifier(SavantNavBarPublic())
        }
    }

    /// The followed list. Free, and the first thing on the tab: it's the only
    /// personal state the app holds, and it feeds the slots below it.
    private var yourPlayersCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "YOUR PLAYERS",
                trailing: AnyView(
                    Button {
                        showingFollowSheet = true
                    } label: {
                        Label(favorites.playerIds.isEmpty ? "Add" : "Edit", systemImage: "star")
                            .font(SavantType.micro)
                            .tracking(0.3)
                            .foregroundStyle(SavantPalette.savantRed)
                    }
                    .buttonStyle(.plain)
                )
            )

            if followedPlayers.isEmpty {
                VStack(spacing: 8) {
                    Text("Follow players to keep them one tap from a comparison, and to spot them on the Trends board.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showingFollowSheet = true
                    } label: {
                        Text("Follow players")
                            .font(SavantType.smallBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: SavantControl.height)
                            .background(SavantPalette.savantRed)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(followedPlayers.enumerated()), id: \.element.playerId) { index, player in
                    followedRow(player: player, index: index)
                }
                Text(store.isPro
                     ? "Tap a player to load them into a slot below."
                     : "Tap a player to see their stats. Head-to-head needs StatScout+.")
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SavantGeo.padCard)
                    .padding(.vertical, 10)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    /// A followed player, and what tapping him does.
    ///
    /// For Pro that's "load into a comparison slot". For everyone else it's
    /// "open his page", his own stats are free, so a free tap used to throw up
    /// the comparison pitch and give the user nothing, on a list they built
    /// themselves. Head-to-head is what's paid; a player's own numbers never
    /// were. The pitch is still one row further down, on the blurred cards that
    /// actually need it.
    @ViewBuilder
    private func followedRow(player: Player, index: Int) -> some View {
        let inSlot = playerA?.playerId == player.playerId || playerB?.playerId == player.playerId

        Group {
            if store.isPro {
                Button {
                    loadIntoSlot(player)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    followedRowLabel(player: player, index: index, inSlot: inSlot)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Loads \(player.name) into a comparison slot")
            } else {
                NavigationLink(value: player) {
                    followedRowLabel(player: player, index: index, inSlot: inSlot)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(player.name)'s stats")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                favorites.toggleFavorite(playerId: player.playerId)
            } label: {
                Label("Unfollow", systemImage: "star.slash")
            }
        }
    }

    private func followedRowLabel(player: Player, index: Int, inSlot: Bool) -> some View {
        HStack(spacing: 10) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                    .lineLimit(1)
                Text("\(displayTeamAbbr(player.team)) · \(player.displayPosition)")
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            Spacer(minLength: 0)
            if inSlot {
                Text("IN SLOT")
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SavantPalette.savantRed)
                    .clipShape(Capsule())
            } else {
                // The glyph states the outcome: a slot to fill for Pro, a page
                // to open for everyone else.
                Image(systemName: store.isPro ? "plus.circle" : "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
        }
        .padding(.horizontal, SavantGeo.padInline)
        .frame(height: SavantGeo.rowHeight)
        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
        .contentShape(Rectangle())
    }

    /// Fills the first empty slot, then replaces the older of the two, so
    /// tapping down a list keeps swapping the challenger against a held player
    /// rather than clearing both.
    private func loadIntoSlot(_ player: Player) {
        if playerA == nil || playerA?.playerId == player.playerId {
            playerA = player
        } else if playerB == nil || playerB?.playerId == player.playerId {
            playerB = player
        } else {
            playerB = player
        }
    }

    private var playerVsPlayerCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "PLAYER VS PLAYER")

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    slotColumn(
                        player: playerA,
                        placeholder: "Player A",
                        season: activeSeasonA,
                        onPickPlayer: { picker = .playerA },
                        onPickSeason: { seasonA = $0 }
                    )
                    Text("vs")
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .padding(.top, 40)
                    slotColumn(
                        player: playerB,
                        placeholder: "Player B",
                        season: activeSeasonB,
                        onPickPlayer: { picker = .playerB },
                        onPickSeason: { seasonB = $0 }
                    )
                }

                if let slotWarning {
                    Text(slotWarning)
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    if let a = resolvedA, let b = resolvedB {
                        comparisonRoute = ComparisonRoute(playerA: a, playerB: b)
                    }
                } label: {
                    Text("Compare")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(resolvedA != nil && resolvedB != nil
                                    ? SavantPalette.savantRed
                                    : SavantPalette.inkTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(resolvedA == nil || resolvedB == nil)
            }
            .padding(16)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var yearOverYearCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "YEAR OVER YEAR")

            VStack(spacing: 12) {
                Text("Pick a player to see how their percentile rankings moved across every season.")
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    picker = .yearPlayer
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Choose a player")
                            .font(SavantType.bodyBold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(SavantPalette.savantRed)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    /// A slot: the player, and the season he's being taken from. The season
    /// picker is the whole point of the pair, without it the tab could only
    /// ever compare two players inside the same year.
    private func slotColumn(
        player: Player?,
        placeholder: String,
        season: Int,
        onPickPlayer: @escaping () -> Void,
        onPickSeason: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            playerSlot(player: player, placeholder: placeholder, action: onPickPlayer)

            SeasonMenu(
                seasons: viewModel.availableSeasons,
                selected: season,
                isLocked: { viewModel.isSeasonLocked($0) },
                onSelect: { picked in
                    if viewModel.isSeasonLocked(picked) {
                        showingTrial = true
                    } else {
                        onPickSeason(picked)
                    }
                }
            ) {
                SavantInlinePill(systemImage: "calendar", title: String(season))
            }
            .accessibilityLabel("Season for \(player?.name ?? placeholder)")
        }
        .frame(maxWidth: .infinity)
    }

    private func playerSlot(player: Player?, placeholder: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let player {
                    PlayerHeadshot(team: player.team, initials: player.initials, size: 44)
                    Text(player.name)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    ZStack {
                        Circle()
                            .fill(SavantPalette.surfaceAlt)
                            .frame(width: 44, height: 44)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                    Text(placeholder)
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(SavantPalette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

}

/// Resolves a `YearCompareRoute` into the player's season history and renders
/// the existing year-over-year comparison. Empty-history players surface a
/// graceful message instead of a blank screen.
private struct YearCompareDestination: View {
    let route: YearCompareRoute
    let viewModel: DashboardViewModel

    private var history: [Player] {
        viewModel.playerHistories[route.playerId] ?? []
    }

    var body: some View {
        ScrollView {
            if history.count < 2 {
                ContentUnavailableView {
                    Label("Not enough history", systemImage: "calendar.badge.clock")
                } description: {
                    Text(viewModel.isHistoricalLoading
                         ? "Loading past seasons for \(route.playerName)…"
                         : "\(route.playerName) doesn't have multiple seasons of data to compare.")
                }
                .padding(.vertical, 64)
            } else {
                YearComparisonView(history: history)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(route.playerName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lightweight, self-contained player picker (the profile screen's picker is
/// private to that file).
private struct ComparePlayerPicker: View {
    let players: [Player]
    /// Which season's roster this is, so an empty list can say why.
    var season: Int? = nil
    var isLoading: Bool = false
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Player] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.team.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { player in
                Button {
                    dismiss()
                    onSelect(player)
                } label: {
                    HStack(spacing: 12) {
                        PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                            Text("\(player.team) · \(player.displayPosition)")
                                .font(SavantType.small)
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            // A past season's roster doesn't exist until the history load
            // finishes; without this the sheet is a blank list with no reason
            // given.
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(isLoading ? "Loading players…" : "No players", systemImage: "person.slash")
                    } description: {
                        if isLoading {
                            Text("Pulling the \(season.map(String.init) ?? "") roster.")
                        } else if !searchText.isEmpty {
                            Text("Nobody matches “\(searchText)”.")
                        } else if let season {
                            Text("No player data for the \(String(season)) season.")
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
            .navigationTitle(season.map { "Select Player · \($0)" } ?? "Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Public mirror of RootTabView's private SavantNavBar so destinations pushed
/// from this file keep the same navy bar treatment.
struct SavantNavBarPublic: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(SavantPalette.savantNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CompareView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
