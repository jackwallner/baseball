import SwiftUI

// MARK: - Atomic Components

struct PlayerHeadshot: View {
    let team: String
    let initials: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(MLBTeamColor.color(team))
            Text(initials)
                .font(SavantFont.condensed(size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Shimmer Effect Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.5), .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 2)
                    .offset(x: -proxy.size.width + phase * proxy.size.width * 2)
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
                }
            )
            .mask(content)
            .onAppear { phase = 1 }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct OverallPercentileBadge: View {
    let percentile: Int
    var size: CGFloat = 64

    private var tierDescription: String {
        switch percentile {
        case 90...100: return "Elite"
        case 75..<90: return "Excellent"
        case 50..<75: return "Above Average"
        case 25..<50: return "Below Average"
        default: return "Poor"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(percentile)")
                .font(SavantType.statHero)
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
            Text(percentile.ordinal)
                .font(SavantType.micro)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 0.5)
        }
        .frame(width: size, height: size)
        .background(SavantPalette.color(forPercentile: percentile))
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusBadge))
        .accessibilityLabel("Overall \(percentile)th percentile, \(tierDescription)")
    }
}

struct TeamColorDot: View {
    let abbr: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(MLBTeamColor.color(abbr)).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

func displayTeamAbbr(_ abbr: String) -> String {
    let trimmed = abbr.trimmingCharacters(in: .whitespaces).uppercased()
    if trimmed.isEmpty || trimmed == "TBD" || trimmed == "—" || trimmed == "-" {
        return "FA"
    }
    return abbr
}

// MARK: - Module 2: Percentile Bar Row (MetricBar) - Baseball Savant Style

struct MetricBar: View {
    let metric: Metric
    var showValue: Bool = true

    private var accessibilityLabel: String {
        let valueText = metric.value.isEmpty ? "\(metric.percentile)th percentile" : "\(metric.value), \(metric.percentile)th percentile"
        return "\(metric.label): \(valueText)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Label column - left aligned
            Text(metric.label)
                .font(SavantType.bodyBold)
                .foregroundStyle(SavantPalette.ink)
                .frame(width: 70, alignment: .leading)

            // Percentile bar - takes remaining space
            let percentileValue = max(0, min(100, metric.percentile))
            GeometryReader { proxy in
                let circleSize: CGFloat = 28
                let trackWidth = proxy.size.width - circleSize
                let offset = (circleSize / 2) + (trackWidth * CGFloat(percentileValue) / 100.0)

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SavantPalette.hairline)
                        .frame(height: 10)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SavantPalette.color(forPercentile: percentileValue))
                        .frame(width: offset, height: 10)

                    // Percentile circle
                    ZStack {
                        Circle()
                            .fill(SavantPalette.color(forPercentile: percentileValue))
                            .frame(width: circleSize, height: circleSize)

                        Text("\(percentileValue)")
                            .font(SavantFont.mono(11, weight: .bold))
                            .foregroundStyle(percentileValue >= 35 && percentileValue <= 75 ? SavantPalette.ink : .white)
                            .shadow(color: percentileValue >= 35 && percentileValue <= 75 ? Color.clear : Color.black.opacity(0.3), radius: 1, x: 0, y: 0.5)
                    }
                    .position(x: offset, y: 14)
                }
            }
            .frame(height: 28)

            // Value column - far right, fixed width (sized for "30.0 ft/s" / "0.421" range)
            if showValue && !metric.value.isEmpty {
                Text(metric.value)
                    .font(SavantType.statMed)
                    .foregroundStyle(SavantPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 72, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: 72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Season + recent percentile bars stacked in one row, same Savant layout,
/// with a compact recent track under the season bar when both are available.
struct DualMetricBar: View {
    let season: Metric
    var recent: Metric?
    var recentCaption: String = "Recent"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Season")
                    .font(SavantType.micro)
                    .tracking(0.4)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .frame(width: 52, alignment: .leading)
                MetricBar(metric: season, showValue: true)
            }

            if let recent {
                HStack(spacing: 6) {
                    Text(recentCaption)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.savantRed)
                        .frame(width: 52, alignment: .leading)
                    MetricBar(metric: recent, showValue: true)
                }
            }
        }
    }
}

// MARK: - Search (restyled for light mode)

