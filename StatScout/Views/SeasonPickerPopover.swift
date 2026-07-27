import SwiftUI

/// Season chooser. A thin wrapper over `VerticalOptionPopover` so seasons,
/// metrics and any future long list are literally the same control.
///
/// Three iterations got here and the constraints are worth recording. A plain
/// `Menu` is spatially right but UIKit gives menus a wide minimum, so twelve
/// four-character years rendered as a column of mostly empty grey. A bottom
/// sheet fixed the width but was wrong for a control in the top corner. A
/// four-wide grid was compact but blanketed a large area of the screen with
/// twelve tap targets sitting over the tab buttons — the likeliest explanation
/// for a stray tap landing on a locked year and pitching it unprompted.
///
/// Vertical is also simply how people read dates. So: one narrow column,
/// scrollable, sized to its content.
struct SeasonPickerPopover: View {
    let seasons: [Int]
    let selected: Int
    let isLocked: (Int) -> Bool
    let onSelect: (Int) -> Void

    var body: some View {
        VerticalOptionPopover(
            options: seasons.map { .init(value: $0, label: String($0), isLocked: isLocked($0)) },
            selected: selected,
            onSelect: onSelect
        )
    }
}
