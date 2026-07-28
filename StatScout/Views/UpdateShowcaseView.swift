import SwiftUI

struct UpdateShowcaseDecision: Equatable {
    let shouldPresent: Bool
    let shouldMarkSeen: Bool
}

enum UpdateShowcaseCampaign {
    static let identifier = "stats-trends-compare-1.3.1"
    static let storageKey = "lastSeenUpdateShowcase"

    static func decision(
        hasCompletedOnboarding: Bool,
        seenCampaign: String,
        forcePresentation: Bool = false
    ) -> UpdateShowcaseDecision {
        if forcePresentation {
            return UpdateShowcaseDecision(shouldPresent: true, shouldMarkSeen: false)
        }
        guard seenCampaign != identifier else {
            return UpdateShowcaseDecision(shouldPresent: false, shouldMarkSeen: false)
        }
        guard hasCompletedOnboarding else {
            return UpdateShowcaseDecision(shouldPresent: false, shouldMarkSeen: true)
        }
        return UpdateShowcaseDecision(shouldPresent: true, shouldMarkSeen: false)
    }

    static var isForced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["STATSCOUT_FORCE_UPDATE_SHOWCASE"] == "1"
        #else
        false
        #endif
    }
}

struct UpdateShowcaseView: View {
    @EnvironmentObject private var store: StoreService

    let onFinish: () -> Void

    @State private var page = 0

    private let pageCount = 3

    var body: some View {
        ZStack {
            SavantPalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    showcasePage(
                        eyebrow: "NEW IN STATSCOUT",
                        title: "Who's hot\nright now.",
                        detail: "The new Trends board ranks the biggest movers across the league, not just the names already at the top.",
                        visual: AnyView(TrendShowcaseGraphic())
                    )
                    .tag(0)

                    showcasePage(
                        eyebrow: "COMPARE YOUR WAY",
                        title: "Any two.\nAny season.",
                        detail: "Change either player and either year. See every shared metric side by side, with the winner called out instantly.",
                        visual: AnyView(ComparisonShowcaseGraphic())
                    )
                    .tag(1)

                    showcasePage(
                        eyebrow: "A DEEPER SCOREBOOK",
                        title: "Every club.\nEvery angle.",
                        detail: "Sort advanced and traditional stats across players and teams, from xwOBA and Barrel% to AVG, ERA, and stolen bases.",
                        visual: AnyView(StatsShowcaseGraphic())
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { onFinish() }
        }
        .accessibilityIdentifier("updateShowcase")
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SavantPalette.savantRed)
                Text("STATSCOUT")
                    .font(SavantType.sectionTitle)
                    .tracking(0.9)
                    .foregroundStyle(SavantPalette.ink)
            }

