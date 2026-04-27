import SwiftUI

// MARK: - Module 1: Player Identity Strip

struct PlayerIdentityStrip: View {
    let player: Player
    var showOverallBadge: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 72)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(SavantType.playerName)
                    .foregroundStyle(SavantPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(teamFullName(player.team))
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(player.position) · \(player.handedness)")
                    .font(SavantType.small)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            if showOverallBadge {
                OverallPercentileBadge(percentile: player.overallPercentile)
            }
        }
        .padding(.horizontal, SavantGeo.padPage)
        .padding(.vertical, SavantGeo.padPage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavantPalette.savantNavy)
    }
}

struct TeamIdentityStrip: View {
    let team: String
    let playerCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MLBTeamColor.color(team))
                    .frame(width: 56, height: 56)
                Text(team)
                    .font(SavantType.statLarge)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(teamFullName(team))
                    .font(SavantType.playerName)
                    .foregroundStyle(SavantPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(playerCount) Players · 2026 Season")
                    .font(SavantType.small)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, SavantGeo.padPage)
        .padding(.vertical, SavantGeo.padPage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavantPalette.savantNavy)
    }
}

// MARK: - Module 3: Section Bar

struct SavantSectionBar: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(SavantPalette.savantRed).frame(width: 2)
            Text(title.uppercased())
                .font(SavantType.sectionTitle)
                .tracking(0.8)
                .foregroundStyle(SavantPalette.ink)
                .padding(.leading, 10)
            Spacer()
            if let trailing { trailing.padding(.trailing, 12) }
        }
        .frame(height: SavantGeo.rowHeightHeader)
        .background(SavantPalette.surfaceSunk)
    }
}

struct SavantSubSectionBar: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = SavantPalette.inkSecondary

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(SavantType.micro)
                .tracking(0.6)
                .foregroundStyle(SavantPalette.inkSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(SavantType.statSmall)
                    .foregroundStyle(trailingColor)
            }
        }
        .frame(height: 26)
        .padding(.horizontal, SavantGeo.padCard)
        .background(SavantPalette.surfaceAlt)
        .overlay(Rectangle().fill(SavantPalette.divider).frame(height: 0.5), alignment: .bottom)
    }
}

// MARK: - Module 5: Tab Bar

struct SavantTabs: View {
    let tabs: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    Button(action: { selected = tab }) {
                        VStack(spacing: 0) {
                            Text(tab.uppercased())
                                .font(SavantType.smallBold)
                                .tracking(0.5)
                                .foregroundStyle(selected == tab ? SavantPalette.ink : SavantPalette.inkTertiary)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                            Rectangle()
                                .fill(selected == tab ? SavantPalette.savantRed : Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
            }
        }
        .background(SavantPalette.surface)
        .overlay(Rectangle().fill(SavantPalette.hairline).frame(height: SavantGeo.hairline), alignment: .bottom)
    }
}

// MARK: - Module 6: Filter Pill Row

struct FilterPillRow: View {
    var body: some View {
        HStack(spacing: 8) {
            FilterPill(label: "Batters", hasChevron: true)
            FilterPill(label: "All Teams", hasChevron: true)
            FilterPill(label: "2026", hasChevron: true)
            Spacer()
            Button(action: {}) {
                Text("UPDATE")
                    .font(SavantType.micro)
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(SavantPalette.savantRed)
                    .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
            }
        }
        .padding(.horizontal, SavantGeo.padPage)
        .padding(.vertical, 12)
        .background(SavantPalette.surface)
        .overlay(Rectangle().fill(SavantPalette.hairline).frame(height: SavantGeo.hairline), alignment: .bottom)
    }
}

struct FilterPill: View {
    let label: String
    var hasChevron: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(SavantType.smallBold)
                .foregroundStyle(SavantPalette.ink)
            if hasChevron {
                Text("▾")
                    .font(.system(size: 10))
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(SavantPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - App Header

struct AppHeader: View {
    var onMetricLeaders: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text("savant")
                .font(.system(size: 26, weight: .heavy))
                .italic()
                .foregroundStyle(.white)
            +
            Text("STATSCOUT")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
                .baselineOffset(6)
            Spacer()
            HStack(spacing: 12) {
                if let onMetricLeaders {
                    Button(action: onMetricLeaders) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }
        }
        .padding(.horizontal, SavantGeo.padPage)
        .frame(height: 56)
        .background(SavantPalette.savantNavy)
    }
}

struct BreadcrumbStrip: View {
    let crumbs: [(String, Bool)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkTertiary)
                }
                Text(crumb.0)
                    .font(SavantType.smallBold)
                    .foregroundStyle(crumb.1 ? SavantPalette.ink : SavantPalette.inkSecondary)
            }
        }
        .padding(.horizontal, SavantGeo.padPage)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavantPalette.surface)
        .overlay(Rectangle().fill(SavantPalette.hairline).frame(height: SavantGeo.hairline), alignment: .bottom)
    }
}
