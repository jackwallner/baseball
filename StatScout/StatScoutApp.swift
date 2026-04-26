import SwiftUI

@main
struct StatScoutApp: App {
    private let api = StatcastAPI(
        baseURL: URL(string: "https://babzqsbmcunrezsdpyng.supabase.co")!,
        apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJhYnpxc2JtY3VucmV6c2RweW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQ5NjIsImV4cCI6MjA5MjgxMDk2Mn0.6OLIj-KnMcWhvjjSzSM3NF_d8AyToi4HSgPJ2oMIHG4"
    )

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: DashboardViewModel(provider: api))
        }
    }
}
