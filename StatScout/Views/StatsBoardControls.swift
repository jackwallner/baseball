import SwiftUI

/// Which leaderboard the Stats tab is drawing.
///
/// This used to be a user-facing chip ("Advanced / Standard / Best-Worst")
/// sitting on the same row as the sort metric, the position filter, search and
/// the filters menu, five controls competing for a 375pt phone. It isn't a
/// question worth a control of its own: "rank the league by AVG" and "rank the
/// league by xwOBA" are the same request in two vocabularies, so the board
/// follows from the stat you picked rather than from a mode you set first.
enum StatsBoard: Hashable {
    /// Statcast percentiles, ranked by `viewModel.currentSortMetric`.
    case advanced
    /// The traditional line, ranked by whichever standard stat is selected.
    case standard
    /// Best and worst in the league, per metric. StatScout+.
    case bestWorst
}

/// The traditional stats each category offers, and which way "best" runs.
///
/// Lifted out of `StandardStatsLeadersView` so the stat menu can list them
/// without owning the board that renders them.
enum StandardStatCatalog {
    static func stats(for category: MetricCategory) -> [String] {
        switch category {
        case .hitting:
            return ["AVG", "HR", "RBI", "OBP", "SLG", "OPS", "H", "R", "2B", "3B", "BB", "SO"]
        case .pitching:
            return ["ERA", "WHIP", "W", "L", "SV", "SO", "IP", "K/9", "BB/9", "QS"]
        case .fielding:
            // Fielding percentage leads, not errors: "fewest errors" sorted
            // ascending is fifty players on zero, and the top of that list is
            // whoever touched the ball least.
            return ["FLD%", "E", "A", "PO", "DP"]
        case .running:
            return ["SB", "SB%", "CS", "3B", "R"]
        }
    }

    /// Stats where lower is the better outcome, so the leader (lowest ERA,
    /// fewest losses) sits at the top by default.
    static let lowerIsBetter: Set<String> = ["ERA", "WHIP", "BB/9", "L", "E", "CS"]

    /// SO is contextual: pitcher strikeouts are good, batter strikeouts aren't.
    static func defaultDescending(for stat: String, category: MetricCategory) -> Bool {
        if stat == "SO" { return category == .pitching }
        return !lowerIsBetter.contains(stat)
    }

    static func defaultStat(for category: MetricCategory) -> String {
        stats(for: category).first ?? "AVG"
    }
}

/// The app's one "which stat is this ranked by" control.
///
/// Stats and Trends both answer that question and used to answer it in two
/// different shapes: Trends put the metric on a pill you tap to change it,
/// while Stats put an identical-looking pill on the row that *didn't* change
/// the stat (it flipped the sort direction) and hid the actual picker two
/// levels down inside the View menu. Same screen furniture, opposite meaning,
/// which is the kind of thing that makes an app feel like two apps.
///
/// One control now, on both boards: the current stat, a chevron, and the two
/// vocabularies as sections inside. Sections are dropped when empty, so the
/// standalone standard board gets the same pill with one section in it.
struct StatPickerMenu: View {
    struct Option: Identifiable {
        let id: String
        let label: String
        var isSelected: Bool = false
    }

    var statcast: [Option] = []
    var standard: [Option] = []
    let activeLabel: String
    var onSelectStatcast: (Option) -> Void = { _ in }
    var onSelectStandard: (Option) -> Void = { _ in }

    var body: some View {
        Menu {
            if !statcast.isEmpty {
                Section("Statcast") { rows(statcast, select: onSelectStatcast) }
            }
            if !standard.isEmpty {
                Section("Standard") { rows(standard, select: onSelectStandard) }
            }
        } label: {
            SavantInlinePill(systemImage: "chart.bar.fill", title: activeLabel)
        }
        .menuOrder(.fixed)
        .savantMenuAppearance()
        .accessibilityLabel("Stat")
        .accessibilityValue(activeLabel)
    }

    private func rows(_ options: [Option], select: @escaping (Option) -> Void) -> some View {
        ForEach(options) { option in
            Button {
                select(option)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if option.isSelected {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }
    }
}

/// The direction toggle that rides beside the stat pill.
///
/// Splitting it out is what lets the pill mean one thing. It's the icon-only
/// `SavantChip` circle, so it costs about a third of the width the old combined
/// chip did and can't be mistaken for a chooser.
struct SortDirectionButton: View {
    let descending: Bool
    let statLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            SavantChip(trailing: .sortArrow(descending: descending))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort direction")
        .accessibilityValue("\(statLabel), \(descending ? "highest first" : "lowest first")")
        .accessibilityHint("Tap to flip sort direction")
    }
}

/// The Stats tab's stat pill: one list, two vocabularies, where picking the
/// stat is also picking the board it belongs to (AVG lands on the standard
/// leaderboard, xwOBA lands back on the Statcast one).
struct StatsBoardStatPicker: View {
    @Bindable var viewModel: DashboardViewModel
    let bindings: StatsBoardBindings

