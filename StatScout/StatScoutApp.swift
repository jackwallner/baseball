import SwiftUI

@main
struct StatScoutApp: App {
    private let api: StatcastAPI?
    @StateObject private var store = StoreService.shared

    init() {
        // 64 MB memory + 256 MB disk image cache so headshots stick around between launches.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "image-cache")
        )

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
    @State private var showingPaywall = false

    init(api: StatcastAPI) {
        _viewModel = State(initialValue: DashboardViewModel(provider: api, cache: TwoTierPlayerCache()))
    }

    var body: some View {
        ZStack {
            RootTabView(viewModel: viewModel)
                .disabled(!hasCompletedOnboarding)
                .allowsHitTesting(hasCompletedOnboarding)

            if !hasCompletedOnboarding {
                OnboardingCards(viewModel: viewModel, showingPaywall: $showingPaywall, hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
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
    @Binding var showingPaywall: Bool
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private var isLastPage: Bool { currentPage == pages.count - 1 }
    private var isPricingPage: Bool { currentPage == 2 }
    private var dataReady: Bool { viewModel.isReady }

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
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if isLastPage {
            Button {
                withAnimation { hasCompletedOnboarding = true }
            } label: {
                HStack(spacing: 10) {
                    if !dataReady {
                        VStack(spacing: 6) {
                            ProgressView(value: min(max(viewModel.loadingProgress, 0), 1), total: 1)
                                .progressViewStyle(.linear)
                                .tint(.white)
                            Text(viewModel.loadingMessage)
                                .font(SavantType.micro)
                                .tracking(0.4)
                        }
                    } else {
                        Image(systemName: "baseball.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Play Ball")
                    }
                }
                .font(SavantType.bodyBold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(dataReady ? SavantPalette.savantRed : SavantPalette.savantRed.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!dataReady)
        } else if isPricingPage {
            VStack(spacing: 12) {
                Button {
                    showingPaywall = true
                } label: {
                    Text(store.proPrice.map { "Unlock Pro — \($0)" } ?? "See Plans")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SavantPalette.savantRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Maybe Later")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
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
            description: "Four tabs cover every angle of the game. See what's happening across the league in seconds.",
            bullets: [
                BulletItem(text: "Leaders — sort the league by any metric", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Teams — see who's hot, who's not", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Metrics — best & worst at each stat", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Stats — traditional numbers for the curious", icon: "checkmark.circle.fill", color: SavantPalette.savantRed)
            ]
        ),
        OnboardingPage(
            icon: "crown.fill",
            title: "Go Pro",
            description: "Current season is free. Pro unlocks the trends that tell the full story — past seasons, year-over-year changes, and head-to-head comparisons.",
            bullets: [
                BulletItem(text: "Current season leaderboard", icon: "checkmark.circle.fill", color: .green),
                BulletItem(text: "Player profiles & percentiles", icon: "checkmark.circle.fill", color: .green),
                BulletItem(text: "Past seasons on demand", icon: "crown.fill", color: .yellow),
                BulletItem(text: "Year-over-year comparisons", icon: "crown.fill", color: .yellow),
                BulletItem(text: "Head-to-head player matchups", icon: "crown.fill", color: .yellow),
                BulletItem(text: "Full percentile history", icon: "crown.fill", color: .yellow)
            ]
        ),
        OnboardingPage(
            icon: "baseball.fill",
            title: "Play Ball",
            description: "Data is loading so you can jump right into the leaderboard. Your app, your team, your game.",
            bullets: [
                BulletItem(text: "Ready when the data loads", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "No account required to get started", icon: "checkmark.circle.fill", color: SavantPalette.savantRed),
                BulletItem(text: "Upgrade to Pro anytime from Settings", icon: "checkmark.circle.fill", color: SavantPalette.savantRed)
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
