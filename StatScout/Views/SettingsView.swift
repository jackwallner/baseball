import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    var dataThrough: Date?
    /// Newest playoff game held, once the postseason is under way. The
    /// regular-season line stops moving in late September, and on its own it
    /// told an October user the data was two weeks stale.
    var postseasonThrough: Date?
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
        // StatScout" was reading first and pushing the support rows to the very
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
            SavantSectionBar(title: String(localized: "STATSCOUT"))
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
            SavantSectionBar(title: String(localized: "STATSCOUT+"))
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: store.isPro ? "crown.fill" : "crown")
                        .font(.title2)
                        .foregroundStyle(store.isPro ? Color.yellow : SavantPalette.inkTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isPro ? String(localized: "StatScout+ Unlocked") : String(localized: "Free Version"))
                            .font(SavantType.bodyBold)
                            .foregroundStyle(SavantPalette.ink)
                        Text(store.isPro ? String(localized: "All StatScout+ features are active.") : String(localized: "Unlock historical seasons and year-over-year comparisons."))
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
                        Button(store.isLapsed ? String(localized: "Renew") : store.upgradeCTALabel) {
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

    /// The last game day the numbers cover.
    ///
    /// The row that "Last Updated" needs standing next to it. A refresh that
    /// runs before the previous night's slate has published rewrites every row
    /// without closing out a new day, so the write stamp says today while the
    /// Trends board says "Through Jul 27" — and the app looked like it was
    /// contradicting itself. Saying which games are in makes the pair readable.
    private var gamesThroughText: String {
        guard let dataThrough else { return "-" }
        // Once the playoffs have games in, the regular season is finished and
        // its last day is a final, not an age.
        if postseasonThrough != nil {
            let date = dataThrough.formatted(.dateTime.month(.abbreviated).day())
            return String(localized: "\(date) (regular season final)")
        }
        return Self.coverageText(dataThrough)
    }

    static func coverageText(_ date: Date) -> String {
        let stamp = date.formatted(.dateTime.month(.abbreviated).day())
        let calendar = Calendar.current
        // Only reachable if a day got ingested while it was still being played,
        // which the pipeline is built not to do. Saying so beats a bare "today",
        // which would read as a complete day.
        if calendar.isDateInToday(date) { return String(localized: "\(stamp) (today, still in progress)") }
        if calendar.isDateInYesterday(date) { return String(localized: "\(stamp) (yesterday)") }
        let days = calendar.dateComponents([.day], from: date, to: .now).day ?? 0
        return String(localized: "\(stamp) (\(days) days ago)")
    }

    private var refreshCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: String(localized: "DATA"))
            row(
                icon: "moon.stars.fill",
                title: String(localized: "Overnight Refresh"),
                subtitle: String(localized: "Rebuilt overnight from publicly available pitch-tracking data, once the previous night's games have published.")
            )
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
            row(
                icon: "calendar.badge.clock",
                title: String(localized: "Games Through"),
                subtitle: gamesThroughText
            )
            if let postseasonThrough {
                Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
                row(
                    icon: "trophy",
                    title: String(localized: "Postseason Through"),
                    subtitle: Self.coverageText(postseasonThrough)
                )
            }
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
            row(
                icon: "clock.arrow.circlepath",
                title: String(localized: "Last Refreshed"),
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
            SavantSectionBar(title: String(localized: "SUPPORT & PRIVACY"))
            // Two separate rows with no rating question in front of either
            // (App Review 5.6.1). The rate row deep-links to the review page;
            // requestReview() from a button may show nothing.
            Button {
                ReviewPromptTracker.markOpenedWriteReview()
                UIApplication.shared.open(AppStoreReviewLinks.writeReviewURL)
            } label: {
                row(
                    icon: "star.fill",
                    title: String(localized: "Rate StatScout"),
                    subtitle: String(localized: "Opens the App Store to write a review.")
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)

            Button {
                ReviewPromptTracker.markFeedbackSent()
                UIApplication.shared.open(AppStoreReviewLinks.feedbackMailURL)
            } label: {
                row(
                    icon: "envelope.fill",
                    title: String(localized: "Send Feedback"),
                    subtitle: AppStoreReviewLinks.feedbackEmail
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)

            if let privacyURL = URL(string: "https://jackwallner.com/ios/baseball/privacy-policy.html") {
                Link(destination: privacyURL) {
                    row(
                        icon: "shield.lefthalf.filled",
                        title: String(localized: "Privacy Policy"),
                        subtitle: String(localized: "No ads or tracking.")
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
            SavantSectionBar(title: String(localized: "VERSION"))
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
            SavantSectionBar(title: String(localized: "DISCLAIMER"))
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
        AboutView(
            lastUpdated: Date(),
            dataThrough: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
            .environmentObject(StoreService.shared)
    }
}
