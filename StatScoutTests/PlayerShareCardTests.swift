import XCTest
@testable import Baseball_Savvy_StatScout

@MainActor
final class PlayerShareCardTests: XCTestCase {
    private func metric(_ label: String, _ value: String, _ pct: Int, _ cat: MetricCategory) -> Metric {
        Metric(id: label, label: label, value: value, percentile: pct, category: cat)
    }

    private var card: PlayerShareCard {
        let hitting = [
            metric("xwOBA", ".442", 99, .hitting), metric("xBA", ".310", 95, .hitting),
            metric("xSLG", ".640", 99, .hitting), metric("Avg EV", "95.1", 98, .hitting),
            metric("Barrel%", "24.0%", 100, .hitting), metric("Hard-Hit%", "58.2%", 99, .hitting),
            metric("K%", "25.1%", 30, .hitting), metric("BB%", "18.0%", 100, .hitting),
            metric("Chase%", "18.9%", 85, .hitting), metric("Bat Speed", "77.3", 92, .hitting),
        ]
        let fielding = [metric("OAA", "3", 70, .fielding), metric("Arm Strength", "92.1", 75, .fielding)]
        let running = [metric("Sprint Speed", "27.0", 45, .running)]
        let player = Player(
            playerId: 592450, name: "Aaron Judge", team: "NYY", position: "RF", handedness: "R/R",
            imageURL: nil, updatedAt: Date(), season: 2026, metrics: hitting + fielding + running,
            standardStats: [], games: []
        )
        return PlayerShareCard(
            player: player,
            groups: [(.hitting, hitting), (.fielding, fielding), (.running, running)],
            seasonLabel: "2026",
            isCurrentSeason: true
        )
    }

    func testRendersPNGAtThreeTimesCardWidth() throws {
        let image = try XCTUnwrap(PlayerShareImage.render(card))
        let rendered = try XCTUnwrap(UIImage(data: image.png))
        XCTAssertEqual(rendered.size.width * rendered.scale, PlayerShareCard.width * 3, accuracy: 1)
        XCTAssertEqual(image.fileName, "Aaron-Judge-2026.png")

        let attachment = XCTAttachment(data: image.png, uniformTypeIdentifier: "public.png")
        attachment.name = "share-card"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHARE_CARD_OUT"] {
            try image.png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("share-card.png"))
        }
    }

    func testShareMessageLinksTheAppStoreListing() {
        let message = StatScoutShare.message(for: card.player, seasonLabel: "2026")
        XCTAssertTrue(message.contains("https://apps.apple.com/app/id\(AppStoreReviewLinks.appStoreID)"))
        XCTAssertTrue(message.hasPrefix("Aaron Judge, 2026 percentiles"))
    }
}
