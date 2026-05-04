import SwiftUI

@main
struct StatScoutApp: App {
    private let api: StatcastAPI?

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
                RootTabView(viewModel: DashboardViewModel(provider: api, cache: DiskPlayerCache()))
                    .preferredColorScheme(.dark)
            } else {
                ConfigMissingView()
                    .preferredColorScheme(.dark)
            }
        }
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
            Link("Contact Support", destination: URL(string: "https://jackwallner.github.io/baseball/support.html")!)
                .buttonStyle(.borderedProminent)
                .tint(SavantPalette.savantRed)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SavantPalette.canvas.ignoresSafeArea())
    }
}