    private var category: MetricCategory { viewModel.selectedCategory ?? .hitting }

    private var activeLabel: String {
        switch bindings.board {
        case .advanced: return viewModel.currentSortMetric ?? viewModel.sortLabel
        case .standard: return bindings.standardStat
        case .bestWorst: return "Best & Worst"
        }
    }

    var body: some View {
        StatPickerMenu(
            statcast: viewModel.availableSortMetrics.map { metric in
                .init(
                    id: metric,
                    label: metric,
                    isSelected: bindings.board == .advanced && metric == viewModel.currentSortMetric
                )
            },
            standard: StandardStatCatalog.stats(for: category).map { stat in
                .init(
                    id: stat,
                    label: stat,
                    isSelected: bindings.board == .standard && stat == bindings.standardStat
                )
            },
            activeLabel: activeLabel,
            onSelectStatcast: { option in
                bindings.board = .advanced
                viewModel.setUserSortMetric(option.id)
            },
            onSelectStandard: { option in
                bindings.board = .standard
                bindings.standardStat = option.id
                bindings.standardSortDescending = StandardStatCatalog.defaultDescending(
                    for: option.id,
                    category: category
                )
            }
        )
    }
}

/// What's left once the stat and its direction are back on the row as controls
/// of their own: who's in the pool (position, qualifier) and which board is
/// answering (leaderboard vs Best & Worst).
///
/// The stat used to live in here too, which kept the row short but put the most
/// frequently changed control on the board two taps deep, and behind a label
/// ("View") that doesn't say "stat". Trends never made that trade, and the two
/// tabs read as different products because of it. The row is still three items
/// wide on a 375pt phone, because the direction toggle is an icon-only circle.
///
/// Named "View" rather than "Filters" because it doesn't only narrow the board,
/// it chooses which one you get.
struct StatsViewMenu: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @Binding var board: StatsBoard

    /// Red when something in here is narrowing or changing the board, so a
    /// filter left on isn't invisible once the menu closes.
    private var isActive: Bool {
        viewModel.qualifierLevel != .qualified
            || viewModel.positionFilter != .all
            || board != .advanced
    }

    var body: some View {
        Menu {
            if viewModel.positionFilterApplies {
                positionSection
            }
            qualifierSection
            boardSection
        } label: {
            SavantChip(
                title: "View",
                systemImage: "slider.horizontal.3",
                trailing: .chevron,
                isActive: isActive
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("View options")
    }

    // MARK: - Position / qualifier

    private var positionSection: some View {
        Section("Position") {
            ForEach(viewModel.availablePositionFilters) { option in
                Button {
                    viewModel.positionFilter = option
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if option == viewModel.positionFilter {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        }
    }

    private var qualifierSection: some View {
        Section("Qualifier") {
            ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                Button {
                    viewModel.qualifierLevel = level
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if level == viewModel.qualifierLevel {
                        Label("\(level.rawValue) · \(level.description)", systemImage: "checkmark")
                    } else {
                        Text("\(level.rawValue) · \(level.description)")
                    }
                }
            }
        }
    }

    // MARK: - Board

    /// Best & Worst is a different question from the leaderboard ("who are the
    /// extremes of every metric" rather than "rank the league by one"), so it
    /// sits at the bottom as its own choice rather than in the stat list.
    ///
    /// A free user can still open it and gets the blurred board behind the
    /// unlock panel, the same gate the Trends board uses. Refusing to open it
    /// at all would sell a feature nobody can see the shape of.
    private var boardSection: some View {
        Section("Show") {
            Button {
                if board == .bestWorst { board = .advanced }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if board != .bestWorst {
                    Label("Leaderboard", systemImage: "checkmark")
                } else {
                    Text("Leaderboard")
                }
            }
            Button {
                board = .bestWorst
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if board == .bestWorst {
                    Label("Best & Worst", systemImage: "checkmark")
                } else if store.isPro {
                    Text("Best & Worst")
                } else {
                    Label("Best & Worst (StatScout+)", systemImage: "crown.fill")
                }
            }
        }
    }
}
