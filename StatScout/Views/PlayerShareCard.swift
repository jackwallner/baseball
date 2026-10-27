import SwiftUI
import UniformTypeIdentifiers

/// The image a player's percentile board is shared as.
///
/// Built from the same `MetricBar` rows as the profile, so a card dropped in a
/// group chat reads exactly like the screen it came from, with the app named
/// in the footer as the place to look the rest up.
struct PlayerShareCard: View {
    let player: Player
    let groups: [(category: MetricCategory, metrics: [Metric])]
    let seasonLabel: String
    let isCurrentSeason: Bool

    static let width: CGFloat = 390

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(groups, id: \.category) { group in
                SavantSubSectionBar(title: group.category.title)
                ForEach(Array(group.metrics.enumerated()), id: \.element.id) { index, metric in
                    MetricBar(metric: metric)
                        .padding(.horizontal, SavantGeo.padCard)
                        .padding(.vertical, 7)
                        .background(index % 2 == 0 ? SavantPalette.surface : SavantPalette.surfaceAlt)
                }
            }
            footer
        }
        .frame(width: Self.width)
        .background(SavantPalette.surface)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 52)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(SavantFont.condensed(24, weight: .black))
                    .foregroundStyle(SavantPalette.inkOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(identityLine)
                    .font(SavantType.small)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(seasonLabel)
                    .font(SavantFont.mono(20, weight: .bold))
                    .foregroundStyle(SavantPalette.inkOnDark)
                Text("PERCENTILES")
                    .font(SavantType.micro)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(SavantGeo.padPage)
        .background(SavantPalette.savantNavy)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("StatScout")
                .font(SavantFont.condensed(16, weight: .black))
                .foregroundStyle(SavantPalette.savantNavy)
            Spacer(minLength: 8)
            Text(footnote)
                .font(SavantType.small)
                .foregroundStyle(SavantPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, SavantGeo.padCard)
        .padding(.vertical, 12)
        .background(SavantPalette.surfaceAlt)
        .overlay(Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline), alignment: .top)
    }

    private var identityLine: String {
        [displayTeamFullName(player.team), positionAndHandedness(player)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// A current-season board moves daily, so it carries its date. A past
    /// season is settled and just says what it is ranked against.
    private var footnote: String {
        guard isCurrentSeason else { return String(localized: "Ranked against MLB qualifiers") }
        let date = player.updatedAt.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "Through \(date)")
    }
}

/// A rendered share card, handed to the share sheet as a PNG.
struct PlayerShareImage: Transferable {
    let png: Data
    let fileName: String

    var preview: Image {
        UIImage(data: png).map(Image.init(uiImage:)) ?? Image(systemName: "photo")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.fileName }
    }

    @MainActor
    static func render(_ card: PlayerShareCard) -> PlayerShareImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let png = renderer.uiImage?.pngData() else { return nil }
        let slug = card.player.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return PlayerShareImage(png: png, fileName: "\(slug)-\(card.seasonLabel.replacingOccurrences(of: " ", with: "-")).png")
    }
}

enum StatScoutShare {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(AppStoreReviewLinks.appStoreID)")!

    static func message(for player: Player, seasonLabel: String) -> String {
        let link = appStoreURL.absoluteString
        return String(localized: "\(player.name), \(seasonLabel) percentiles on StatScout \(link)")
    }
}
