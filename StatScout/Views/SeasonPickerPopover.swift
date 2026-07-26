import SwiftUI

/// Season chooser: a narrow vertical list in a popover anchored to whatever
/// control opened it.
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

    @Environment(\.dismiss) private var dismiss

    /// Wide enough for a year, a crown and a checkmark, and no wider.
    private let width: CGFloat = 168
    /// Caps the list at roughly eight rows so it never becomes a full-screen
    /// panel; the rest scrolls.
    private let maxListHeight: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(seasons, id: \.self) { season in
                        row(for: season)
                        if season != seasons.last {
                            Rectangle()
                                .fill(SavantPalette.divider)
                                .frame(height: SavantGeo.hairline)
                        }
                    }
                }
            }
            .frame(maxHeight: maxListHeight)

            if seasons.contains(where: isLocked) {
                Rectangle()
                    .fill(SavantPalette.divider)
                    .frame(height: SavantGeo.hairline)
                Label("Crowned = StatScout+", systemImage: "crown.fill")
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: width)
        .background(SavantPalette.surface)
        // Without this iPhone promotes a popover into a bottom sheet, which is
        // the transition this exists to avoid.
        .presentationCompactAdaptation(.popover)
    }

    private func row(for season: Int) -> some View {
        let locked = isLocked(season)
        let isSelected = season == selected
        return Button {
            dismiss()
            onSelect(season)
        } label: {
            HStack(spacing: 6) {
                Text(String(season))
                    .font(isSelected ? SavantType.bodyBold : SavantType.body)
                    .foregroundStyle(
                        isSelected
                            ? SavantPalette.savantRed
                            : (locked ? SavantPalette.inkTertiary : SavantPalette.ink)
                    )
                Spacer(minLength: 0)
                if locked {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.yellow)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SavantPalette.savantRed)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "\(season), requires StatScout+" : String(season))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
