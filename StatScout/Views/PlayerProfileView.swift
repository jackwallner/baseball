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
    @State private var showingPaywall = false
    @State private var showingPlayerPicker = false
    @State private var comparisonPlayer: Player?

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
            return (category: cat, metrics: m.sorted { $0.percentile > $1.percentile })
        }
    }

    private var previewMetrics: [Metric] {
        Array(groupedMetrics.flatMap { $0.metrics }.sorted { $0.percentile > $1.percentile }.prefix(3))
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
                HStack(spacing: 12) {
                    Button {
                        if store.isPro {
                            showingPlayerPicker = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Compare with another player")
                    if let url = player.savantURL {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Open source page")
                    }
                }
            }
        }
        .sheet(isPresented: $showPercentileInfo) {
            PercentileInfoSheet()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerSheet(players: allPlayers.filter { $0.playerId != player.playerId }) { selected in
                comparisonPlayer = selected
            }
        }
        .background {
            if let other = comparisonPlayer {
                NavigationLink(
                    value: ComparisonRoute(playerA: player, playerB: other),
                    label: { EmptyView() }
                )
                .hidden()
                .onDisappear { comparisonPlayer = nil }
            }
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
            HStack(spacing: 4) {
                if !store.isPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                }
                Text(PlayerStatTab.yearCompare.rawValue)
                    .font(SavantType.bodyBold)
            }
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
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
            yearComparePreview
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

    private var yearComparePreview: some View {
        VStack(spacing: 12) {
            VStack(spacing: 14) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(SavantPalette.savantRed)
                Text("Compare seasons side by side")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Text("Pro unlocks year-over-year percentile trends so you can see what changed, what held, and where a player is moving.")
                    .font(SavantType.body)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                Button(store.proPrice.map { "Unlock Pro — \($0)" } ?? "Unlock Pro") {
                    showingPaywall = true
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
        }
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
                                showingPaywall = true
                            } else {
                                selectedPercentileSeason = season
                            }
                        } label: {
                            HStack {
                                Text(String(season))
                                if isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(SavantPalette.inkTertiary)
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
                let avg = displayedPlayer.percentile(for: group.category)
                SavantSubSectionBar(
                    title: "\(group.category.rawValue.uppercased())",
                    trailing: avg.map { "AVG \($0)" },
                    trailingColor: avg.map { SavantPalette.color(forPercentile: $0) } ?? SavantPalette.inkSecondary
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
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    HStack(spacing: 12) {
                        Text(stat.label)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(stat.value)
                            .font(SavantType.statMed)
                            .foregroundStyle(SavantPalette.ink)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, SavantGeo.padCard)
                    .frame(height: SavantGeo.rowHeight)
                    .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                    .overlay(
                        Rectangle()
                            .fill(SavantPalette.divider)
                            .frame(height: SavantGeo.hairline),
                        alignment: .bottom
                    )
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
                        PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 36)
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
