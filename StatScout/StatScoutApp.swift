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

struct OnboardingCards: View {
    @EnvironmentObject private var store: StoreService
    let viewModel: DashboardViewModel
    @Binding var showingPaywall: Bool
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private var isLastPage: Bool { currentPage == pages.count - 1 }
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

                primaryButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isLastPage {
            Button {
                withAnimation { hasCompletedOnboarding = true }
            } label: {
                HStack(spacing: 10) {
                    if !dataReady {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                        Text("Loading 2024–2026 data…")
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
            title: "Baseball Savant,\nin Your Pocket",
            description: "MLB's percentile rankings — without the desktop view.",
            bullets: [
                "Every qualified player ranked",
                "xwOBA, Barrel%, Sprint Speed, and more",
                "Updated daily"
            ]
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Find Signals Fast",
            description: "Four tabs cover every angle.",
            bullets: [
                "Leaders — sort the league by any metric",
                "Teams — see who's hot, who's not",
                "Metrics — best & worst at each stat",
                "Stats — traditional numbers for the curious"
            ]
        ),
        OnboardingPage(
            icon: "crown.fill",
            title: "Free covers 2026.\nPro unlocks the rest.",
            description: "History, comparisons, and the deep cuts.",
            bullets: [
                "Past seasons (2024, 2025…)",
                "Year-over-year player comparisons",
                "Full metric rankings & team breakdowns"
            ]
        )
    ]
}

struct OnboardingCard: View {
    let icon: String
    let title: String
    let description: String
    let bullets: [String]

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(SavantPalette.savantRed.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(SavantPalette.savantRed)
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
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SavantPalette.savantRed)
                        Text(bullet)
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
    let bullets: [String]
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
