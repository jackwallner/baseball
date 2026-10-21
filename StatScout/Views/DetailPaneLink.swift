import SwiftUI

/// What the trailing pane of the unfolded iPhone Duo shows: the player or team
/// the user last opened from the leading pane.
enum PaneDetail: Hashable {
    case player(PlayerRoute)
    case team(TeamDestination)

    /// Same page, whatever slate the link carried.
    func matches(_ other: PaneDetail?) -> Bool {
        switch (self, other) {
        case let (.player(a), .player(b)?): return a.player.playerId == b.player.playerId
        case let (.team(a), .team(b)?): return normalizedTeamAbbreviation(a.abbr) == normalizedTeamAbbreviation(b.abbr)
        default: return false
        }
    }
}

extension EnvironmentValues {
    /// Set only in the leading pane while the Duo is split. `nil` everywhere
    /// else, so links push exactly as they do on a phone.
    @Entry var openInDetailPane: (@MainActor (PaneDetail) -> Void)? = nil
    /// The trailing pane's page, so the row that opened it can show it.
    @Entry var detailPaneSelection: PaneDetail? = nil
}

/// A player or team link. On a phone it is a `NavigationLink`; in the leading
/// pane of the unfolded Duo it opens the page beside the list instead of
/// pushing over it. Leaderboard rows pass `marksSelection` so the open row
/// carries a red edge.
struct DetailPaneLink<Label: View>: View {
    private let detail: PaneDetail
    private let marksSelection: Bool
    private let label: Label
    @Environment(\.openInDetailPane) private var openInDetailPane
    @Environment(\.detailPaneSelection) private var selection

    init(value: PlayerRoute, marksSelection: Bool = false, @ViewBuilder label: () -> Label) {
        detail = .player(value)
        self.marksSelection = marksSelection
        self.label = label()
    }

    init(value: TeamDestination, marksSelection: Bool = false, @ViewBuilder label: () -> Label) {
        detail = .team(value)
        self.marksSelection = marksSelection
        self.label = label()
    }

    private var isOpen: Bool { detail.matches(selection) }

    var body: some View {
        if let openInDetailPane {
            Button {
                openInDetailPane(detail)
            } label: {
                label.overlay(alignment: .leading) {
                    if marksSelection, isOpen {
                        Rectangle()
                            .fill(SavantPalette.savantRed)
                            .frame(width: 3)
                    }
                }
            }
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        } else {
            switch detail {
            case .player(let route): NavigationLink(value: route) { label }
            case .team(let team): NavigationLink(value: team) { label }
            }
        }
    }
}
