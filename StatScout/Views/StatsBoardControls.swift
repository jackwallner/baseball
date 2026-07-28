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

/// Every control that changes what the Stats board shows, behind one chip.
///
/// The row it sits on had grown to five controls and had to scroll to avoid
/// clipping; scrolling a control row means a filter can be off-screen, which is
/// how "the app lost its filter button" happens. Everything that answers "what
/// am I looking at" now lives in here (the stat, in both vocabularies; which
/// way it sorts; which positions; what counts as qualified; and whether you
/// want the board or the best-and-worst view), which leaves the row itself at
/// three items on every phone.
///
/// Named "View" rather than "Filters" because it no longer only narrows the
/// board, it chooses it.
struct StatsViewMenu: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @Binding var board: StatsBoard
    @Binding var standardStat: String
    /// Sort direction for whichever board is on screen. The two boards keep
    /// their own, so this is a binding rather than a reach into the model.
    @Binding var sortDescending: Bool

    private var category: MetricCategory { viewModel.selectedCategory ?? .hitting }

    /// Red when something in here is narrowing or changing the board, so a
    /// filter left on isn't invisible once the menu closes.
    private var isActive: Bool {
        viewModel.qualifierLevel != .qualified
            || viewModel.positionFilter != .all
            || board != .advanced
    }

    var body: some View {
        Menu {
            statMenu
            directionSection
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

    // MARK: - Stat

    /// One list, two vocabularies. Picking a standard stat moves the board to
    /// the standard leaderboard and picking a Statcast metric moves it back:
    /// the choice of stat *is* the choice of board.
    private var statMenu: some View {
        Menu {
            Section("Statcast") {
                ForEach(viewModel.availableSortMetrics, id: \.self) { metric in
                    Button {
                        board = .advanced
                        viewModel.setUserSortMetric(metric)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if board == .advanced, metric == viewModel.currentSortMetric {
                            Label(metric, systemImage: "checkmark")
                        } else {
                            Text(metric)
                        }
                    }
                }
            }

            Section("Standard") {
                ForEach(StandardStatCatalog.stats(for: category), id: \.self) { stat in
                    Button {
                        board = .standard
                        standardStat = stat
                        sortDescending = StandardStatCatalog.defaultDescending(for: stat, category: category)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if board == .standard, stat == standardStat {
                            Label(stat, systemImage: "checkmark")
                        } else {
                            Text(stat)
                        }
                    }
                }
            }
        } label: {
            Label("Stat: \(activeStatLabel)", systemImage: "chart.bar.doc.horizontal")
        }
    }

    private var activeStatLabel: String {
        switch board {
        case .advanced: return viewModel.currentSortMetric ?? viewModel.sortLabel
        case .standard: return standardStat
        case .bestWorst: return "Best & Worst"
        }
    }

    // MARK: - Direction

    /// The two boards keep their own direction, so the menu has to read the one
    /// belonging to whichever is on screen or the checkmark describes the board
    /// you aren't looking at.
    private var activeDescending: Bool {
        board == .advanced ? viewModel.sortDescending : sortDescending
    }

    @ViewBuilder
    private var directionSection: some View {
        if board != .bestWorst {
            Section("Direction") {
                Button {
                    if !activeDescending { flipDirection() }
                } label: {
                    if activeDescending {
                        Label("Highest first", systemImage: "checkmark")
                    } else {
                        Text("Highest first")
                    }
                }
                Button {
                    if activeDescending { flipDirection() }
                } label: {
                    if !activeDescending {
                        Label("Lowest first", systemImage: "checkmark")
                    } else {
                        Text("Lowest first")
                    }
                }
            }
        }
    }

    /// The advanced board's direction lives in the model, which also has to
    /// record that the user pinned it; the standard board's is plain state.
    private func flipDirection() {
        if board == .advanced {
            viewModel.toggleSortDirection()
        } else {
            sortDescending.toggle()
        }
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
