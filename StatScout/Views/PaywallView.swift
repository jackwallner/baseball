import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreManager

    @State private var isPurchasing = false

    var body: some View {
        ZStack {
            SavantPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    featureList
                    purchaseSection
                    footerSection
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(SavantPalette.inkTertiary)
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 48)

            ZStack {
                Circle()
                    .fill(SavantPalette.savantNavy)
                    .frame(width: 88, height: 88)
                Image(systemName: "baseball.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            Text("StatScout Pro")
                .font(SavantType.playerName)
                .foregroundStyle(SavantPalette.ink)

            Text("Unlock the full power of advanced MLB analytics. One purchase. Lifetime access.")
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "PRO FEATURES")

            VStack(spacing: 0) {
                FeatureRow(
                    icon: "chart.bar.fill",
                    title: "Full Metric Access",
                    subtitle: "Every advanced metric for every player — xwOBA, Barrel%, Sprint Speed, OAA, and more."
                )
                DividerRow()
                FeatureRow(
                    icon: "shield.lefthalf.filled",
                    title: "Team Rosters & Rankings",
                    subtitle: "Browse all 30 MLB team rosters with full percentile breakdowns per player."
                )
                DividerRow()
                FeatureRow(
                    icon: "arrow.left.arrow.right",
                    title: "Year-over-Year Compare",
                    subtitle: "See how players trend across seasons with historical percentile data."
                )
                DividerRow()
                FeatureRow(
                    icon: "person.2.fill",
                    title: "Metric Leaderboards",
                    subtitle: "Discover who leads the league in every tracked metric across all categories."
                )
                DividerRow()
                FeatureRow(
                    icon: "square.and.arrow.up",
                    title: "Share Player Cards",
                    subtitle: "Send player stat summaries to friends, group chats, or social media."
                )
                DividerRow()
                FeatureRow(
                    icon: "photo.fill",
                    title: "Player Headshots",
                    subtitle: "Official MLB headshots on every card, row, and profile."
                )
            }
            .background(SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                    .stroke(SavantPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Button {
                isPurchasing = true
                Task {
                    await store.purchase()
                    isPurchasing = false
                    if store.proStatus == .purchased {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isPurchasing ? "Processing..." : "Unlock Pro — \(store.proPrice)")
                        .font(SavantType.bodyBold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SavantPalette.savantRed)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isPurchasing)
            .padding(.horizontal, 12)

            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(SavantType.smallBold)
                    .foregroundStyle(SavantPalette.linkBlue)
            }

            if let error = store.purchaseError {
                Text(error)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.savantRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.top, 20)
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("One-time purchase. No subscription. No ads. Ever.")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkTertiary)

            HStack(spacing: 16) {
                if let privacyURL = URL(string: "https://jackwallner.github.io/baseball/privacy-policy.html") {
                    Link("Privacy", destination: privacyURL)
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.linkBlue)
                }
                if let termsURL = URL(string: "https://jackwallner.github.io/baseball/terms.html") {
                    Link("Terms", destination: termsURL)
                        .font(SavantType.micro)
                        .foregroundStyle(SavantPalette.linkBlue)
                }
            }
        }
        .padding(.vertical, 24)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SavantPalette.savantRed)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Text(subtitle)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, SavantGeo.padCard)
        .padding(.vertical, 12)
    }
}

private struct DividerRow: View {
    var body: some View {
        Rectangle()
            .fill(SavantPalette.divider)
            .frame(height: SavantGeo.hairline)
            .padding(.leading, 58)
    }
}

#Preview {
    PaywallView(store: StoreManager())
}
