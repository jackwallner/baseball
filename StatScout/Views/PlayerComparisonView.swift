import SwiftUI

struct ComparisonRoute: Hashable, Identifiable {
    let playerA: Player
    let playerB: Player
    var phase: SeasonPhase = .regular
    var id: String { "\(playerA.id)-vs-\(playerB.id)-\(phase.rawValue)" }
}

/// Everything a comparison screen needs to swap a side out without owning the
/// dashboard: which seasons exist, who played in each of them, and how to
/// resolve a player into a different year.
///
/// Passed in rather than reached for, because the two screens that push a
/// comparison hold different things, the Compare tab has the view model, the
/// player profile has a bag of closures. Absent means "this comparison is
/// fixed", and the editing controls simply don't draw.
struct ComparisonCatalog {
    var seasons: [Int] = []
    var roster: (Int) -> [Player] = { _ in [] }
    var resolve: (Player, Int) -> Player? = { player, season in
        player.season == season ? player : nil
    }
    var isSeasonLocked: (Int) -> Bool = { _ in false }
    var isLoadingHistory: Bool = false
    var loadHistory: (() async -> Void)? = nil

    init(
        seasons: [Int] = [],
        roster: @escaping (Int) -> [Player] = { _ in [] },
        resolve: @escaping (Player, Int) -> Player? = { player, season in
            player.season == season ? player : nil
        },
        isSeasonLocked: @escaping (Int) -> Bool = { _ in false },
        isLoadingHistory: Bool = false,
        loadHistory: (() async -> Void)? = nil
    ) {
        self.seasons = seasons
        self.roster = roster
        self.resolve = resolve
        self.isSeasonLocked = isSeasonLocked
        self.isLoadingHistory = isLoadingHistory
        self.loadHistory = loadHistory
    }

    @MainActor
    init(viewModel: DashboardViewModel, phase: SeasonPhase = .regular) {
        self.init(
            seasons: viewModel.availableSeasons,
            roster: { viewModel.players(forSeason: $0, phase: phase).sorted { $0.name < $1.name } },
            resolve: { player, season in
                if phase == .postseason, season == StatScoutSeason.current {
                    return viewModel.players(forSeason: season, phase: phase)
                        .first { $0.playerId == player.playerId }
                }
                if player.season == season { return player }
                return viewModel.playerHistories[player.playerId]?.first { $0.season == season }
            },
            isSeasonLocked: { viewModel.isSeasonLocked($0) },
            isLoadingHistory: viewModel.isHistoricalLoading,
            loadHistory: { await viewModel.loadHistoricalIfNeeded() }
        )
    }
}

struct PlayerComparisonView: View {
    @EnvironmentObject private var store: StoreService
    let playerA: Player
    let playerB: Player
    var phase: SeasonPhase = .regular
    /// Nil disables in-page swapping; the comparison is then whatever was
    /// pushed.
    var catalog: ComparisonCatalog? = nil

    private enum PickerTarget: Identifiable {
        case a, b
        var id: Int { hashValue }
    }

    @State private var showingTrial = false
    // The screen used to be a dead end: getting to a different pairing meant
    // going back to the tab that built this one, re-picking both slots, and
    // pressing Compare again. Either side can now be replaced in place, and
    // either side can be moved to a different year.
    @State private var overrideA: Player?
    @State private var overrideB: Player?
    @State private var picker: PickerTarget?
    @State private var note: String?

    private var a: Player { overrideA ?? playerA }
    private var b: Player { overrideB ?? playerB }

    private var comparisonMetrics: [(label: String, category: MetricCategory, a: Metric?, b: Metric?)] {
        var seen = Set<String>()
        var result: [(label: String, category: MetricCategory, a: Metric?, b: Metric?)] = []
        let allMetrics = a.metrics + b.metrics
        for metric in allMetrics {
            let key = "\(metric.label)|\(metric.category.rawValue)"
            guard seen.insert(key).inserted else { continue }
            let left = a.metrics.first { $0.label == metric.label && $0.category == metric.category }
            let right = b.metrics.first { $0.label == metric.label && $0.category == metric.category }
            result.append((metric.label, metric.category, left, right))
        }
        return result.sorted { $0.category == $1.category
            ? $0.category.sortMetrics($0.label, $1.label)
            : MetricCategory.allCases.firstIndex(of: $0.category)! < MetricCategory.allCases.firstIndex(of: $1.category)!
        }
    }

