import SwiftUI

struct PlayerProfileView: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let history: [Player]
    var allPlayers: [Player] = []
    var isHistoricalLoading = false
    var hasLoadedHistorical = true
    var historicalLoadingMessage = "Loading past seasons…"
    var historicalLoadingProgress = 0.12
    var loadHistorical: (() async -> Void)?
    @State private var showPercentileInfo = false
    @State private var selectedTab: PlayerStatTab = .statcast
    @State private var selectedPercentileSeason: Int? = nil
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingPlayerPicker = false
    @State private var comparisonRoute: ComparisonRoute?

    enum PlayerStatTab: String, CaseIterable {
        case statcast = "Percentiles"
        case standard = "Standard Stats"
        case yearCompare = "Year Compare"
    }

    private var availablePercentileSeasons: [Int] {
        let fromHistory = history.compactMap(\.season)
        var set = Set(fromHistory)
        if let s = player.season { set.insert(s) }
        return Array(set).sorted(by: >)
    }

    private var activeSeason: Int? {
        selectedPercentileSeason ?? player.season
    }

    private var displayedPlayer: Player {
        guard let season = activeSeason else { return player }
        return history.first { $0.season == season } ?? player
    }

    private var seasonLabel: String {
        activeSeason.map(String.init) ?? "—"
    }

    private var groupedMetrics: [(category: MetricCategory, metrics: [Metric])] {
        let grouped = Dictionary(grouping: displayedPlayer.metrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let m = grouped[cat], !m.isEmpty else { return nil }
            return (category: cat, metrics: m.sorted { cat.sortMetrics($0.label, $1.label) })
        }
    }

    /// Baseball Savant's fixed metric ordering per category so the layout is consistent
    /// across players — makes it easy to find the same stat in the same spot every time.
    private var previewMetrics: [Metric] {
        Array(groupedMetrics.flatMap { $0.metrics }.sorted { $0.percentile > $1.percentile }.prefix(3))
    }

    /// Players eligible for comparison: same player type (hitter↔hitter, pitcher↔pitcher),
    /// sorted by xwOBA proximity to the current player so the closest match is first.
    private var comparablePlayers: [Player] {
        let myType = player.playerType
        let pool = allPlayers.filter { other in
            guard other.playerId != player.playerId else { return false }
            switch myType {
            case "pitcher": return other.playerType == "pitcher"
            case "batter", "hitter": return other.playerType != "pitcher"
            case "two_way": return true
            default: return other.playerType == myType
            }
        }
        let myXwoba = player.metrics.first { $0.label == "xwOBA" }?.percentile
        guard let mine = myXwoba else { return pool }
        return pool.sorted { a, b in
            let ax = a.metrics.first { $0.label == "xwOBA" }?.percentile
            let bx = b.metrics.first { $0.label == "xwOBA" }?.percentile
            switch (ax, bx) {
            case let (.some(av), .some(bv)):
                return abs(av - mine) < abs(bv - mine)
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.name < b.name
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlayerIdentityStrip(player: player)

                tabSelector
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                switch selectedTab {
                case .statcast:
                    statcastContent
                case .standard:
                    standardContent
                case .yearCompare:
                    yearCompareContent
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if store.isPro {
                        showingPlayerPicker = true
                    } else {
                        paywallTrigger = .playerComparison
                    }
                } label: {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Compare with another player")
            }
        }
        .sheet(isPresented: $showPercentileInfo) {
            PercentileInfoSheet()
        }
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerSheet(players: comparablePlayers) { selected in
                comparisonRoute = ComparisonRoute(playerA: player, playerB: selected)
            }
        }
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(playerA: route.playerA, playerB: route.playerB)
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 8) {
            statcastTabButton
            standardTabButton
            yearCompareTabButton
        }
    }

    private var statcastTabButton: some View {
        let isSelected = selectedTab == .statcast
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .statcast
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.statcast.rawValue)
                .font(SavantType.bodyBold)
                .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var standardTabButton: some View {
        let isSelected = selectedTab == .standard
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .standard
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.standard.rawValue)
                .font(SavantType.bodyBold)
                .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var yearCompareTabButton: some View {
        let isSelected = selectedTab == .yearCompare
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .yearCompare
            }
            if store.isPro, !hasLoadedHistorical, !isHistoricalLoading {
                Task { await loadHistorical?() }
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.yearCompare.rawValue)
                .font(SavantType.bodyBold)
                .foregroundStyle(isSelected ? .white : SavantPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var statcastContent: some View {
        VStack(spacing: 12) {
            percentileRankingsCard

            if !store.isPro {
                proUpsellCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var proUpsellCard: some View {
        Button {
            paywallTrigger = .upgrade
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Track year-over-year trends")
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                    Text("See how \(player.name)'s metrics evolved across seasons with Pro.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .padding(12)
            .background(SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                    .stroke(SavantPalette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var standardContent: some View {
        VStack(spacing: 12) {
            standardStatsGridCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var yearCompareContent: some View {
        if store.isPro {
            if isHistoricalLoading {
                historicalLoadingCard
            } else if !hasLoadedHistorical, loadHistorical != nil {
                loadHistoricalCard
            } else {
                YearComparisonView(history: history)
            }
        } else {
            YearComparePreview(playerName: player.name) {
                paywallTrigger = .yearCompare
            }
        }
    }

    private var historicalLoadingCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: min(max(historicalLoadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(SavantPalette.savantRed)
            Text(historicalLoadingMessage)
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("\(Int(min(max(historicalLoadingProgress, 0), 1) * 100))%")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var loadHistoricalCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(SavantPalette.savantRed)
            Text("Load past seasons")
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
            Text("Year Compare loads historical data only when you need it.")
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Load History") {
                Task { await loadHistorical?() }
            }
            .buttonStyle(.borderedProminent)
            .tint(SavantPalette.savantRed)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Cards

    private var seasonMenu: some View {
        let seasons = availablePercentileSeasons
        return Group {
            if seasons.count > 1 {
                Menu {
                    ForEach(seasons, id: \.self) { season in
                        let isLocked = season != 2026 && !store.isPro
                        Button {
                            if isLocked {
                                paywallTrigger = .pastSeason
                            } else {
                                selectedPercentileSeason = season
                            }
                        } label: {
                            HStack {
                                Text(String(season))
                                if isLocked {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.yellow)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(seasonLabel)
                            .font(SavantType.micro)
                            .tracking(0.5)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SavantPalette.inkSecondary)
                    }
                }
                .menuOrder(.fixed)
            } else {
                Text(seasonLabel)
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
        }
    }

    private var percentileRankingsCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "PERCENTILE RANKINGS",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        seasonMenu
                        Button(action: { showPercentileInfo = true }) {
                            Text("ⓘ")
                                .font(SavantType.micro)
                                .foregroundStyle(SavantPalette.linkBlue)
                        }
                        .buttonStyle(.plain)
                    }
                )
            )

            if groupedMetrics.isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "No metrics available",
                    description: "Percentile rankings are not available for this player in the \(seasonLabel) season."
                )
                .padding(.vertical, 24)
            } else {
                ForEach(groupedMetrics, id: \.category) { group in
                SavantSubSectionBar(
                    title: "\(group.category.rawValue.uppercased())"
                )

                ForEach(Array(group.metrics.enumerated()), id: \.element.id) { index, metric in
                    NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
                        MetricBar(metric: metric)
                            .padding(.horizontal, SavantGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                            .overlay(
                                Rectangle()
                                    .fill(SavantPalette.divider)
                                    .frame(height: SavantGeo.hairline),
                                alignment: .bottom
                            )
                    }
                    .buttonStyle(.plain)
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
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "STANDARD STATS · \(seasonLabel)",
                trailing: AnyView(seasonMenu)
            )

            if (displayedPlayer.standardStats ?? []).isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "Standard stats unavailable",
                    description: "Traditional stats are not available for this player."
                )
                .padding(.vertical, 24)
            } else {
                let stats = displayedPlayer.standardStats ?? []
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1)
                    ],
                    spacing: 1
                ) {
                    ForEach(stats) { stat in
                        VStack(spacing: 4) {
                            Text(stat.label.uppercased())
                                .font(SavantType.micro)
                                .tracking(0.4)
                                .foregroundStyle(SavantPalette.inkTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(stat.value)
                                .font(SavantType.statMed)
                                .foregroundStyle(SavantPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SavantPalette.surface)
                    }
                }
                .background(SavantPalette.divider)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

}

struct PercentileInfoSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Percentile Rankings")
                        .font(SavantType.playerName)
                        .foregroundStyle(SavantPalette.ink)

                    Text("Percentile rankings compare a player to others at the same position. A 90th percentile means the player ranks in the top 10% of the league for that metric.")
                        .font(SavantType.body)
                        .foregroundStyle(SavantPalette.inkSecondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Elite (75–100): Red bars", systemImage: "flame.fill")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.pctlHot)
                        Label("Average (25–75): Gray bars", systemImage: "minus")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.inkSecondary)
                        Label("Below Average (0–25): Blue bars", systemImage: "snowflake")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.pctlCold)
                    }
                    .padding(.vertical, 8)

                    Text("Data refreshes nightly from public baseball percentile leaderboards. Not all metrics are available for every player due to qualifying thresholds.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                .padding(24)
            }
            .background(SavantPalette.canvas.ignoresSafeArea())
            .navigationTitle("About Percentiles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlayerPickerSheet: View {
    let players: [Player]
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredPlayers: [Player] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.team.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredPlayers) { player in
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
            .navigationTitle("Compare With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerProfileView(player: SampleData.players[0], history: [SampleData.players[0]])
            .environmentObject(StoreService.shared)
    }
}
#endif
