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
    var season: Int? = nil

    private var normalizedTeam: String {
        normalizedTeamAbbreviation(team)
    }

    private var seasonLabel: String {
        let year = season ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        return "\(year) Season"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MLBTeamColor.color(normalizedTeam))
                    .frame(width: 56, height: 56)
                Text(normalizedTeam)
                    .font(SavantType.statLarge)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(teamFullName(normalizedTeam))
                    .font(SavantType.playerName)
                    .foregroundStyle(SavantPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(seasonLabel)
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
                    Button(action: {
                        selected = tab
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
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

