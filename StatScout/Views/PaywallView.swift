import SwiftUI
@preconcurrency import RevenueCat

enum PaywallTrigger: Identifiable, Hashable {
    var id: Self { self }

    case pastSeason
    case yearCompare
    case playerComparison
    case onboarding
    case activation
    case upgrade
    case pastSeasonsLoad
    case teamView
    case winback
    /// Soft, half-sheet trial pitch shown on a free user's first player open.
    /// Distinct from the old `.activation` full-PaywallView popup (removed for
    /// being too intrusive) — this routes through TrialPitchSheet, which is
    /// native/intentional, dismissible with "Maybe later", and gated by
    /// PaywallGate so it caps at 2 per session.
    case playerScouting
    /// Soft pitch from the blurred Recent Form teaser on the leaderboard.
    case recentForm

    var icon: String {
        switch self {
        case .pastSeason:        return "calendar.badge.clock"
        case .yearCompare:       return "arrow.left.arrow.right.circle.fill"
        case .playerComparison:  return "person.2.fill"
        case .onboarding:        return "crown.fill"
        case .activation:        return "crown.fill"
        case .upgrade:           return "crown.fill"
        case .pastSeasonsLoad:   return "clock.arrow.circlepath"
        case .teamView:          return "shield.lefthalf.filled"
        case .winback:           return "arrow.counterclockwise.circle.fill"
        case .playerScouting:    return "binoculars.fill"
        case .recentForm:        return "flame.fill"
        }
    }

    var title: String {
        switch self {
        case .pastSeason:        return "Unlock Past Seasons"
        case .yearCompare:       return "Year-over-Year Comparison"
        case .playerComparison:  return "Player Comparison"
        case .onboarding:        return "Go Pro"
        case .activation:        return "Unlock the Full Game"
        case .upgrade:           return "StatScout Pro"
        case .pastSeasonsLoad:   return "Load Past Seasons"
        case .teamView:          return "Team Insights"
        case .winback:           return "Welcome Back"
        case .playerScouting:    return "Full Player Scouting"
        case .recentForm:        return "Recent Form"
        }
    }

    var subtitle: String {
        switch self {
        case .pastSeason:
            return "See how your favorite players ranked in previous seasons. Track the trends that tell the full story."
        case .yearCompare:
            return "Compare a player's percentile rankings across any two seasons. See what changed, what held, and where they're headed."
        case .playerComparison:
            return "Compare any two players side by side across every metric. Find who leads in xwOBA, Barrel%, Sprint Speed, and more."
        case .onboarding:
            return "Current season is free. Pro unlocks historical seasons, year-over-year comparisons, and head-to-head player matchups."
        case .activation:
            return "You're all set with the current season. Pro adds every past season, year-over-year trends, and head-to-head player matchups — the full scouting picture."
        case .upgrade:
            return "Unlock historical seasons and year-over-year comparisons."
        case .pastSeasonsLoad:
            return "Load historical data to explore past seasons, year-over-year trends, and more."
        case .teamView:
            return "Get full team rosters, player breakdowns, and side-by-side comparisons for every squad."
        case .winback:
            return "Your Pro access has lapsed. Renew to get historical seasons, year-over-year trends, and head-to-head matchups back."
        case .playerScouting:
            return "See last 7 / 15 / 30 day form, stack players head-to-head, and scout every roster — the full picture, not just season totals."
        case .recentForm:
            return "See every player's last 7 / 15 / 30 day form — spot who's heating up or cooling off before the season totals catch up."
        }
    }

    /// RevenueCat custom-paywall impression id for this entry point.
    var paywallImpressionId: String {
        switch self {
        case .pastSeason:        return "statscout_paywall_past_season"
        case .yearCompare:       return "statscout_paywall_year_compare"
        case .playerComparison:  return "statscout_paywall_player_comparison"
        case .onboarding:        return "statscout_paywall_onboarding"
        case .activation:        return "statscout_paywall_activation"
        case .upgrade:           return "statscout_paywall_upgrade"
        case .pastSeasonsLoad:   return "statscout_paywall_past_seasons_load"
        case .teamView:          return "statscout_paywall_team_view"
        case .winback:           return "statscout_paywall_winback"
        case .playerScouting:    return "statscout_paywall_player_scouting"
        case .recentForm:        return "statscout_paywall_recent_form"
        }
    }

    private static let proFeatures: [(icon: String, title: String)] = [
        ("calendar.badge.clock", "Every past season back to 2020"),
        ("arrow.left.arrow.right.circle.fill", "Year-over-year percentile trends"),
        ("person.2.fill", "Head-to-head player matchups"),
        ("flame.fill", "Recent form — last 7 / 15 / 30 days")
    ]

    var features: [(icon: String, title: String)] {
        Self.proFeatures
    }
}

