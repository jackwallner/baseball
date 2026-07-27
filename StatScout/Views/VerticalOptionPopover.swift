import SwiftUI

/// The one "pick one of many" control in the app: a narrow vertical list in a
/// popover anchored to the pill that opened it.
///
/// `SavantSegmented` covers two-to-four inline options. Past that a segmented
/// row stops working — twelve seasons or a dozen metrics can't be laid side by
/// side — and this takes over. Both are deliberately the only two shapes; the
/// app previously had five.
///
/// Options can be individually locked, which draws a crown and routes the tap
/// to the caller so it can pitch that specific thing rather than hiding it.
struct VerticalOptionPopover<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var isLocked: Bool = false
        /// Caption drawn above this row, starting a group. Only set it on the
        /// first option of each group.
        var header: String? = nil

        var id: Value { value }
    }

    let options: [Option]
    let selected: Value
    /// Shown under the list when anything is locked. Kept short enough to sit
    /// on one line at the list's width.
    var lockedFootnote: String = "StatScout+"
    let onSelect: (Value) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Sized to the label and nothing else. A plain `Menu` can't do this —
    /// UIKit gives menus a wide minimum, so four-character years rendered as a
    /// column of mostly empty grey, which is the whole reason this exists.
    /// Callers with long labels (the Trends metric list) pass a wider value.
    var width: CGFloat = 128
    /// Caps the list so it can't become a full-screen panel; the rest scrolls.
    /// Tall enough for all twelve seasons at once — the whole complaint about
    /// the old picker was having to hunt for a year.
    var maxListHeight: CGFloat = 470
    /// Short rows keep a twelve-item list mostly visible without scrolling.
    private let rowHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options) { option in
                        entry(for: option)
                    }
                }
            }
            .frame(maxHeight: maxListHeight)

            if options.contains(where: \.isLocked) {
                Rectangle()
                    .fill(SavantPalette.divider)
                    .frame(height: SavantGeo.hairline)
                Label(lockedFootnote, systemImage: "crown.fill")
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
        // wrong for a control anchored in the top corner.
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func entry(for option: Option) -> some View {
        VStack(spacing: 0) {
            if let header = option.header {
                Text(header)
                    .font(SavantType.micro)
                    .tracking(0.6)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(SavantPalette.surfaceSunk)
            }
            row(for: option)
            if option.id != options.last?.id {
                Rectangle()
                    .fill(SavantPalette.divider)
                    .frame(height: SavantGeo.hairline)
            }
        }
    }

    /// Any lock in the list turns the trailing glyph into a lock state on every
    /// row — crown for locked, open padlock for not — because a crown that only
    /// appears on some rows reads as decoration rather than as a status. Lists
    /// with nothing locked keep a plain checkmark on the selection.
    private var showsLockState: Bool { options.contains(where: \.isLocked) }

    private func row(for option: Option) -> some View {
        let isSelected = option.value == selected
        return Button {
            dismiss()
            onSelect(option.value)
        } label: {
            HStack(spacing: 6) {
                Text(option.label)
                    .font(isSelected ? SavantType.bodyBold : SavantType.body)
                    .foregroundStyle(
                        isSelected
                            ? SavantPalette.savantRed
                            : (option.isLocked ? SavantPalette.inkTertiary : SavantPalette.ink)
                    )
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsLockState {
                    Image(systemName: option.isLocked ? "crown.fill" : "lock.open.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(option.isLocked ? Color.yellow : SavantPalette.inkTertiary)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SavantPalette.savantRed)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            // Selection is a red bar rather than another trailing glyph, so the
            // row stays narrow enough to justify the shape.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? SavantPalette.savantRed : .clear)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.isLocked ? "\(option.label), requires StatScout+" : option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The tappable label for a `VerticalOptionPopover` living on the navy nav bar.
///
/// Every nav-bar chooser (season on Stats / Teams / a team page) drew its own
/// copy of this, and they drifted — one was a `Menu`, the others popovers, and
/// the team page's had no `fixedSize()` so it clipped to a bare icon. One view
/// now, so a change lands everywhere.
struct SavantNavPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(SavantType.smallBold)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        // Without this the toolbar squeezes the label and the title itself is
        // the first thing to get clipped, leaving a bare icon.
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(SavantPalette.savantRed)
        .clipShape(Capsule())
    }
}

/// In-content variant: same control, but sitting on a card rather than the navy
/// bar, so it's a quiet outlined capsule instead of a red one.
struct SavantInlinePill: View {
    let systemImage: String?
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(title)
                .font(SavantType.smallBold)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(SavantPalette.inkSecondary)
        .fixedSize()
        .frame(height: 32)
        .padding(.horizontal, 12)
        .background(SavantPalette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SavantPalette.hairline, lineWidth: 0.5))
    }
}
