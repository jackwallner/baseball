import SwiftUI

struct SettingsView: View {
    let lastUpdated: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StatScoutTheme.background.ignoresSafeArea()
                List {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "moon.stars.fill")
                                .font(.title2)
                                .foregroundStyle(StatScoutTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nightly Refresh")
                                    .font(.headline.weight(.bold))
                                Text("Data is refreshed nightly via GitHub Actions using Baseball Savant / Statcast feeds.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.white.opacity(0.05))

                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(StatScoutTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last Updated")
                                    .font(.headline.weight(.bold))
                                Text(lastUpdated.formatted(date: .long, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.white.opacity(0.05))
                    }

                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "baseball.fill")
                                .font(.title2)
                                .foregroundStyle(StatScoutTheme.savantRed)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("StatScout")
                                    .font(.headline.weight(.bold))
                                Text("Baseball Savant-style percentiles and leaderboards for fans and media.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .tint(.white)
    }
}

#Preview {
    SettingsView(lastUpdated: Date())
}