/// Native StatScout Pro paywall. Purchases flow through `StoreService.purchase`
/// → `Purchases.shared.purchase` so RevenueCat records transactions unchanged.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var hasDismissed = false

    init(trigger: PaywallTrigger = .upgrade) {
        self.trigger = trigger
    }

    var body: some View {
        ZStack {
            SavantPalette.canvas.ignoresSafeArea()

            if store.isLoadingProducts && store.products.isEmpty {
                loadingState
            } else if store.products.isEmpty {
                emptyState
            } else {
                content
            }

            closeButton
        }
        .onAppear { PaywallGate.shared.markPresented(trigger) }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismissOnce() }
        }
        .task {
            store.trackPaywallImpression(id: trigger.paywallImpressionId)
            if store.products.isEmpty { await store.fetchProducts() }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: store.products.count) { _, _ in selectDefaultPackageIfNeeded() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(SavantPalette.savantRed)
            Text("Loading plans…")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(SavantPalette.inkTertiary)
            Text("Couldn't Load Plans")
                .font(SavantType.cardTitle)
                .foregroundStyle(SavantPalette.inkSecondary)
            Text(store.lastError ?? "Check your connection and try again.")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task {
                    await store.fetchProducts()
                    selectDefaultPackageIfNeeded()
                }
            }
            .font(SavantType.bodyBold)
            .foregroundStyle(SavantPalette.savantRed)
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader

                VStack(spacing: 20) {
                    featureList
                    trustRow
                    planCards
                    purchaseSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // Bold navy hero: the entry-point icon over a faint percentile-bar motif,
    // a "Pro" eyebrow, the benefit headline, and the emotional subtitle. Sells
    // the upgrade before any pricing — pricing/feature density comes below.
    private var heroHeader: some View {
        ZStack {
            LinearGradient(
                colors: [SavantPalette.savantNavy, SavantPalette.savantNavy.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            PaywallBarBackdrop()
                .opacity(0.16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 78, height: 78)
                    Image(systemName: trigger.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("STATSCOUT PRO")
                    .font(SavantType.micro)
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.65))

                Text(trigger.title)
                    .font(SavantType.playerName)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(trigger.subtitle)
                    .font(SavantType.small)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)
            }
            .padding(.top, 72)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(trigger.features, id: \.title) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SavantPalette.savantRed)
                        .frame(width: 26)
                    Text(feature.title)
                        .font(SavantType.body)
                        .foregroundStyle(SavantPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Reassurance, not social proof — no fabricated ratings or user counts.
    private var trustRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Cancel anytime · No commitment")
                .font(SavantType.smallBold)
                .tracking(0.2)
        }
        .foregroundStyle(SavantPalette.inkTertiary)
        .frame(maxWidth: .infinity)
    }

    private var planCards: some View {
        VStack(spacing: 8) {
            ForEach(store.products, id: \.identifier) { package in
                PaywallPlanCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier,
                    showsTrialBadge: store.isEligibleForIntroOffer(package),
                    isBestValue: package.productKind == .yearly
                ) {
                    selectedPackage = package
                }
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            Button(action: startPurchase) {
                ZStack {
                    Text(ctaTitle)
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SavantPalette.savantRed)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPackage == nil)

            if let disclosure = disclosureText {
                Text(disclosure)
                    .font(SavantType.micro)
                    .tracking(0.2)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.savantRed)
                    .multilineTextAlignment(.center)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: startRestore) {
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(SavantType.smallBold)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)

            HStack(spacing: 12) {
                Link("Terms", destination: StatScoutLegal.termsURL)
                Link("Privacy", destination: StatScoutLegal.privacyURL)
            }
            .font(SavantType.micro)
            .tracking(0.3)
            .foregroundStyle(SavantPalette.inkTertiary)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismissOnce() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.28))
                        .padding(16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Spacer()
        }
    }

    // MARK: - Copy

    private var ctaTitle: String {
        guard let package = selectedPackage else { return "Continue" }
        if package.productKind == .lifetime { return "Unlock Lifetime" }
        if store.isEligibleForIntroOffer(package) { return "Start Free Trial" }
        return "Subscribe"
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    private var disclosureText: String? {
        guard let package = selectedPackage else { return nil }
        let price = package.priceLabel
        if package.productKind == .lifetime {
            return "\(price). One-time purchase. Lifetime access, no subscription."
        }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
        if store.isEligibleForIntroOffer(package), let trial = package.introOfferLabel {
            return "\(trial.capitalized), then \(price). \(renew)"
        }
        return "\(price). \(renew)"
    }

    // MARK: - Actions

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackage == nil, !store.products.isEmpty else { return }
        selectedPackage = store.products.first { $0.productKind == .yearly }
            ?? store.products.first
    }

    private func startPurchase() {
        guard let package = selectedPackage else { return }
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(package) {
                case .purchased, .pending:
                    break
                case .cancelled:
                    errorMessage = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                errorMessage = store.lastError ?? "Couldn't complete the purchase. Please try again."
            }
        }
    }

    private func startRestore() {
        errorMessage = nil
        restoreMessage = nil
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await store.restorePurchases()
            if !store.isPro {
                restoreMessage = store.lastError ?? "No active StatScout Pro purchase was found for this Apple ID."
            }
        }
    }

    private func dismissOnce() {
        guard !hasDismissed else { return }
        hasDismissed = true
        dismiss()
    }
}

/// Faint percentile-bar motif behind the hero — ties the paywall to the
/// app's Statcast leaderboard visual language without competing with the copy.
private struct PaywallBarBackdrop: View {
    private let percentiles: [Int] = [94, 81, 67, 52, 38, 88, 73, 60, 45, 83, 70]

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(percentiles.enumerated()), id: \.offset) { _, pct in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 13, height: CGFloat(pct) * 1.05)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

private struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let showsTrialBadge: Bool
    let isBestValue: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? SavantPalette.savantRed : SavantPalette.hairline, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(SavantPalette.savantRed)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(package.displayName)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(SavantType.micro)
                                .tracking(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SavantPalette.savantRed, in: Capsule())
                        }
                    }
                    if showsTrialBadge, let trial = package.introOfferLabel {
                        Text(trial.capitalized)
                            .font(SavantType.micro)
                            .tracking(0.3)
                            .foregroundStyle(SavantPalette.savantRed)
                    }
                }

                Spacer(minLength: 8)

                Text(package.priceLabel)
                    .font(SavantType.smallBold)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            .overlay {
                RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                    .stroke(isSelected ? SavantPalette.savantRed : SavantPalette.hairline, lineWidth: isSelected ? 2 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
