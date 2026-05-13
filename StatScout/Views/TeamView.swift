import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let players: [Player]
    var season: Int? = nil
    var viewModel: DashboardViewModel? = nil
    @State private var searchText = ""
    @State private var selectedCategory: MetricCategory? = nil
    @State private var sortDescending = true
    @State private var showingPaywall = false

    private var displaySeason: Int {
        season ?? players.compactMap(\.season).max() ?? Calendar.current.component(.year, from: Date())
    }

    private var sortMetric: (label: String, category: MetricCategory)? {
        guard let category = selectedCategory else { return nil }
        for label in priorityMetrics(for: category) {
            if players.contains(where: { p in p.metrics.contains { $0.label == label && $0.category == category } }) {
                return (label, category)
            }
        }
        return nil
    }

    private var sortLabel: String {
        if selectedCategory == nil { return "xwOBA" }
        return sortMetric?.label ?? "Top Category"
    }

    private func score(_ player: Player) -> Int {
        if let m = sortMetric, let metric = player.metrics.first(where: { $0.label == m.label && $0.category == m.category }) {
            return metric.percentile
        }
        if let category = selectedCategory {
            if let p = player.percentile(for: category) { return p }
        }
        return player.metrics.first(where: { $0.label == "xwOBA" })?.percentile ?? 0
    }

    private var filteredPlayers: [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        let byType = bySearch.filter { $0.matchesPlayerType(for: selectedCategory) }
        let byCategory = selectedCategory == nil
            ? byType
            : byType.filter { p in p.metrics.contains { $0.category == selectedCategory } }
        return byCategory.sorted {
            sortDescending ? score($0) > score($1) : score($0) < score($1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: displaySeason)

                if let viewModel {
                    teamSeasonMenu(viewModel: viewModel)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }

                CategoryFilter(selectedCategory: $selectedCategory)

                rosterSection
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(teamFullName(team))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: .teamView)
        }
    }

    private var rosterSection: some View {
        VStack(spacing: 0) {
            SavantSectionBar(
                title: "ROSTER",
                trailing: players.isEmpty ? nil : AnyView(
                    Button(action: {
                        sortDescending.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        HStack(spacing: 4) {
                            Text(sortLabel)
                            Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                        }
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkSecondary)
                    }
                )
            )

            if players.isEmpty {
                emptyStateView(
                    icon: "person.2.slash",
                    title: "No players tracked",
                    description: "No players are tracked for \(teamFullName(team)) in the \(String(displaySeason)) season."
                )
            } else {
                SearchField(text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                if filteredPlayers.isEmpty {
                    let noCategoryMatch = searchText.isEmpty && selectedCategory != nil
                    emptyStateView(
                        icon: "magnifyingglass",
                        title: "No players found",
                        description: noCategoryMatch
                            ? "No players match the selected category for this team."
                            : "Try a different search term."
                    )
                } else {
                    LeaderboardTableHeader(sortDescending: sortDescending, sortLabel: sortLabel)
                    ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                        NavigationLink(value: player) {
                            LeaderboardTableRow(
                                rank: index + 1,
                                player: player,
                                metricLabel: sortMetric?.label,
                                metricCategory: sortMetric?.category
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
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateView(icon: String, title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        }
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private func teamSeasonMenu(viewModel: DashboardViewModel) -> some View {
        HStack {
            Menu {
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
                                    .foregroundStyle(Color.yellow)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Season")
                        .font(SavantType.micro)
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(String(viewModel.selectedSeason))
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(SavantPalette.savantRed)
                .clipShape(Capsule())
            }
            .menuOrder(.fixed)
            .fixedSize()
            Spacer()
        }
    }

    private func priorityMetrics(for category: MetricCategory) -> [String] {
        switch category {
        case .hitting: return ["xwOBA", "xSLG", "xBA"]
        case .pitching: return ["xwOBA", "K%", "Barrel%", "Whiff%", "Chase%"]
        case .fielding: return ["Range (OAA)", "Arm Strength", "Arm Value"]
        case .running: return ["Sprint Speed"]
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TeamView(
            team: "NYY",
            players: SampleData.players.filter { $0.team == "NYY" },
            season: 2026
        )
    }
}
#endif