struct SearchField: View {
    @Binding var text: String
    var focusOnAppear: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SavantPalette.inkSecondary)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Search players or teams")
                        .font(SavantType.body)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(SavantPalette.ink)
                    .focused($isFocused)
            }
        }
        .onAppear {
            if focusOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Category Tabs (Module 5 variant for dashboard)

struct CategoryFilter: View {
    @Binding var selectedCategory: MetricCategory?
    var showAllOption: Bool = false

    var body: some View {
        let categoryTabs = MetricCategory.allCases.map { $0.rawValue }
        let tabs = showAllOption ? ["All"] + categoryTabs : categoryTabs
        let selectedTab = selectedCategory?.rawValue ?? (showAllOption ? "All" : MetricCategory.hitting.rawValue)

        SavantTabs(
            tabs: tabs,
            selected: Binding(
                get: { selectedTab },
                set: { newValue in
                    if showAllOption && newValue == "All" {
                        selectedCategory = nil
                    } else {
                        selectedCategory = MetricCategory.allCases.first { $0.rawValue == newValue }
                    }
                }
            )
        )
    }
}

// MARK: - Section Header (legacy, minimal use)

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SavantType.sectionTitle)
                .tracking(0.8)
                .foregroundStyle(SavantPalette.ink)
            Text(subtitle)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
        }
    }
}

// MARK: - Trend Glyph

struct TrendGlyph: View {
    let direction: MetricDirection

    var body: some View {
        Image(systemName: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(color)
    }

    private var icon: String {
        switch direction {
        case .up: "arrow.up.right"
        case .flat: "minus"
        case .down: "arrow.down.right"
        }
    }

    private var color: Color {
        switch direction {
        case .up: SavantPalette.up
        case .flat: SavantPalette.inkTertiary
        case .down: SavantPalette.down
        }
    }
}

// MARK: - Percentile Bar Mini (for leaderboards)

struct PercentileBarMini: View {
    let percentile: Int
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height/2)
                    .fill(SavantPalette.hairline)
                    .frame(height: height)

                RoundedRectangle(cornerRadius: height/2)
                    .fill(SavantPalette.color(forPercentile: percentile))
                    .frame(width: proxy.size.width * CGFloat(percentile) / 100.0, height: height)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Leaderboard Table

struct LeaderboardTableHeader: View {
    let sortDescending: Bool
    var sortLabel: String = "OVERALL"

    var body: some View {
        HStack(spacing: 0) {
            Text("RANK")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 42, alignment: .leading)

            Text("PLAYER")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("TEAM")
                .font(SavantType.micro)
                .tracking(0.5)
                .foregroundStyle(SavantPalette.inkTertiary)
                .frame(width: 44, alignment: .leading)

            // Sort indicator - display only, tap SavantSectionBar to change sort
            HStack(spacing: 4) {
                Text(sortLabel.uppercased())
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.savantRed)
                Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SavantPalette.savantRed)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .frame(height: SavantGeo.rowHeightHeader)
        .padding(.horizontal, SavantGeo.padInline)
        .background(SavantPalette.surfaceAlt)
        .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .bottom)
    }
}

/// Recent-vs-prior change for one metric, drawn as an arrow and a magnitude.
///
/// Drawn only on boards that are explicitly in a rolling-window mode: the
/// Trends tab, the team form cards, the team roster with Recent on. It used to
/// ride along as an extra column on the season leaderboard too, where it only
/// rendered for the players the window happened to cover: rows with a trend
/// lost their percentile bar and rows without it kept one, so the app's
/// most-read column changed shape halfway down the list. Trends are a screen,
/// not a garnish on the season leaderboard.
struct TrendArrow: View {
    let delta: Double
    /// Percent-style metrics move in whole numbers, rate stats in thousandths.
    var decimals: Int = 3
    /// For metrics where down is the good direction, a hitter's Chase% or a
    /// pitcher's opponent xwOBA. The arrow still points the way the number
    /// actually moved; only the colour flips, so red always means "better".
    var lowerIsBetter: Bool = false

    /// Below half of the last displayed digit a delta is noise, and an arrow
    /// would imply a signal: .005 for rate stats, 0.05 for a mph or percent
    /// reported to a tenth, 0.5 for whole numbers.
    private var isFlat: Bool { abs(delta) < 5 * pow(10, -Double(decimals + 1)) }

    private var tint: Color {
        if isFlat { return SavantPalette.inkTertiary }
        let improved = lowerIsBetter ? delta < 0 : delta > 0
        return improved ? SavantPalette.pctlHot : SavantPalette.pctlCold
    }

