import SwiftUI

/// Compact season chooser, presented as a popover anchored to the season pill.
///
/// A plain `Menu` is spatially right but badly proportioned here: UIKit gives
/// menus a wide minimum width, so twelve four-character years render as a tall
/// column of mostly empty gray. A popover keeps the "opens from the control
/// you tapped" behaviour while sizing to its content — a four-wide grid fits
/// all twelve seasons in three rows with room for a crown on the locked ones.
struct SeasonPickerPopover: View {
    let seasons: [Int]
    let selected: Int
    let isLocked: (Int) -> Bool
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(seasons, id: \.self) { season in
                    Button {
                        dismiss()
                        onSelect(season)
                    } label: {
                        chip(for: season)
                    }
                    .buttonStyle(.plain)
                }
            }

            if seasons.contains(where: isLocked) {
                Label("Crowned = StatScout+", systemImage: "crown.fill")
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
        }
        .padding(14)
        .frame(width: 210)
        .background(SavantPalette.canvas)
        // Without this iPhone promotes a popover to a full sheet, which is the
        // bottom-up transition this exists to avoid.
        .presentationCompactAdaptation(.popover)
    }

    private func chip(for season: Int) -> some View {
        let locked = isLocked(season)
        let isSelected = season == selected
        return Text(String(season))
            .font(SavantType.smallBold)
            .foregroundStyle(isSelected ? .white : (locked ? SavantPalette.inkTertiary : SavantPalette.ink))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? SavantPalette.savantRed : SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.clear : SavantPalette.hairline, lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if locked {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SavantPalette.savantNavy)
                        .padding(2.5)
                        .background(Color.yellow, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
            .accessibilityLabel(locked ? "\(season), requires StatScout+" : String(season))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
