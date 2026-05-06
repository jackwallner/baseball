import SwiftUI

struct AboutView: View {
    let lastUpdated: Date?
    let store: StoreManager
    @State private var showingPaywall = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                aboutCard
                proStatusCard
                refreshCard
                linkCard
                versionCard
                disclaimerCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store)
        }
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "STATSCOUT")
            HStack(spacing: 12) {
                Image(systemName: "baseball.fill")
                    .font(.title2)
                    .foregroundStyle(SavantPalette.savantRed)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Percentile Rankings")
                        .font(SavantType.cardTitle)
                        .foregroundStyle(SavantPalette.ink)
                    Text("Mobile-first percentile rankings and leaderboards for fans and media.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                Spacer()
            }
            .padding(SavantGeo.padCard)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var proStatusCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "STATSCOUT PRO")
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: store.proStatus == .purchased ? "crown.fill" : "crown")
                        .font(.title2)
                        .foregroundStyle(store.proStatus == .purchased ? Color.yellow : SavantPalette.inkTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.proStatus == .purchased ? "Pro Unlocked" : "Free Version")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        Text(store.proStatus == .purchased ? "Full access to all features." : "Unlock teams, metrics, and more.")
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkSecondary)
                    }
                    Spacer()
                    if store.proStatus != .purchased {
                        Button("Upgrade") {
                            showingPaywall = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SavantPalette.savantRed)
                        .controlSize(.small)
                    }
                }
                .padding(SavantGeo.padCard)

                if store.proStatus == .purchased {
                    Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text("Restore Purchases")
                                .font(SavantType.smallBold)
                        }
                        .foregroundStyle(SavantPalette.linkBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SavantGeo.padCard)
                    }
                    .buttonStyle(.plain)
                }

                if let error = store.purchaseError {
                    Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
                    Text(error)
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.savantRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SavantGeo.padCard)
                }
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var refreshCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "DATA")
            row(
                icon: "moon.stars.fill",
                title: "Nightly Refresh",
                subtitle: "Refreshed each night using publicly available pitch-tracking data."
            )
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
            row(
                icon: "clock.arrow.circlepath",
                title: "Last Updated",
                subtitle: lastUpdated.map { $0.formatted(date: .long, time: .shortened) } ?? "—"
            )
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var linkCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "SUPPORT & PRIVACY")
            if let supportURL = URL(string: "https://jackwallner.github.io/baseball/support.html") {
                Link(destination: supportURL) {
                    row(
                        icon: "envelope.fill",
                        title: "Contact Support",
                        subtitle: "support@statscout.app"
                    )
                }
                .buttonStyle(.plain)
            }
            
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
            
            if let privacyURL = URL(string: "https://jackwallner.github.io/baseball/privacy-policy.html") {
                Link(destination: privacyURL) {
                    row(
                        icon: "shield.lefthalf.filled",
                        title: "Privacy Policy",
                        subtitle: "No data collection. No tracking."
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var versionCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "VERSION")
            HStack {
                Text("App Version")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Spacer()
                Text(version)
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .padding(SavantGeo.padCard)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var disclaimerCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "DISCLAIMER")
            Text("Not affiliated with, endorsed by, or sponsored by Major League Baseball, MLB Advanced Media, MLBPA, or any team. Team names and abbreviations are used for identification only. All trademarks are property of their respective owners.")
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SavantGeo.padCard)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SavantPalette.savantRed)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Text(subtitle)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            Spacer()
        }
        .padding(SavantGeo.padCard)
    }
}

#Preview {
    NavigationStack {
        AboutView(lastUpdated: Date(), store: StoreManager())
    }
}