    private var text: String {
        if isFlat { return "0" }
        let magnitude = abs(delta)
        let formatted = String(format: "%.\(decimals)f", magnitude)
        // Rate stats are written Savant-style, without the leading zero.
        return decimals == 3 ? formatted.replacingOccurrences(of: "0.", with: ".") : formatted
    }

    var body: some View {
        HStack(spacing: 2) {
            if !isFlat {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(SavantType.micro)
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .accessibilityLabel(
            isFlat ? "No recent change" : "\(delta > 0 ? "Up" : "Down") \(text) recently"
        )
    }
}

struct LeaderboardTableRow: View {
    let rank: Int
    let player: Player
    var metricLabel: String? = nil
    var metricCategory: MetricCategory? = nil
    /// Recent-vs-prior change in the displayed metric. Only ever set alongside
    /// `valueOverride`, i.e. on a board that is explicitly in its rolling-window
    /// mode; a trend that appears on some rows of a season board and not others
    /// is the bug this pairing exists to prevent.
    var trendDelta: Double? = nil
    var trendDecimals: Int = 3
    /// The rolling-window value, shown in place of the season number when the
    /// list is ranking by recent form. Uncoloured: the season percentile is the
    /// wrong ruler for a fortnight's number, and there is no window curve to
    /// place it on.
    var valueOverride: String? = nil

    private var displayMetric: Metric? {
        guard let label = metricLabel else { return nil }
        // When no category is active (the all-categories leaderboard) fall back
        // to matching on label alone so we still surface the player's xwOBA
        // entry regardless of whether it lives under hitting or pitching.
        if let category = metricCategory {
            return player.metrics.first { $0.label == label && $0.category == category }
        }
        return player.metrics.first { $0.label == label }
    }

    private var displayPercentile: Int {
        displayMetric?.percentile ?? 0
    }

    // Raw stat value where there is one. The colored bar to the left already
    // conveys the percentile, so repeating it here would read as "the stat
    // value" at a glance, but a whole column of dashes on a board Savant ranks
    // (Arm Strength before its value source was wired up) is worse: it says the
    // app has nothing when it has the ranking the page is sorted by. Falling
    // back to an explicitly-labelled percentile keeps the column honest.
    private var displayValueText: String {
        if let valueOverride { return valueOverride }
        guard let metric = displayMetric else { return "-" }
        if !metric.value.isEmpty { return metric.value }
        // The ordinal is what distinguishes the two: "94th" can't be misread as
        // a rate the way a bare "94" can.
        return metric.percentile.ordinal
    }

    /// A window value has no percentile behind it, so it stays ink rather than
    /// borrowing the season bar's colour and implying a rank it doesn't have.
    private var displayValueColor: Color {
        valueOverride == nil ? SavantPalette.textColor(forPercentile: displayPercentile) : SavantPalette.ink
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(SavantType.statSmall)
                .foregroundStyle(SavantPalette.inkSecondary)
                .frame(width: 42, alignment: .leading)
                .monospacedDigit()

            HStack(spacing: 10) {
                PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    Text(player.displayPosition)
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                TeamColorDot(abbr: player.team, size: 6)
                Text(displayTeamAbbr(player.team))
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .frame(width: 44, alignment: .leading)

            HStack(spacing: 8) {
                // A player without the sorted metric gets no bar, drawing one
                // from their overall percentile would mislabel a different number
                // as this column's stat. Show a muted "-" instead.
                if displayMetric != nil || valueOverride != nil {
                    // A window value drops the bar: the season percentile bar
                    // beside a fortnight's number reads as that number's rank.
                    if valueOverride == nil {
                        PercentileBarMini(percentile: displayPercentile)
                            .frame(width: 36)
                    }
                    Text(displayValueText)
                        .font(SavantType.statSmall)
                        .foregroundStyle(displayValueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 48, alignment: .trailing)
                        .monospacedDigit()
                } else {
                    Text("-")
                        .font(SavantType.statSmall)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .frame(width: trendDelta == nil ? 92 : 56, alignment: .trailing)

            if let trendDelta {
                TrendArrow(delta: trendDelta, decimals: trendDecimals)
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .frame(height: SavantGeo.rowHeight)
        .padding(.horizontal, SavantGeo.padInline)
        .background(rank % 2 == 1 ? SavantPalette.surface : SavantPalette.surfaceAlt)
        .contentShape(Rectangle())
    }
}

// MARK: - Blur Gate Unlock

/// Compact unlock affordance for Pro-gated, blurred teasers. Anchors to the
/// bottom over a gradient that fades the blurred preview into the card surface,
/// so the teaser stays visible as the hook instead of being buried under an
/// opaque panel. Used by RecentFormCard, TeamRankingsCard, and YearComparePreview.
///
/// The CTA transacts. It used to open `TrialPitchSheet`, which showed the same
/// offer a second time under a second button, so a user who had already said
/// yes to "Start 7-day free trial" had to say it again before Apple's confirm
/// sheet ever appeared. The button says what it does and then does it; the plan
/// picker stays reachable behind a quiet "See all plans" link for anyone who
/// actually wants to weigh monthly against lifetime.
/// A card whose data didn't load, and the way to ask for it again.
///
/// These cards live inside scroll views that own no refresh gesture, so the
/// copy used to end in "Pull to refresh" and name an affordance that wasn't
/// there. A button is both honest and one tap instead of a hunt.
struct InlineLoadError: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await retry() }
            }
            .font(SavantType.smallBold)
            .foregroundStyle(SavantPalette.savantRed)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SavantGeo.padInline)
        .padding(.vertical, 24)
    }
}

struct BlurGateUnlock: View {
    let headline: String
    /// Entry point this gate represents, drives the impression id and the
    /// copy on the plan picker, if the user asks for it.
    let trigger: PaywallTrigger

