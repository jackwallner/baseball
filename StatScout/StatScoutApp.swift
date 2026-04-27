import SwiftUI

@main
struct StatScoutApp: App {
    private let api: StatcastAPI

    init() {
        guard let urlString = Self.configValue(for: "SUPABASE_URL"),
              let url = URL(string: urlString),
              let key = Self.configValue(for: "SUPABASE_ANON_KEY") else {
            fatalError("Missing Supabase configuration. Set SUPABASE_URL and SUPABASE_ANON_KEY in the scheme environment or Info.plist build settings.")
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
            RootTabView(viewModel: DashboardViewModel(provider: api))
                .preferredColorScheme(.light)
        }
    }
}
