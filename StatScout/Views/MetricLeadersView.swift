import SwiftUI

struct MetricLeadersView: View {
    let metrics: [(label: String, category: MetricCategory, best: (player: Player, value: Int)?, worst: (player: Player, value: Int)?)]
    @Binding var selectedPlayer: Player?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Metric Leaders")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Text("Best and worst performer for every tracked Statcast metric.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        ForEach(metrics, id: \.label) { metric in
                            MetricLeaderRow(
                                label: metric.label,
                                category: metric.category,
                                bestPlayer: metric.best?.player,
                                bestValue: metric.best?.value,
                                worstPlayer: metric.worst?.player,
                                worstValue: metric.worst?.value,
                                onSelect: { selectedPlayer = $0 }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(StatScoutTheme.background.ignoresSafeArea())
            .navigationTitle("Leaders")
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
    MetricLeadersView(
        metrics: [],
        selectedPlayer: .constant(nil)
    )
}