    var body: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PlusDirectCTA(trigger: trigger, style: .capsule)
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, SavantPalette.surface.opacity(0.95), SavantPalette.surface],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - One-tap StatScout+ CTA

/// The app's only in-place conversion control, and the reason there is no
/// pitch-then-pitch path left.
///
/// Every surface that names an offer, the blurred gates, the player-page
/// upsell card, the trial sheet's footer, used to hand off to another screen
/// that showed the same offer under another button. This one transacts: tap it
/// and the next thing on screen is Apple's confirm sheet. The plan picker is
/// still there for anyone who wants to weigh monthly against lifetime, but it's
/// a quiet text link rather than a toll gate, and it's also where a failed
/// product load lands because that's the only screen that can retry.
struct PlusDirectCTA: View {
    enum Style {
        /// Compact pill, for the bottom of a blurred teaser.
        case capsule
        /// Full-width bar, for a card or sheet footer.
        case bar
    }

    @EnvironmentObject private var store: StoreService

    let trigger: PaywallTrigger
    var style: Style = .bar
    /// Hidden where the surrounding screen already offers plan choice.
    var showsAllPlansLink: Bool = true

    @State private var isPurchasing = false
    @State private var statusMessage: String?
    @State private var showingPlans = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: buy) {
                label
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityLabel(store.directCTALabel(for: trigger))

            // Full auto-renew terms sit beside the purchase point, because this
            // button *is* the purchase point now (Apple 3.1.2).
            if let disclosure = store.yearlyCTADisclosureText ?? store.paywallBlurSubtext {
                Text(disclosure)
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(SavantType.micro)
                    .foregroundStyle(SavantPalette.savantRed)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsAllPlansLink {
                Button("See all plans") { showingPlans = true }
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            store.trackPaywallImpression(id: trigger.paywallImpressionId, oncePerSession: true)
            if store.currentOffering == nil { await store.fetchProducts() }
        }
        .sheet(isPresented: $showingPlans) {
            PaywallView(trigger: trigger)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .capsule:
            HStack(spacing: 6) {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11))
                    Text(store.directCTALabel(for: trigger))
                        .font(SavantType.bodyBold)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(SavantPalette.savantRed)
            .clipShape(Capsule())
        case .bar:
            ZStack {
                Text(store.directCTALabel(for: trigger))
                    .font(SavantType.bodyBold)
                    .opacity(isPurchasing ? 0 : 1)
                if isPurchasing {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(SavantPalette.savantRed)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func buy() {
        statusMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            switch await store.purchaseYearlyDirect() {
            case .unlocked:
                break
            case .pending:
                // Ask-to-Buy / deferred payment: not unlocked, not an error.
                statusMessage = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
            case .cancelled:
                statusMessage = "Purchase cancelled. Tap again to continue."
            case .failed(let message):
                statusMessage = message
            case .needsPlanPicker:
                // Nothing loaded to buy, the picker's retry/empty state is the
                // only surface that can say so and recover.
                showingPlans = true
            }
        }
    }
}

// MARK: - Int Ordinal Extension

extension Int {
    var ordinal: String {
        let suffix: String
        switch self % 100 {
        case 11...13: suffix = "th"
        default:
            switch self % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(self)\(suffix)"
    }
}

// MARK: - Extensions for Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