    private var groupedComparison: [(MetricCategory, [(label: String, a: Metric?, b: Metric?)])] {
        let grouped = Dictionary(grouping: comparisonMetrics) { $0.category }
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            let mapped = items.map { (label: $0.label, a: $0.a, b: $0.b) }
            return (cat, mapped)
        }
    }

    var body: some View {
        Group {
            if store.isPro {
                comparisonContent
            } else {
                ZStack(alignment: .bottom) {
                    comparisonContent
                        .blur(radius: 8)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, SavantPalette.canvas.opacity(0.9)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .clipped()

                    // CTA overlay
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.yellow)

                        Text("Find the Edge")
                            .font(SavantType.cardTitle)
                            .foregroundStyle(SavantPalette.ink)

                        Text("StatScout+ unlocks side-by-side player comparisons across every metric. See who leads in xwOBA, Barrel%, Sprint Speed, and more.")
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            showingTrial = true
                        } label: {
                            Text(store.paywallBlurCTA)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(SavantPalette.savantRed)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        if let subtext = store.paywallBlurSubtext {
                            Text(subtext)
                                .font(SavantType.micro)
                                .tracking(0.3)
                                .foregroundStyle(SavantPalette.inkTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                            .fill(SavantPalette.surface)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(SavantPalette.divider)
                            .frame(height: SavantGeo.hairline)
                    }
                    .offset(y: -8)
                }
                .background(SavantPalette.canvas.ignoresSafeArea())
                .sheet(isPresented: $showingTrial) {
                    TrialPitchSheet(trigger: .playerComparison)
                }
            }
        }
        .onAppear {
            if store.isPro {
                ReviewPromptTracker.recordPositiveMoment()
            }
        }
        .sheet(item: $picker) { target in
            if let catalog {
                let side = target == .a ? a : b
                let other = target == .a ? b : a
                ComparePlayerPicker(
                    players: catalog.roster(side.season ?? 0).filter { $0.playerId != other.playerId },
                    season: side.season,
                    isLoading: catalog.isLoadingHistory
                ) { selected in
                    note = nil
                    if target == .a { overrideA = selected } else { overrideB = selected }
                }
            }
        }
    }

    private var comparisonContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                playerHeadlines
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if let note {
                    Text(note)
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(SavantPalette.savantRed)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }

                if comparisonMetrics.isEmpty {
                    ContentUnavailableView {
                        Label("No comparable metrics", systemImage: "chart.bar")
                    } description: {
                        Text("These players don't share any common metrics.")
                    }
                    .padding(.vertical, 48)
                } else {
                    ForEach(groupedComparison, id: \.0) { category, metrics in
                        categoryCard(category: category, metrics: metrics)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
            // Clears the floating tab bar.
            Color.clear.frame(height: 88)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SavantPalette.canvas.ignoresSafeArea())
        .navigationTitle("Player Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var playerHeadlines: some View {
        HStack(alignment: .top, spacing: 8) {
            playerSummaryCard(player: a, target: .a)
            if catalog != nil {
                // Flips the two sides, which is the cheapest way to get the
                // player you care about into the left column without touching
                // either picker.
                Button {
                    let left = a
                    let right = b
                    overrideA = right
                    overrideB = left
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(SavantPalette.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 44)
                .accessibilityLabel("Swap sides")
            }
            playerSummaryCard(player: b, target: .b)
        }
    }

    private func playerSummaryCard(player: Player, target: PickerTarget) -> some View {
        VStack(spacing: 8) {
            // The identity opens his page. A comparison is where you decide a
            // player is worth a closer look, and until now it was the one
            // screen in the app where his name wasn't a link.
            NavigationLink(value: PlayerRoute(
                player: player,
                phase: phase,
                season: player.season
            )) {
                VStack(spacing: 6) {
                    PlayerHeadshot(team: player.team, initials: player.initials, size: 56)
                    Text(player.name)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(displayTeamAbbr(player.team)) · \(player.displayPosition)")
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(player.name)'s page")

            if let catalog {
                // Season is load-bearing once the two sides can come from
                // different years, and it's now the control as well as the
                // label: a cross-year comparison is built here rather than
                // back on the tab that pushed this screen.
                SeasonMenu(
                    seasons: catalog.seasons,
                    selected: player.season ?? 0,
                    isLocked: { catalog.isSeasonLocked($0) },
                    onSelect: { season in
                        if catalog.isSeasonLocked(season) {
                            showingTrial = true
                        } else {
                            move(target, to: season, catalog: catalog)
                        }
                    }
                ) {
                    SavantInlinePill(systemImage: "calendar", title: player.season.map(String.init) ?? "-")
                }
                .accessibilityLabel("Season for \(player.name)")

                Button {
                    picker = target
                } label: {
                    SavantInlinePill(systemImage: "arrow.triangle.2.circlepath", title: "Change")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change \(target == .a ? "first" : "second") player")
            } else if let season = player.season {
                Text(String(season))
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SavantPalette.savantNavy)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    /// Moves one side to another season, or says why it can't. A player who
    /// wasn't in the league that year has no row to show, and silently leaving
    /// the old season on screen under a new label would be worse than saying so.
    private func move(_ target: PickerTarget, to season: Int, catalog: ComparisonCatalog) {
        let current = target == .a ? a : b
        if let resolved = catalog.resolve(current, season) {
            if target == .a { overrideA = resolved } else { overrideB = resolved }
            note = nil
        } else {
            note = catalog.isLoadingHistory
                ? "Loading past seasons…"
                : "No \(String(season)) data for \(current.name)."
            Task { await catalog.loadHistory?() }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func categoryCard(category: MetricCategory, metrics: [(label: String, a: Metric?, b: Metric?)]) -> some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: category.rawValue.uppercased())

            HStack(spacing: 8) {
                Text("METRIC")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 72, alignment: .leading)
                Text(a.name.split(separator: " ").last.map(String.init) ?? "A")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(b.name.split(separator: " ").last.map(String.init) ?? "B")
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: SavantGeo.rowHeightHeader)
            .padding(.horizontal, SavantGeo.padInline)
            .background(SavantPalette.surfaceAlt)
            .overlay(
                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                alignment: .bottom
            )

            ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.ink)
                        .frame(width: 72, alignment: .leading)

                    metricValueCell(metric: item.a, other: item.b)
                    metricValueCell(metric: item.b, other: item.a)
                }
                .frame(height: 60)
                .padding(.horizontal, SavantGeo.padInline)
                .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    /// One side of one metric row.
    ///
    /// The bar is the promise that there is something behind the cell, so it is
    /// drawn only where there is. The backend ships plenty of metrics with a
    /// real percentile and a blank value string, and the old cell rendered
    /// those as a dash sitting on top of a full-length coloured bar, sometimes
    /// with a trophy over it: it read as "we have this number and are refusing
    /// to print it". Now a blank value with a real percentile says the
    /// percentile out loud, and a metric with neither draws nothing at all.
    private func metricValueCell(metric: Metric?, other: Metric?) -> some View {
        Group {
            if let m = metric, m.percentile > 0 || !m.value.isEmpty {
                let hasValue = !m.value.isEmpty
                let comparable = other.map { $0.percentile > 0 || !$0.value.isEmpty } ?? false
                let isWinner = comparable && (other.map { m.percentile > $0.percentile } ?? false)
                let pctColor = SavantPalette.color(forPercentile: m.percentile)
                let pctTextColor = SavantPalette.textColor(forPercentile: m.percentile)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if isWinner {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                        Text(hasValue ? m.value : "\(m.percentile)")
                            .font(SavantType.statMed)
                            .foregroundStyle(pctTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    // Says what the number is when it isn't the raw stat, so a
                    // percentile can't be misread as a rate.
                    Text(hasValue ? "" : "PERCENTILE")
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pctColor)
                        .frame(width: max(8, CGFloat(m.percentile) * 0.6), height: 4)
                        .frame(maxWidth: 60, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("-")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerComparisonView(
            playerA: SampleData.players.first!,
            playerB: SampleData.players.last!
        )
        .environmentObject(StoreService.shared)
    }
}
#endif
