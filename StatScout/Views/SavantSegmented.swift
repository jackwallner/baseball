import SwiftUI

/// The single inline-options control for the whole app.
///
/// Same-level choices were being drawn four different ways — large filled
/// rounded-rects, tall capsules, short capsules, and underlined text tabs — so
/// two pickers that mean the same kind of thing looked unrelated. The app now
/// keeps exactly three tiers, and this is the third:
///
/// 1. **Page-level switch** (Percentiles / Roster, Percentiles / Standard Stats
///    / Year Compare): the large filled rounded-rect row. "Which screen is
///    this."
/// 2. **Metric category** (Hitting / Pitching / Fielding / Running):
///    `SavantTabs`, underlined text. Matches Savant's own leaderboard tabs.
/// 3. **Inline options** (Season / Recent / Both, Hitters / Pitchers, the
///    Last 7 / 15 / 30 windows, Heating / Cooling): this control. One height,
///    one shape, everywhere. Past four options it hands over to
///    `VerticalOptionPopover` — seasons and the Trends metric list.
///
/// The wording is shared too: a rolling window is always "Last 15", never
/// "15d" on one screen and "Last 15" on the next.
///
/// Segments can be individually locked, which draws a crown and routes the tap
/// to `onLockedTap` instead of selecting — that's how a free user can see that
/// Recent exists at all rather than the option being hidden entirely.
struct SavantSegmented<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let label: String
        var isLocked: Bool = false
        /// Optional leading glyph. Kept to SF Symbols so it tints with the
        /// palette and can't fall back to a missing-glyph box.
        var systemImage: String? = nil

        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value
    /// Called instead of selecting when a locked segment is tapped.
    var onLockedTap: ((Value) -> Void)? = nil
    /// Fill for the selected segment. Defaults to the Savant red every other
    /// active control uses; Trends overrides it to encode hot vs cold.
    var selectedFill: (Value) -> Color = { _ in SavantPalette.savantRed }

    /// One height for every instance. Previously 26, 28, 30, 34 and 44 were all
    /// in use for controls at the same level.
    private let height: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection && !segment.isLocked
                Button {
                    if segment.isLocked {
                        onLockedTap?(segment.value)
                    } else {
                        selection = segment.value
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        if let icon = segment.systemImage {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(segment.label)
                            .font(SavantType.smallBold)
                        if segment.isLocked {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                    }
                    .foregroundStyle(isSelected ? .white : SavantPalette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(isSelected ? selectedFill(segment.value) : SavantPalette.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(isSelected ? Color.clear : SavantPalette.hairline, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.isLocked ? "\(segment.label), requires StatScout+" : segment.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
    }
}
