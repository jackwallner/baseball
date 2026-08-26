import SwiftUI
import RevenueCat

@main
struct StatScoutApp: App {
    private let api: StatcastAPI?
    @StateObject private var store = StoreService.shared

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["STATSCOUT_RESET_TEAM_FAVORITE"] == "1" {
            UserDefaults.standard.removeObject(forKey: "favoriteTeam")
        }
        #endif
        ReviewPromptTracker.recordAppLaunch()
        guard let urlString = Self.configValue(for: "SUPABASE_URL"),
              let url = URL(string: urlString),
              let key = Self.configValue(for: "SUPABASE_ANON_KEY") else {
            self.api = nil
            return
        }
        self.api = StatcastAPI(baseURL: url, apiKey: key)
        StoreService.shared.start()
    }

    private static func configValue(for key: String) -> String? {
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !plistValue.isEmpty,
           !plistValue.hasPrefix("$(") {
            return plistValue
        }
        return ProcessInfo.processInfo.environment[key]
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let mode = PaywallScreenshotMode.current {
                PaywallScreenshotHarness(mode: mode)
                    .environmentObject(store)
                    .preferredColorScheme(.light)
            } else if let api {
                ContentView(api: api)
                    .environmentObject(store)
                    .preferredColorScheme(.light)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        Task { await store.updateCustomerProductStatus() }
                    }
            } else {
                ConfigMissingView()
                    .preferredColorScheme(.light)
            }
            #else
            if let api {
                ContentView(api: api)
                    .environmentObject(store)
                    .preferredColorScheme(.light)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        Task { await store.updateCustomerProductStatus() }
                    }
            } else {
                ConfigMissingView()
                    .preferredColorScheme(.light)
            }
            #endif
        }
    }
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(UpdateShowcaseCampaign.storageKey) private var seenUpdateShowcase = ""
    @EnvironmentObject private var store: StoreService

    @State private var viewModel: DashboardViewModel
    @State private var showUpdateShowcase = false

    init(api: StatcastAPI) {
        _viewModel = State(initialValue: DashboardViewModel(provider: api, cache: TwoTierPlayerCache()))
    }

    var body: some View {
        ZStack {
            RootTabView(viewModel: viewModel)
                .disabled(!hasCompletedOnboarding || showUpdateShowcase)
                .allowsHitTesting(hasCompletedOnboarding && !showUpdateShowcase)

            if !hasCompletedOnboarding {
                OnboardingCards(viewModel: viewModel, hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if showUpdateShowcase {
                UpdateShowcaseView(onFinish: finishUpdateShowcase)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .onAppear {
            viewModel.applyProState(store.isPro)
            evaluateUpdateShowcase()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.load() }
        }
        .onChange(of: store.isPro) { _, isPro in
            viewModel.applyProState(isPro)
        }
    }

    private func evaluateUpdateShowcase() {
        let decision = UpdateShowcaseCampaign.decision(
            hasCompletedOnboarding: hasCompletedOnboarding,
            seenCampaign: seenUpdateShowcase,
            forcePresentation: UpdateShowcaseCampaign.isForced
        )
        if decision.shouldMarkSeen {
            seenUpdateShowcase = UpdateShowcaseCampaign.identifier
        }
        showUpdateShowcase = decision.shouldPresent
    }

    private func finishUpdateShowcase() {
        seenUpdateShowcase = UpdateShowcaseCampaign.identifier
        withAnimation { showUpdateShowcase = false }
    }
}

struct BulletItem: Identifiable {
    let id = UUID()
    let text: String
    let icon: String
    let color: Color
}

/// Height-driven sizing for the onboarding flow.
///
/// Onboarding used to be built for a modern iPhone's ~780pt of usable height
/// and nothing else: fixed hero art, fixed spacing, and a bottom stack that
/// reserved the last page's upsell block on every page. On a short canvas that
/// arithmetic overflows, and SwiftUI resolves the overflow by collapsing each
/// `Text` to a single truncated line and clipping whatever is left, which is
/// what App Review saw on an iPad (an iPhone-only app gets a 375x622pt
/// compatibility window there) and what an iPhone SE owner has been seeing all
/// along.
///
/// So every fixed number in the flow comes from here, and shrinks when the
/// canvas is short. Nothing in the layout reads a device idiom: it reads the
/// height it was actually given.
struct OnboardingMetrics {
    let isCompact: Bool

    init(availableHeight: CGFloat) {
        // A modern iPhone leaves ~760pt inside the safe area; an iPhone SE and
        // the iPad compatibility window leave ~620-650.
        isCompact = availableHeight < 720
    }

    /// Onboarding is a single centred column. Left to itself it would stretch
    /// the full width of a wide window and leave 60-character measure lines.
    var maxContentWidth: CGFloat { 460 }

    var headerHeight: CGFloat { isCompact ? 28 : 32 }
    var heroCircle: CGFloat { isCompact ? 62 : 96 }
    var heroIcon: CGFloat { isCompact ? 27 : 42 }
    var heroBackdrop: CGSize { isCompact ? CGSize(width: 150, height: 72) : CGSize(width: 220, height: 120) }
    var heroBackdropScale: CGFloat { isCompact ? 0.6 : 1 }
    var cardSpacing: CGFloat { isCompact ? 12 : 20 }
    var bulletSpacing: CGFloat { isCompact ? 7 : 10 }
    var copyInset: CGFloat { isCompact ? 20 : 32 }
    var bulletInset: CGFloat { isCompact ? 22 : 36 }
    var titleFont: Font { isCompact ? SavantType.pageTitle : SavantType.playerName }

    /// Breathing room under the last bullet. Small, because the paging dots
    /// are no longer drawn on top of it (see `OnboardingCards.header`).
    var pageIndicatorInset: CGFloat { 4 }

    var stackSpacing: CGFloat { isCompact ? 8 : 10 }
    var statusLineHeight: CGFloat { isCompact ? 18 : 32 }
    var primaryButtonHeight: CGFloat { isCompact ? 48 : 52 }
    var footerHeight: CGFloat { isCompact ? 20 : 24 }
    var bottomPadding: CGFloat { isCompact ? 14 : 32 }

    /// On a tall canvas the last page's upsell block is reserved (invisible) on
    /// every page, so the red CTA never moves as pages swipe past. On a short
    /// canvas that reservation costs ~160pt the card needs to render at all, so
    /// the block is inserted only where it is used and the CTA is allowed to
    /// move once, on arrival at the last page.
    var reservesUpsellBlock: Bool { !isCompact }
}

struct OnboardingCards: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var paywallTrigger: PaywallTrigger?
    @State private var isStartingTrial = false
    @State private var trialError: String?
    @State private var isRestoring = false

    private var isLastPage: Bool { currentPage == pages.count - 1 }
    private var dataReady: Bool { viewModel.isReady }
    /// The free-tier exit + trial legalese only mean anything on the last page
    /// for a non-subscriber, but the space is reserved on every page.
    private var showsUpsellBlock: Bool { isLastPage && !store.isPro }

    /// CTA label / disclosure mirror the direct-purchase pop-ups: trial copy
    /// when eligible, price-forward monthly copy otherwise. Both come from
    /// StoreService so every one-tap conversion surface reads the same.
    private var proCTALabel: String {
        store.onboardingMonthlyCTALabel
    }

    private var trialDisclosure: String? {
        store.onboardingMonthlyDisclosureText
    }

    var body: some View {
        ZStack {
            SavantPalette.canvas.ignoresSafeArea()

            GeometryReader { geo in
                let metrics = OnboardingMetrics(availableHeight: geo.size.height)
                VStack(spacing: 0) {
                    // Fixed-height header: Skip fades out on the last page rather
                    // than being removed, so the TabView below it never changes
                    // height and the card content never shifts mid-swipe.
                    //
                    // The paging dots live here, opposite Skip, rather than in
                    // the page style's own overlay. That overlay draws them *on*
                    // the bottom of the card, which put them across the last
                    // bullet of every full page at every screen size; this row
                    // is space the layout already reserves.
                    HStack {
                        HStack(spacing: 6) {
                            ForEach(pages.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == currentPage ? SavantPalette.ink : SavantPalette.inkTertiary.opacity(0.4))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(.leading, 20)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
                        Spacer()
                        Button("Skip") {
                            withAnimation { hasCompletedOnboarding = true }
                        }
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.savantRed)
                        .padding(.trailing, 20)
                        .opacity(isLastPage ? 0 : 1)
                        .allowsHitTesting(!isLastPage)
                    }
                    .frame(height: metrics.headerHeight)

                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingCard(
                                icon: page.icon,
                                title: page.title,
                                description: page.description,
                                bullets: page.bullets,
                                metrics: metrics
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    bottomButtons(metrics)
                        .padding(.horizontal, 24)
                        .padding(.bottom, metrics.bottomPadding)
                }
                .frame(maxWidth: metrics.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if store.currentOffering == nil {
                await store.fetchProducts()
            }
        }
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro {
                paywallTrigger = nil
                withAnimation { hasCompletedOnboarding = true }
            }
        }
    }

    @ViewBuilder
    private func bottomButtons(_ metrics: OnboardingMetrics) -> some View {
        // Layout invariant on a tall canvas: this whole stack is the SAME
        // HEIGHT on every page. Every slot is either fixed (the red button, the
        // status line, the footer) or always present and merely faded (the
        // upsell block). Nothing is conditionally inserted or removed, which
        // keeps two things true at once: the red button is pixel-identical
        // across pages, and the TabView above never resizes, so card content
        // can't drift on a swipe.
        //
        // On a short canvas the upsell reservation is dropped instead (see
        // `OnboardingMetrics.reservesUpsellBlock`): the CTA moves once, on
        // arrival at the last page, and the card gets the ~160pt it needs to
        // render at all. Every other slot still comes from `metrics`, so the
        // stack shrinks as a whole rather than overflowing.
        VStack(spacing: metrics.stackSpacing) {
            // --- Above the primary button ---
            // Always in the layout, faded out where it doesn't apply. It used to
            // be inserted only on the last page, which grew this bottom-anchored
            // stack by ~130pt on arrival: the TabView above absorbed the change,
            // so the card's icon, title and bullets visibly floated up as the
            // StatScout+ page came in. Reserving the space on every page keeps
            // the TabView one constant height and kills the float.
            VStack(spacing: metrics.stackSpacing) {
                getStartedButton(prominent: false, metrics: metrics)

                // Reserved fixed-height status line: a restore/purchase result
                // fills this slot in place instead of being inserted, so nothing
                // above the button shifts either.
                Text(trialError ?? " ")
                    .font(SavantType.micro)
                    .foregroundStyle(SavantPalette.savantRed)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: metrics.statusLineHeight, alignment: .top)

                if let disclosure = trialDisclosure {
                    Text(disclosure)
                        .font(SavantType.micro)
                        .tracking(0.3)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Terms/Privacy sit just above the purchase point (this CTA can
                // buy the trial directly, no PaywallView handoff).
                HStack(spacing: 12) {
                    Link("Terms", destination: StatScoutLegal.termsURL)
                    Link("Privacy", destination: StatScoutLegal.privacyURL)
                }
                .font(SavantType.micro)
                .tracking(0.3)
                .foregroundStyle(SavantPalette.inkTertiary)

                // Billed amount, last thing before the CTA. Apple 3.1.2(c):
                // the trial named on the button can't be more conspicuous than
                // the price, so this sits one type step above the button label
                // and stays the largest pricing element on the page.
                //
                // Fixed height, for the same reason the status line above it is
                // reserved rather than inserted. `monthlyPackage` is nil until
                // RevenueCat answers, so an unreserved slot appears late and
                // pushes the red button down the screen at the exact moment a
                // thumb is travelling toward it.
                Text(store.monthlyPackage?.priceLabel ?? " ")
                    .font(SavantType.priceLead)
                    .foregroundStyle(SavantPalette.ink)
                    .frame(height: 20)
            }
            // Reserved-and-faded on a tall canvas (the CTA then never moves);
            // simply absent on a short one, where the reservation is the
            // difference between the card rendering and the card clipping.
            .opacity(showsUpsellBlock ? 1 : 0)
            .allowsHitTesting(showsUpsellBlock)
            .accessibilityHidden(!showsUpsellBlock)
            .frame(height: (metrics.reservesUpsellBlock || showsUpsellBlock) ? nil : 0)
            .clipped()

            // --- Primary red button: identical slot on every page ---
            if isLastPage {
                if store.isPro {
                    getStartedButton(prominent: true, metrics: metrics)
                } else {
                    Button {
                        buyMonthly()
                    } label: {
                        ZStack {
                            Text(proCTALabel)
                                .opacity(isStartingTrial ? 0 : 1)
                            if isStartingTrial {
                                ProgressView().tint(.white)
                            }
                        }
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.primaryButtonHeight)
                        .background(SavantPalette.savantRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingTrial)
                }
            } else {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Continue")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.primaryButtonHeight)
                        .background(SavantPalette.savantRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            // --- Fixed 24pt footer slot BELOW the button, identical every page.
            // On the last page it carries Restore (or the loading state); on the
            // others it is empty. Its constant height is what keeps the button's
            // bottom edge, and therefore its Y, pinned across pages.
            Group {
                if isLastPage, !dataReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(SavantPalette.inkSecondary)
                            .scaleEffect(0.7)
                        Text(viewModel.loadingMessage)
                            .font(SavantType.micro)
                            .tracking(0.4)
                    }
                    .foregroundStyle(SavantPalette.inkSecondary)
                } else if isLastPage && !store.isPro {
                    Button {
                        // Surface the outcome through the same trialError line the
                        // purchase CTA uses, a restore that silently does nothing
                        // reads as a dead button. Success flips isPro, which
                        // finishes onboarding via onChange.
                        isRestoring = true
                        Task { @MainActor in
                            defer { isRestoring = false }
                            await store.restorePurchases()
                            if !store.isPro {
                                trialError = store.lastError ?? "No active StatScout+ purchase was found for this Apple ID."
                            }
                        }
                    } label: {
                        Text(isRestoring ? "Restoring…" : "Restore Purchases")
                            .font(SavantType.micro)
                            .tracking(0.4)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)
                } else {
                    Color.clear
                }
            }
            .frame(height: metrics.footerHeight)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    /// "Get Started" dismisses onboarding into the free tier. `prominent` is the
    /// solo state (Pro users, where it's the only, and primary, action, a
    /// filled button); otherwise it's a de-emphasized, borderless text link that
    /// sits above the red trial CTA so it never competes for the tap.
    private func getStartedButton(prominent: Bool, metrics: OnboardingMetrics) -> some View {
        Button {
            withAnimation { hasCompletedOnboarding = true }
        } label: {
            if prominent {
                Text("Get Started")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.primaryButtonHeight)
                    .background(SavantPalette.savantRed)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                // Borderless free-tier exit: SAME text as the boxed 1.3.0 version
                // (bodyBold, ink), just no box. Keeps it legible/compliant (the
                // free path must stay clearly visible) while the red trial button
                // is the prominent action.
                Text("Get Started")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.primaryButtonHeight)
            }
        }
        .buttonStyle(.plain)
    }

    // One-tap conversion: buy the monthly plan in place, trial when eligible,
    // straight purchase otherwise, never a second paywall. PaywallView is only
    // the emergency fallback when products didn't load. Success flips
    // store.isPro, which finishes onboarding via the onChange handler.
    private func buyMonthly() {
        trialError = nil
        isStartingTrial = true
        Task { @MainActor in
            defer { isStartingTrial = false }
            // The offering can still be in flight (or have failed once) when
            // the button is tapped on a slow or VPN'd network. Load it here
            // rather than dumping the user into the plan picker's error state,
            // which is what made a first purchase attempt look like a failure.
            if store.monthlyPackage == nil {
                await store.ensureProductsLoaded()
            }
            guard let monthly = store.monthlyPackage else {
                trialError = "Still loading subscription options. Tap again in a moment."
                return
            }
            do {
                switch try await store.purchase(monthly) {
                case .purchased:
                    break
                case .pending:
                    // Ask-to-Buy / deferred payment: onboarding stays up because
                    // isPro hasn't flipped, explain instead of appearing dead.
                    trialError = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
                case .cancelled:
                    // Backing out of Apple's sheet is a normal choice, not an
                    // error. Showing red text here is what App Review reads as
                    // "the purchase returned an error message".
                    trialError = nil
                }
            } catch {
                trialError = StoreService.purchaseFailureMessage(for: error)
            }
        }
    }

    // Every page carries four bullets. The count is load-bearing: the bottom
    // button stack is a fixed height and the TabView takes what's left, so a
    // page with a shorter card visibly floats its content on the swipe in.
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "baseball.fill",
            title: "Your Pocket\nScout",
            description: "Baseball percentile rankings built for a fast mobile view. Every qualified player, every metric, always up to date.",
            bullets: [
                BulletItem(text: "Every qualified player ranked", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "xwOBA, Barrel%, Sprint Speed, and more", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Updated daily, always fresh", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "No account, no sign-up", icon: "checkmark.circle.fill", color: SavantPalette.savantRed)
            ]
        ),
        // Four tabs, and the bullets name all four. This page said "three tabs"
        // and listed Stats / Teams / Compare long after Trends shipped, which
        // meant the one screen page three is about was the one screen a new
        // user was never told existed.
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Find Insights\nFast",
            description: "Four tabs cover every angle of the game. See what's happening across the league in seconds.",
            bullets: [
                BulletItem(text: "Stats: sort the league, leaders, best & worst", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Trends: who's heating up and cooling off", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Teams: browse any roster, see who's hot", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Compare: stack two players head-to-head", icon: "checkmark.circle.fill", color: SavantPalette.savantRed)
            ]
        ),
        // The conversion page, so it argues in the same order the TrialPitchSheet
        // does: the Trends board first (the thing that's only useful today, and
        // the reason to start now rather than bookmark it), then form, then the
        // matchups and history. The old copy led with "recent form, every roster
        // player" — a feature list, in the order the features were built.
        OnboardingPage(
            icon: "crown.fill",
            title: "Go Deeper\nwith StatScout+",
            description: "Season numbers tell you who's good. StatScout+ tells you who's good right now, and lets you prove it.",
            bullets: [
                BulletItem(text: "The Trends board: the league ranked by who's moving", icon: "flame.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Last 7 / 15 / 30 day form on any player or team", icon: "chart.bar.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Head-to-head matchups across every percentile", icon: "person.2.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Every season back to 2015, and year-over-year", icon: "calendar.badge.clock", color: SavantPalette.savantRed)
            ]
        )
    ]
}

struct OnboardingCard: View {
    let icon: String
    let title: String
    let description: String
    let bullets: [BulletItem]
    let metrics: OnboardingMetrics

    var body: some View {
        // Every `Text` here is `fixedSize`d vertically. Without that, SwiftUI
        // answers a too-short proposal by truncating each line to one line and
        // clipping the rest, which is how "Go Deeper with StatScout+" became
        // "Go Deeper…" with two of its four bullets missing. Fixed-size text
        // instead reports the height it actually needs, and the ScrollView
        // below absorbs whatever the canvas can't show.
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: metrics.cardSpacing) {
                    ZStack {
                        StatcastBarBackdrop(scale: metrics.heroBackdropScale)
                            .frame(width: metrics.heroBackdrop.width, height: metrics.heroBackdrop.height)
                        ZStack {
                            Circle()
                                .fill(SavantPalette.savantNavy)
                                .frame(width: metrics.heroCircle, height: metrics.heroCircle)
                            Image(systemName: icon)
                                .font(.system(size: metrics.heroIcon, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: SavantPalette.savantNavy.opacity(0.25), radius: 12, y: 4)
                    }

                    Text(title)
                        .font(metrics.titleFont)
                        .foregroundStyle(SavantPalette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(description)
                        .font(SavantType.body)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, metrics.copyInset)

                    VStack(alignment: .leading, spacing: metrics.bulletSpacing) {
                        ForEach(bullets) { bullet in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: bullet.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(bullet.color)
                                Text(bullet.text)
                                    .font(SavantType.body)
                                    .foregroundStyle(SavantPalette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, metrics.bulletInset)
                    .padding(.top, 4)
                }
                .padding(.top, metrics.cardSpacing)
                // The paging dots are drawn over the bottom of this page, not
                // below it, so the last bullet needs to clear them.
                .padding(.bottom, metrics.pageIndicatorInset)
                .frame(maxWidth: .infinity)
                // Centres the card when it fits, scrolls it when it doesn't,
                // in the space above the dots rather than behind them.
                .frame(minHeight: max(0, geo.size.height - metrics.pageIndicatorInset), alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let bullets: [BulletItem]
}

private struct StatcastBarBackdrop: View {
    /// Bars are drawn at their percentile height, so the motif has to be scaled
    /// as a whole when the hero shrinks. Left at 1.0 the tallest bar is 101pt,
    /// which overruns a compact hero frame and collides with the title.
    var scale: CGFloat = 1

    private let percentiles: [Int] = [92, 78, 65, 48, 32, 88, 71, 55, 42, 80]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6 * scale) {
            ForEach(Array(percentiles.enumerated()), id: \.offset) { _, pct in
                RoundedRectangle(cornerRadius: 3)
                    .fill(SavantPalette.color(forPercentile: pct).opacity(0.55))
                    .frame(width: 14 * scale, height: CGFloat(pct) * 1.1 * scale)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

struct ConfigMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(SavantPalette.savantRed)
            Text("StatScout can't load")
                .font(SavantType.playerName)
                .foregroundStyle(SavantPalette.ink)
            Text("This build is missing its data-feed configuration. Please install the latest TestFlight build or contact support.")
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
            if let supportURL = URL(string: "https://jackwallner.github.io/baseball/support.html") {
                Link("Contact Support", destination: supportURL)
                    .buttonStyle(.borderedProminent)
                    .tint(SavantPalette.savantRed)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SavantPalette.canvas.ignoresSafeArea())
    }
}
