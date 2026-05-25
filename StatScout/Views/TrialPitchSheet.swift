import SwiftUI

/// Native, Apple-Health-"Vitals"-style trial pitch. A focused, friendly
/// pre-paywall: hero glyph, headline, feature bullets, one prominent CTA,
/// and the trial fine print. The CTA hands off to the native `PaywallView`
/// for the actual transaction.
struct TrialPitchSheet: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger
    @State private var showingPaywall = false

    private struct Benefit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    // Bullets are context-aware. For `.playerScouting` (the player-page
    // first-tap pitch) we lead with current-season value — Recent Form,
    // head-to-head, full-roster scouting. Triggers that explicitly opened a
    // history feature still get the time-shaped pitch.
    private var benefits: [Benefit] {
        switch trigger {
        case .playerScouting, .recentForm, .upgrade, .onboarding, .activation:
            return [
                Benefit(icon: "flame.fill",
                        title: "Recent form",
                        detail: "Last 7 / 15 / 30 day splits — spot hot streaks and slumps before anyone else."),
                Benefit(icon: "person.2.fill",
                        title: "Head-to-head matchups",
                        detail: "Pit any two players side by side — every Statcast metric, this season."),
                Benefit(icon: "shield.lefthalf.filled",
                        title: "Full team scouting",
                        detail: "Every player on every roster, not just qualified starters.")
            ]
        case .pastSeason, .pastSeasonsLoad, .yearCompare:
            return [
                Benefit(icon: "calendar.badge.clock",
                        title: "Every past season",
                        detail: "Back to 2020 — see how the numbers held up year by year."),
                Benefit(icon: "arrow.left.arrow.right.circle.fill",
                        title: "Year-over-year trends",
                        detail: "Compare a player's percentile rankings across any two seasons."),
                Benefit(icon: "person.2.fill",
                        title: "Head-to-head matchups",
                        detail: "Stack any two players across every Statcast metric.")
            ]
        case .playerComparison, .teamView, .winback:
            return [
                Benefit(icon: "person.2.fill",
                        title: "Head-to-head matchups",
                        detail: "Stack any two players across every Statcast metric."),
                Benefit(icon: "shield.lefthalf.filled",
                        title: "Full team scouting",
                        detail: "See every player on every roster, not just qualified starters."),
                Benefit(icon: "arrow.left.arrow.right.circle.fill",
                        title: "Year-over-year trends",
                        detail: "Compare any two seasons when you want the longer arc.")
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    benefitList
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
        // Tick the session cap on the *pitch* sheet too, not just the full
        // PaywallView. Otherwise PaywallGate.shouldPresent(.playerScouting)
        // stays true forever for sheets that never reach PaywallView, and the
        // half-sheet would auto-present on every player open.
        .onAppear { PaywallGate.shared.markPresented(trigger) }
        .task {
            store.trackPaywallImpression(id: "statscout_trial_sheet")
            if store.currentOffering == nil { await store.fetchProducts() }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(trigger: trigger)
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SavantPalette.savantRed.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: trigger.icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(SavantPalette.savantRed)
            }

            Text(trigger.title)
                .font(SavantType.statLarge)
                .foregroundStyle(SavantPalette.ink)
                .multilineTextAlignment(.center)

            Text(trigger.subtitle)
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefitList: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                HStack(spacing: 14) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SavantPalette.savantRed)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        Text(benefit.detail)
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)

                if index < benefits.count - 1 {
                    Rectangle()
                        .fill(SavantPalette.divider)
                        .frame(height: SavantGeo.hairline)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                showingPaywall = true
            } label: {
                Text(store.paywallBlurCTA)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(SavantPalette.savantRed)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let subtext = store.paywallBlurSubtext {
                Text(subtext)
                    .font(SavantType.micro)
                    .tracking(0.3)
                    .foregroundStyle(SavantPalette.inkTertiary)
                    .multilineTextAlignment(.center)
            }

            Button("Maybe later") { dismiss() }
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            SavantPalette.surface
                .overlay(
                    Rectangle()
                        .fill(SavantPalette.divider)
                        .frame(height: SavantGeo.hairline),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

#if DEBUG
#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            TrialPitchSheet(trigger: .upgrade)
                .environmentObject(StoreService.shared)
        }
}
#endif
