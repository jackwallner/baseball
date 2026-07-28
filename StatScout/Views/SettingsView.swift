import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    var onRequestReview: (() -> Void)?
    @State private var paywallTrigger: PaywallTrigger?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        // Ordered by what people open Settings to do. Subscription status and
        // Restore first (the reason a paying user is here at all), then the
        // support and privacy links, then the explanatory cards. "What is
        // StatScout" was reading first and pushing Contact Support to the very
        // bottom of a scroll, which is the one place a stuck user shouldn't
        // have to go looking.
        ScrollView {
            VStack(spacing: 12) {
                proStatusCard
                linkCard
                refreshCard
                aboutCard
                versionCard
                disclaimerCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            // Settings was the one scrolling screen with no clearance for the
            // floating tab bar, so its last rows sat under the glass.
            Color.clear.frame(height: 88)
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
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
            SavantSectionBar(title: "STATSCOUT+")
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: store.isPro ? "crown.fill" : "crown")
                        .font(.title2)
                        .foregroundStyle(store.isPro ? Color.yellow : SavantPalette.inkTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isPro ? "StatScout+ Unlocked" : "Free Version")
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        Text(store.isPro ? "All StatScout+ features are active." : "Unlock historical seasons and year-over-year comparisons.")
                            .font(SavantType.small)
                            .foregroundStyle(SavantPalette.inkSecondary)
                    }
                    Spacer()
                    if !store.isPro {
                        // Same words as the toolbar pill: "Try Free" when an
                        // intro offer is live, "Upgrade" otherwise. Settings
                        // used to say "Upgrade" while the toolbar two taps away
                        // said "Try Free" and the board footer said "Unlock
                        // StatScout+", three labels for one destination.
                        Button(store.isLapsed ? "Renew" : store.upgradeCTALabel) {
                            paywallTrigger = store.defaultUpgradeTrigger
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SavantPalette.savantRed)
                        .controlSize(.small)
                    }
                }
                .padding(SavantGeo.padCard)

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

                if let error = store.lastError {
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

    /// Timestamp of the last successful pipeline run, in the reader's own zone
    /// and saying so.
    ///
    /// This used to print a bare "9:39 AM", which is a time in no particular
    /// place, someone in Denver reading a stamp their phone had already
    /// converted had no way to tell whether the data was three hours old or
    /// five. The zone is the whole point of a freshness line, and the relative
    /// gloss answers the question the stamp is standing in for.
    private var lastUpdatedText: String {
        guard let lastUpdated else { return "-" }
        let stamp = lastUpdated.formatted(
            .dateTime
                .month(.abbreviated).day()
                .hour().minute()
                .timeZone(.specificName(.short))
        )
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "\(stamp) (\(relative.localizedString(for: lastUpdated, relativeTo: .now)))"
    }

    private var refreshCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "DATA")
            row(
                icon: "moon.stars.fill",
                title: "Overnight Refresh",
                subtitle: "Rebuilt overnight from publicly available pitch-tracking data, once the previous night's games have published."
            )
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
            row(
                icon: "clock.arrow.circlepath",
                title: "Last Updated",
                subtitle: lastUpdatedText
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
            Button {
                if let onRequestReview {
                    onRequestReview()
                } else {
                    ReviewPromptCoordinator.shared.requestEnjoymentPrompt()
                }
            } label: {
                row(
                    icon: "star.fill",
                    title: "Rate or Send Feedback",
                    subtitle: "Help StatScout grow, or tell us what to improve."
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)

            // Always-works fallback: the native rating sheet is rate-limited and
            // may show nothing, so keep a direct write-review link for users who
            // explicitly want to leave a review.
            Link(destination: AppStoreReviewLinks.writeReviewURL) {
                row(
                    icon: "square.and.pencil",
                    title: "Rate on the App Store",
                    subtitle: "Opens the App Store to write a review."
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)

            if let supportURL = URL(string: "https://jackwallner.github.io/baseball/support.html") {
                Link(destination: supportURL) {
                    row(
                        icon: "envelope.fill",
                        title: "Contact Support",
                        subtitle: "jackwallner+bb@gmail.com"
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
                        subtitle: "No ads or tracking."
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
        AboutView(lastUpdated: Date())
            .environmentObject(StoreService.shared)
    }
}
