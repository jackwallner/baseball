import SwiftUI
import RevenueCat

@main
struct StatScoutApp: App {
    private let api: StatcastAPI?
    @StateObject private var store = StoreService.shared

    init() {
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
        }
    }
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService

    @State private var viewModel: DashboardViewModel

    init(api: StatcastAPI) {
        _viewModel = State(initialValue: DashboardViewModel(provider: api, cache: TwoTierPlayerCache()))
    }

    var body: some View {
        ZStack {
            RootTabView(viewModel: viewModel)
                .disabled(!hasCompletedOnboarding)
                .allowsHitTesting(hasCompletedOnboarding)

            if !hasCompletedOnboarding {
                OnboardingCards(viewModel: viewModel, hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .onAppear { viewModel.applyProState(store.isPro) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.load() }
        }
        .onChange(of: store.isPro) { _, isPro in
            viewModel.applyProState(isPro)
        }
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

    private var isLastPage: Bool { currentPage == pages.count - 1 }
    private var dataReady: Bool { viewModel.isReady }

    private var yearlyPackage: Package? {
        store.products.first(where: { $0.productKind == .yearly })
    }

    private var hasYearlyTrial: Bool {
        yearlyPackage?.introOfferLabel != nil
    }

    private var proCTALabel: String {
        hasYearlyTrial ? "Start Free Trial" : "Upgrade to Pro"
    }

    private var trialDisclosure: String? {
        guard let yearly = yearlyPackage, let trial = yearly.introOfferLabel else {
            return nil
        }
        return "\(trial), then \(yearly.priceLabel). Auto-renews until cancelled in Settings › Apple ID › Subscriptions. Cancel at least 24 hours before the trial ends to avoid being charged."
    }

    var body: some View {
        ZStack {
            SavantPalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLastPage {
                        Button("Skip") {
                            withAnimation { hasCompletedOnboarding = true }
                        }
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.savantRed)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }

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
        if isLastPage {
            VStack(spacing: 10) {
                // Primary action is always entering the app — never blocked on
                // data load or a purchase, so a user can't get trapped here.
                Button {
                    withAnimation { hasCompletedOnboarding = true }
                } label: {
                    Text("Get Started")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SavantPalette.savantRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                if !dataReady {
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
                    .frame(height: 20)
                }

                // No Pro pitch here — the ask is deliberately deferred to a
                // one-time full-screen paywall on the user's first meaningful
                // action (opening a player), after they've felt the value.
                // Restore stays so a reinstalling subscriber isn't funneled
                // through a paywall just to get their purchase back.
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Text("Restore Purchases")
                        .font(SavantType.micro)
                        .tracking(0.4)
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
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
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "baseball.fill",
            title: "Your Pocket\nScout",
            description: "Baseball percentile rankings built for a fast mobile view. Every qualified player, every metric, always up to date.",
            bullets: [
                BulletItem(text: "Every qualified player ranked", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "xwOBA, Barrel%, Sprint Speed, and more", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Updated daily — fresh data, always", icon: "checkmark.circle.fill", color: SavantPalette.savantRed)
            ]
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Find Insights\nFast",
            description: "Three tabs cover every angle of the game. See what's happening across the league in seconds.",
            bullets: [
                BulletItem(text: "Stats — sort the league, leaders, best & worst", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Teams — browse any roster, see who's hot", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Compare — stack two players head-to-head", icon: "checkmark.circle.fill", color: SavantPalette.savantRed)
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