            Spacer()

            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .frame(width: 36, height: 36)
                    .background(SavantPalette.surface, in: Circle())
                    .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
            }
            .accessibilityLabel("Close what's new")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(height: 56)
    }

    private func showcasePage(
        eyebrow: String,
        title: String,
        detail: String,
        visual: AnyView
    ) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(eyebrow)
                    .font(SavantType.micro)
                    .tracking(1.2)
                    .foregroundStyle(SavantPalette.savantRed)

                Text(title)
                    .font(SavantFont.condensed(38, weight: .black))
                    .foregroundStyle(SavantPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)

                Text(detail)
                    .font(SavantType.body)
                    .foregroundStyle(SavantPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            visual
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? SavantPalette.savantRed : SavantPalette.hairline)
                        .frame(width: index == page ? 24 : 7, height: 7)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: page)
            .accessibilityHidden(true)

            if page < pageCount - 1 {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Continue")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SavantPalette.savantRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("updateShowcaseContinue")
            } else if store.isPro {
                Button(action: onFinish) {
                    Text("Start Scouting")
                        .font(SavantType.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SavantPalette.savantRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("updateShowcaseFinish")
            } else {
                VStack(spacing: 7) {
                    Text(store.isLapsed ? "Put the full scouting toolkit back in your lineup." : "Unlock Trends, recent form, comparisons, and every season back to 2015.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .multilineTextAlignment(.center)

                    PlusDirectCTA(trigger: store.defaultUpgradeTrigger)

                    Button("Keep using the free version", action: onFinish)
                        .font(SavantType.smallBold)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .accessibilityIdentifier("updateShowcaseDismiss")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            SavantPalette.surface
                .overlay(Rectangle().fill(SavantPalette.divider).frame(height: 0.5), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct TrendShowcaseGraphic: View {
    private let players = [
        ("1", "KH", "Ke'Bryan Hayes", "+.342", 0.96),
        ("2", "RW", "Ryan Waldschmidt", "+.281", 0.82),
        ("3", "AC", "Andrés Chaparro", "+.273", 0.72),
        ("4", "AW", "Austin Wells", "+.265", 0.62)
    ]

    var body: some View {
        ShowcaseCard(title: "HOTTEST IN THE LEAGUE", trailing: "15 DAYS") {
            VStack(spacing: 0) {
                ForEach(Array(players.enumerated()), id: \.offset) { index, player in
                    HStack(spacing: 10) {
                        Text(player.0)
                            .font(SavantType.statSmall)
                            .foregroundStyle(SavantPalette.inkSecondary)
                            .frame(width: 14)
                        Circle()
                            .fill(SavantPalette.color(forPercentile: 88 - index * 7))
                            .frame(width: 34, height: 34)
                            .overlay(Text(player.1).font(SavantType.micro).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.2)
                                .font(SavantType.bodyBold)
                                .foregroundStyle(SavantPalette.ink)
                                .lineLimit(1)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(SavantPalette.savantRed.opacity(0.82))
                                    .frame(width: proxy.size.width * player.4, height: 4)
                            }
                            .frame(height: 4)
                        }
                        Spacer(minLength: 4)
                        Text(player.3)
                            .font(SavantType.statMed)
                            .foregroundStyle(SavantPalette.savantRed)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    if index < players.count - 1 {
                        Rectangle().fill(SavantPalette.divider).frame(height: 0.5)
                    }
                }
            }
        }
    }
}

private struct ComparisonShowcaseGraphic: View {
    private let metrics = [
        ("xwOBA", "0.415", "0.405", true),
        ("xSLG", "0.600", "0.563", true),
        ("Whiff%", "30.8%", "27.4%", false),
        ("Barrel%", "21.7%", "16.4%", true)
    ]

    var body: some View {
        ShowcaseCard(title: "PLAYER COMPARISON", trailing: "2026") {
            VStack(spacing: 0) {
                HStack {
                    playerBadge(initials: "AJ", name: "Aaron Judge", team: "NYY")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SavantPalette.inkTertiary)
                        .frame(width: 36, height: 36)
                        .background(SavantPalette.surfaceAlt, in: Circle())
                    playerBadge(initials: "SO", name: "Shohei Ohtani", team: "LAD")
                }
                .padding(14)

                Rectangle().fill(SavantPalette.divider).frame(height: 0.5)

                ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                    HStack {
                        Text(metric.0)
                            .font(SavantType.smallBold)
                            .foregroundStyle(SavantPalette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        comparisonValue(metric.1, wins: metric.3)
                        comparisonValue(metric.2, wins: !metric.3)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(index.isMultiple(of: 2) ? SavantPalette.surface : SavantPalette.surfaceAlt)
                }
            }
        }
    }

    private func playerBadge(initials: String, name: String, team: String) -> some View {
        VStack(spacing: 5) {
            Circle()
                .fill(SavantPalette.savantNavy)
                .frame(width: 48, height: 48)
                .overlay(Text(initials).font(SavantType.statMed).foregroundStyle(.white))
            Text(name)
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
                .lineLimit(1)
            Text(team)
                .font(SavantType.micro)
                .foregroundStyle(SavantPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonValue(_ value: String, wins: Bool) -> some View {
        HStack(spacing: 4) {
            if wins {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Text(value)
                .font(SavantType.statMed)
                .foregroundStyle(wins ? SavantPalette.savantRed : SavantPalette.inkSecondary)
        }
        .frame(width: 88)
    }
}

private struct StatsShowcaseGraphic: View {
    private let stats = [
        ("xwOBA", "Yordan Alvarez", "0.473"),
        ("HR", "Cal Raleigh", "41"),
        ("SB", "Nasim Nuñez", "37"),
        ("DRS", "Pete Crow-Armstrong", "18")
    ]

    var body: some View {
        ShowcaseCard(title: "EVERY WAY TO RANK", trailing: "30 CLUBS") {
            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    filterPill("Advanced", selected: true)
                    filterPill("Standard", selected: false)
                    filterPill("Teams", selected: false)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(SavantType.statSmall)
                                .foregroundStyle(SavantPalette.inkSecondary)
                                .frame(width: 16)
                            Circle()
                                .fill(SavantPalette.color(forPercentile: 96 - index * 9))
                                .frame(width: 32, height: 32)
                                .overlay(Text(String(stat.1.split(separator: " ").compactMap(\.first).prefix(2))).font(SavantType.micro).foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.1)
                                    .font(SavantType.bodyBold)
                                    .foregroundStyle(SavantPalette.ink)
                                    .lineLimit(1)
                                Text(stat.0)
                                    .font(SavantType.micro)
                                    .foregroundStyle(SavantPalette.inkTertiary)
                            }
                            Spacer()
                            Text(stat.2)
                                .font(SavantType.statMed)
                                .foregroundStyle(SavantPalette.savantRed)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 49)
                        if index < stats.count - 1 {
                            Rectangle().fill(SavantPalette.divider).frame(height: 0.5)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func filterPill(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(SavantType.smallBold)
            .foregroundStyle(selected ? .white : SavantPalette.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(selected ? SavantPalette.savantRed : SavantPalette.surfaceAlt)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(selected ? .clear : SavantPalette.hairline, lineWidth: 0.5))
    }
}

private struct ShowcaseCard<Content: View>: View {
    let title: String
    let trailing: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(SavantType.sectionTitle)
                    .tracking(0.7)
                    .foregroundStyle(SavantPalette.ink)
                Spacer()
                Text(trailing)
                    .font(SavantType.micro)
                    .tracking(0.5)
                    .foregroundStyle(SavantPalette.inkTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(SavantPalette.surfaceSunk)

            content
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SavantPalette.hairline, lineWidth: 0.5))
        .shadow(color: SavantPalette.savantNavy.opacity(0.08), radius: 14, y: 6)
    }
}

#if DEBUG
#Preview {
    UpdateShowcaseView(onFinish: {})
        .environmentObject(StoreService.shared)
        .preferredColorScheme(.light)
}
#endif
