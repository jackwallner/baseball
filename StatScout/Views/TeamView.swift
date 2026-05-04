import SwiftUI

struct TeamView: View {
    let team: String
    let players: [Player]
    @State private var searchText = ""
    @State private var selectedCategory: MetricCategory? = .hitting
    @State private var sortDescending = true

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
        sortMetric?.label ?? "Overall"
    }

    private func score(_ player: Player) -> Int {
        if let m = sortMetric, let metric = player.metrics.first(where: { $0.label == m.label && $0.category == m.category }) {
            return metric.percentile
        }
        if let category = selectedCategory, let p = player.percentile(for: category) {
            return p
        }
        return player.overallPercentile
    }

    private var filteredPlayers: [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        let byCategory = selectedCategory == nil
            ? bySearch
            : bySearch.filter { p in p.metrics.contains { $0.category == selectedCategory } }
        return byCategory.sorted {
            sortDescending ? score($0) > score($1) : score($0) < score($1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TeamIdentityStrip(team: team, season: players.compactMap(\.season).max())

                CategoryFilter(selectedCategory: $selectedCategory)

                rosterSection
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle(teamFullName(team))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = savantTeamURL(for: team) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .foregroundStyle(.white)
                    }
                }
            }
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
                    description: "No players are currently tracked for \(teamFullName(team)). Check back after the nightly update."
                )
            } else {
                SearchField(text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                if filteredPlayers.isEmpty {
                    emptyStateView(
                        icon: "magnifyingglass",
                        title: "No players found",
                        description: "Try a different search term."
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

    private func savantTeamURL(for abbr: String) -> URL? {
        let normalized = normalizedTeamAbbreviation(abbr).lowercased()
        return URL(string: "https://baseballsavant.mlb.com/team/\(normalized)")
    }

    private func priorityMetrics(for category: MetricCategory) -> [String] {
        switch category {
        case .hitting: return ["xwOBA", "xSLG", "xBA"]
        case .pitching: return ["Barrel%", "xwOBA", "K%", "Whiff%", "Chase%"]
        case .fielding: return ["Range (OAA)", "Arm Strength", "Arm Value"]
        case .running: return ["Sprint Speed"]
        }
    }
}

#Preview {
    NavigationStack {
        TeamView(
            team: "NYY",
            players: SampleData.players.filter { $0.team == "NYY" }
        )
    }
}
