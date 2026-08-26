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

    private enum TeamSlot: Identifiable {
        case a, b
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
    // Team slots, with their own seasons for the same reason the player slots
    // have them: a club against its own past year is the comparison people
    // actually want, and it can't be asked without two years.
    @State private var teamA: String?
    @State private var teamB: String?
    @State private var teamSeasonA: Int?
    @State private var teamSeasonB: Int?
    @State private var teamPicker: TeamSlot?
    @State private var teamRoute: TeamComparisonRoute?

    private var activeSeasonA: Int { seasonA ?? viewModel.selectedSeason }
    private var activeSeasonB: Int { seasonB ?? viewModel.selectedSeason }
    private var activeTeamSeasonA: Int { teamSeasonA ?? viewModel.selectedSeason }
    private var activeTeamSeasonB: Int { teamSeasonB ?? viewModel.selectedSeason }

    /// The same club in the same year on both sides compares a roster with
    /// itself, and every row would tie. Any other pairing is fair game.
    private var isSameTeamContext: Bool {
        guard let teamA, let teamB else { return false }
        return normalizedTeamAbbreviation(teamA) == normalizedTeamAbbreviation(teamB)
            && activeTeamSeasonA == activeTeamSeasonB
    }

    private var canCompareTeams: Bool {
        teamA != nil && teamB != nil && !isSameTeamContext
    }

    /// Says why the button is off. The fix (change one side's season) isn't
    /// guessable from a greyed-out button.
    private var teamWarning: String? {
        guard isSameTeamContext, let teamA else { return nil }
        return "Both sides are \(teamFullName(teamA)) in \(String(activeTeamSeasonA)). Change one side's season to compare."
    }

    /// Clubs with data in a given season, so a slot can't be pointed at a team
    /// the year has nothing for.
    private func teamsWithData(season: Int) -> [String] {
        Set(viewModel.players(forSeason: season).map { normalizedTeamAbbreviation($0.team) })
            .sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

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
                        teamVsTeamCard
                        yearOverYearCard
                    }
                    .blur(radius: store.isPro ? 0 : 5)
                    .disabled(!store.isPro)
                    .allowsHitTesting(store.isPro)

                    if !store.isPro {
                        // The same gate every other locked module uses, rather
                        // than this screen's own floating panel.
                        BlurGateUnlock(
                            headline: "Stack any two players or any two clubs, and any of them against their own past seasons",
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
        .task(id: "\(activeSeasonA)-\(activeSeasonB)-\(activeTeamSeasonA)-\(activeTeamSeasonB)") {
            guard store.isPro,
                  activeSeasonA != viewModel.selectedSeason
                    || activeSeasonB != viewModel.selectedSeason
                    || activeTeamSeasonA != viewModel.selectedSeason
                    || activeTeamSeasonB != viewModel.selectedSeason
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
        .sheet(item: $teamPicker) { slot in
            let season = slot == .a ? activeTeamSeasonA : activeTeamSeasonB
            CompareTeamPicker(
                teams: teamsWithData(season: season),
                season: season,
                isLoading: viewModel.isHistoricalLoading
            ) { picked in
                if slot == .a { teamA = picked } else { teamB = picked }
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
            PlayerComparisonView(
                playerA: route.playerA,
                playerB: route.playerB,
                phase: route.phase,
                catalog: ComparisonCatalog(viewModel: viewModel, phase: route.phase)
            )
                .modifier(SavantNavBarPublic())
        }
        .navigationDestination(item: $teamRoute) { route in
            TeamComparisonView(
                route: route,
                leaguePlayersA: viewModel.players(forSeason: route.seasonA),
                leaguePlayersB: viewModel.players(forSeason: route.seasonB)
            )
                .modifier(SavantNavBarPublic())
        }
        .navigationDestination(item: $yearRoute) { route in
            YearCompareDestination(
                route: route,
                viewModel: viewModel,
                onChangePlayer: { picker = .yearPlayer }
            )
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

        HStack(spacing: 0) {
            if store.isPro {
                Button {
                    loadIntoSlot(player)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    followedRowLabel(player: player, inSlot: inSlot)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Loads \(player.name) into a comparison slot")

                // A Pro tap is spent on the slot, which left the list you
                // curated yourself with no way through to any of the pages it
                // names. The chevron is its own target and does the obvious
                // thing.
                    NavigationLink(value: PlayerRoute(
                        player: player,
                        phase: .regular,
                        season: player.season
                    )) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(width: 40, height: SavantGeo.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(player.name)'s page")
            } else {
                NavigationLink(value: PlayerRoute(
                    player: player,
                    phase: .regular,
                    season: player.season
                )) {
                    followedRowLabel(player: player, inSlot: inSlot)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(player.name)'s stats")
            }
        }
        .padding(.trailing, store.isPro ? 4 : 0)
        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
            alignment: .bottom
        )
        .contextMenu {
            NavigationLink(value: PlayerRoute(
                player: player,
                phase: .regular,
                season: player.season
            )) {
                Label("Open player page", systemImage: "person.text.rectangle")
            }
            Button(role: .destructive) {
                favorites.toggleFavorite(playerId: player.playerId)
            } label: {
                Label("Unfollow", systemImage: "star.slash")
            }
        }
    }

    private func followedRowLabel(player: Player, inSlot: Bool) -> some View {
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
                // The glyph states the outcome: a slot to fill for Pro (the
                // chevron beside it opens the page), a page to open for
                // everyone else.
                Image(systemName: store.isPro ? "plus.circle" : "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
        }
        .padding(.leading, SavantGeo.padInline)
        .padding(.trailing, store.isPro ? 6 : SavantGeo.padInline)
        .frame(height: SavantGeo.rowHeight)
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

    /// Two clubs, each with a year of its own. Same furniture as the player
    /// card above it, because it's the same question one level up.
    private var teamVsTeamCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "TEAM VS TEAM")

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    teamSlotColumn(
                        team: teamA,
                        placeholder: "Team A",
                        season: activeTeamSeasonA,
                        onPickTeam: { teamPicker = .a },
                        onPickSeason: { teamSeasonA = $0 }
                    )
                    Text("vs")
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .padding(.top, 40)
                    teamSlotColumn(
                        team: teamB,
                        placeholder: "Team B",
                        season: activeTeamSeasonB,
                        onPickTeam: { teamPicker = .b },
                        onPickSeason: { teamSeasonB = $0 }
                    )
                }

                if let teamWarning {
                    Text(teamWarning)
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    guard let teamA, let teamB, canCompareTeams else { return }
                    teamRoute = TeamComparisonRoute(
                        teamA: teamA,
                        teamB: teamB,
                        seasonA: activeTeamSeasonA,
                        seasonB: activeTeamSeasonB
                    )
                } label: {
                    Text("Compare Teams")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(canCompareTeams ? SavantPalette.savantRed : SavantPalette.inkTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canCompareTeams)
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

    private func teamSlotColumn(
        team: String?,
        placeholder: String,
        season: Int,
        onPickTeam: @escaping () -> Void,
        onPickSeason: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Button(action: onPickTeam) {
                VStack(spacing: 6) {
                    if let team {
                        ZStack {
                            Circle()
                                .fill(MLBTeamColor.color(team))
                                .frame(width: 44, height: 44)
                            Text(displayTeamAbbr(team))
                                .font(SavantType.micro)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        Text(teamFullName(team))
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
            .accessibilityLabel("Season for \(team.map(teamFullName) ?? placeholder)")
        }
        .frame(maxWidth: .infinity)
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
    /// Swaps the whole comparison onto a different player without going back.
    var onChangePlayer: (() -> Void)? = nil

    private var history: [Player] {
        viewModel.playerHistories[route.playerId] ?? []
    }

    /// Most recent season we hold for him, for the header identity.
    private var latest: Player? {
        history.max { ($0.season ?? 0) < ($1.season ?? 0) }
    }

    /// Who this is, a way through to his page, and a way to point the whole
    /// screen at somebody else. Without it the only route to a second player's
    /// history was back out to the tab and in again.
    @ViewBuilder
    private var playerBar: some View {
        HStack(spacing: 10) {
            if let latest {
                NavigationLink(value: PlayerRoute(
                    player: latest,
                    phase: .regular,
                    season: latest.season
                )) {
                    HStack(spacing: 10) {
                        PlayerHeadshot(team: latest.team, initials: latest.initials, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.playerName)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                                .lineLimit(1)
                            Text("\(displayTeamAbbr(latest.team)) · \(latest.displayPosition)")
                                .font(SavantType.micro)
                                .tracking(0.3)
                                .foregroundStyle(SavantPalette.inkTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(route.playerName)'s page")
            } else {
                Text(route.playerName)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
            }

            Spacer(minLength: 0)

            if let onChangePlayer {
                Button(action: onChangePlayer) {
                    SavantInlinePill(systemImage: "arrow.triangle.2.circlepath", title: "Change")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare a different player's seasons")
            }
        }
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.vertical, 10)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                playerBar
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
                // Clears the floating tab bar.
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(route.playerName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lightweight, self-contained player picker (the profile screen's picker is
/// private to that file). Shared with `PlayerComparisonView`, which offers the
/// same "swap this side out" choice from inside the comparison.
struct ComparePlayerPicker: View {
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
            // String(), not the Int: a number interpolated into a
            // LocalizedStringKey picks up the grouping separator and reads
            // "2,026".
            .navigationTitle(season.map { "Select Player · \(String($0))" } ?? "Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Team picker for the team-vs-team slots. Mirrors `ComparePlayerPicker`, so
/// filling a team slot works the way filling a player slot already does.
struct CompareTeamPicker: View {
    let teams: [String]
    /// Which season's clubs these are, so an empty list can say why.
    var season: Int? = nil
    var isLoading: Bool = false
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [String] {
        guard !searchText.isEmpty else { return teams }
        return teams.filter { teamMatchesQuery($0, query: searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { abbr in
                Button {
                    dismiss()
                    onSelect(abbr)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(MLBTeamColor.color(abbr))
                                .frame(width: 36, height: 36)
                            Text(displayTeamAbbr(abbr))
                                .font(SavantType.micro)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        Text(teamFullName(abbr))
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(isLoading ? "Loading teams…" : "No teams", systemImage: "flag.slash")
                    } description: {
                        if isLoading {
                            Text("Pulling the \(season.map(String.init) ?? "") season.")
                        } else if !searchText.isEmpty {
                            Text("Nobody matches “\(searchText)”.")
                        } else if let season {
                            Text("No team data for the \(String(season)) season.")
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search teams")
            .navigationTitle(season.map { "Select Team · \(String($0))" } ?? "Select Team")
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
