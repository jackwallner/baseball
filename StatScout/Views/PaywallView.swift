import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreManager

    @State private var isPurchasing = false
    @State private var selectedTier: ProTier = .yearly
    @State private var purchaseSucceeded = false

    var body: some View {
        ZStack {
            SavantPalette.canvas.ignoresSafeArea()

            if purchaseSucceeded {
                successSection
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                        featureList
                        purchaseSection
                        footerSection
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }

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

            Text("Go deeper when you need the full read on a player. Core browsing stays free.")
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
                    title: "Full Percentile Breakdowns",
                    subtitle: "Move beyond the preview and see every tracked metric for each player."
                )
                DividerRow()
                FeatureRow(
                    icon: "arrow.left.arrow.right",
                    title: "Year-over-Year Compare",
                    subtitle: "Compare seasons side by side to spot changes, trends, and breakouts."
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
            VStack(spacing: 10) {
                TierOptionRow(
                    title: "Yearly",
                    badge: "Best Value",
                    price: priceText(for: .yearly),
                    cadence: "per year",
                    isSelected: selectedTier == .yearly
                ) { selectedTier = .yearly }

                TierOptionRow(
                    title: "Monthly",
                    badge: nil,
                    price: priceText(for: .monthly),
                    cadence: "per month",
                    isSelected: selectedTier == .monthly
                ) { selectedTier = .monthly }

                TierOptionRow(
                    title: "Lifetime",
                    badge: "One-Time",
                    price: priceText(for: .lifetime),
                    cadence: "forever",
                    isSelected: selectedTier == .lifetime
                ) { selectedTier = .lifetime }
            }
            .padding(.horizontal, 12)

            Button {
                isPurchasing = true
                Task {
                    await store.purchase(tier: selectedTier)
                    isPurchasing = false
                    if store.proStatus == .purchased {
                        purchaseSucceeded = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isPurchasing ? "Processing..." : "Continue — \(priceText(for: selectedTier))")
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
            .padding(.top, 4)

            Button {
                Task {
                    await store.restorePurchases()
                    if store.proStatus == .purchased {
                        purchaseSucceeded = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
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

    private var successSection: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(SavantPalette.savantRed)
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Pro Unlocked")
                .font(SavantType.playerName)
                .foregroundStyle(SavantPalette.ink)
            Text("Full metric breakdowns and year-over-year comparisons are ready.")
                .font(SavantType.body)
                .foregroundStyle(SavantPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Start using Pro") {
                dismiss()
            }
            .font(SavantType.bodyBold)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(SavantPalette.savantRed)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            Spacer()
        }
        .padding(.vertical, 32)
    }

    private func priceText(for tier: ProTier) -> String {
        if let product = store.product(for: tier) {
            return product.displayPrice
        }
        switch tier {
        case .monthly: return "$1.99"
        case .yearly: return "$14.99"
        case .lifetime: return store.proPrice
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Subscriptions auto-renew until cancelled. Manage in Settings.")
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

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

private struct TierOptionRow: View {
    let title: String
    let badge: String?
    let price: String
    let cadence: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? SavantPalette.savantRed : SavantPalette.inkTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        if let badge {
                            Text(badge)
                                .font(SavantType.micro)
                                .tracking(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SavantPalette.savantRed)
                                .clipShape(Capsule())
                        }
                    }
                    Text(cadence)
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                Spacer()
                Text(price)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(SavantPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? SavantPalette.savantRed : SavantPalette.hairline, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView(store: StoreManager())
}
