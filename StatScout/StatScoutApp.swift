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

            VStack(spacing: 0) {
                // Fixed-height header: Skip fades out on the last page rather
                // than being removed, so the TabView below it never changes
                // height and the card content never shifts mid-swipe.
                HStack {
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
                .frame(height: 32)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingCard(
                            icon: page.icon,
                            title: page.title,
                            description: page.description,
                            bullets: page.bullets
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
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
    private var bottomButtons: some View {
        // Layout invariant: this whole stack is the SAME HEIGHT on every page.
        // Every slot is either fixed (the 52pt red button, the 32pt status line,
        // the 24pt footer) or always present and merely faded (the upsell block).
        // Nothing is conditionally inserted or removed. That keeps two things
        // true at once: the red button is pixel-identical across pages, and the
        // TabView above never resizes, so card content can't drift on a swipe.
        VStack(spacing: 10) {
            // --- Above the primary button ---
            // Always in the layout, faded out where it doesn't apply. It used to
            // be inserted only on the last page, which grew this bottom-anchored
            // stack by ~130pt on arrival: the TabView above absorbed the change,
            // so the card's icon, title and bullets visibly floated up as the
            // StatScout+ page came in. Reserving the space on every page keeps
            // the TabView one constant height and kills the float.
            VStack(spacing: 10) {
                getStartedButton(prominent: false)

                // Reserved fixed-height status line: a restore/purchase result
                // fills this slot in place instead of being inserted, so nothing
                // above the button shifts either.
                Text(trialError ?? " ")
                    .font(SavantType.micro)
                    .foregroundStyle(SavantPalette.savantRed)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32, alignment: .top)

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
            .opacity(showsUpsellBlock ? 1 : 0)
            .allowsHitTesting(showsUpsellBlock)
            .accessibilityHidden(!showsUpsellBlock)

            // --- Primary red button: identical 52pt slot on every page ---
            if isLastPage {
                if store.isPro {
                    getStartedButton(prominent: true)
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
                        .frame(height: 52)
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
                        .frame(height: 52)
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
            .frame(height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    /// "Get Started" dismisses onboarding into the free tier. `prominent` is the
    /// solo state (Pro users, where it's the only, and primary, action, a
    /// filled button); otherwise it's a de-emphasized, borderless text link that
    /// sits above the red trial CTA so it never competes for the tap.
    private func getStartedButton(prominent: Bool) -> some View {
        Button {
            withAnimation { hasCompletedOnboarding = true }
        } label: {
            if prominent {
                Text("Get Started")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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
                    .frame(height: 52)
            }
        }
        .buttonStyle(.plain)
    }

    // One-tap conversion: buy the monthly plan in place, trial when eligible,
    // straight purchase otherwise, never a second paywall. PaywallView is only
    // the emergency fallback when products didn't load. Success flips
    // store.isPro, which finishes onboarding via the onChange handler.
    private func buyMonthly() {
        guard let monthly = store.monthlyPackage else {
            paywallTrigger = .onboarding
            return
        }
        trialError = nil
        isStartingTrial = true
        Task { @MainActor in
            defer { isStartingTrial = false }
            do {
                switch try await store.purchase(monthly) {
                case .purchased:
                    break
                case .pending:
                    // Ask-to-Buy / deferred payment: onboarding stays up because
                    // isPro hasn't flipped, explain instead of appearing dead.
                    trialError = "Purchase pending approval. StatScout+ unlocks automatically once it's approved."
                case .cancelled:
                    trialError = "Purchase cancelled. Tap again to continue."
                }
            } catch {
                trialError = store.lastError ?? "Couldn't complete the purchase. Please try again."
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

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            ZStack {
                StatcastBarBackdrop()
                    .frame(width: 220, height: 120)
                ZStack {
                    Circle()
                        .fill(SavantPalette.savantNavy)
                        .frame(width: 96, height: 96)
                    Image(systemName: icon)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: SavantPalette.savantNavy.opacity(0.25), radius: 12, y: 4)
            }

            Text(title)
                .font(SavantType.playerName)
                .foregroundStyle(SavantPalette.ink)
                .multilineTextAlignment(.center)

            Text(description)
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(bullets) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: bullet.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(bullet.color)
                        Text(bullet.text)
                            .font(SavantType.body)
                            .foregroundStyle(SavantPalette.ink)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 4)

            Spacer()
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
    private let percentiles: [Int] = [92, 78, 65, 48, 32, 88, 71, 55, 42, 80]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(percentiles.enumerated()), id: \.offset) { _, pct in
                RoundedRectangle(cornerRadius: 3)
                    .fill(SavantPalette.color(forPercentile: pct).opacity(0.55))
                    .frame(width: 14, height: CGFloat(pct) * 1.1)
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
