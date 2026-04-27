import XCTest
@testable import StatScout

final class PlayerTests: XCTestCase {
    func testOverallPercentileDoubleAverage() {
        let metrics = [
            Metric(id: "m1", label: "A", value: "1", percentile: 75, direction: .flat, category: .hitting),
            Metric(id: "m2", label: "B", value: "2", percentile: 76, direction: .flat, category: .hitting),
            Metric(id: "m3", label: "C", value: "3", percentile: 77, direction: .flat, category: .hitting)
        ]
        let player = Player(
            id: 1, name: "Test", team: "NYY", position: "RF",
            handedness: "R/R", imageURL: nil,
            updatedAt: Date(), metrics: metrics, games: []
        )
        XCTAssertEqual(player.overallPercentile, 76) // 75.9 rounded
    }

    func testShareSummaryIncludesTopSignal() {
        let metric = Metric(id: "m1", label: "xwOBA", value: ".463", percentile: 100, direction: .up, category: .hitting)
        let player = Player(
            id: 1, name: "Aaron Judge", team: "NYY", position: "RF",
            handedness: "R/R", imageURL: nil,
            updatedAt: Date(), metrics: [metric], games: []
        )
        let summary = player.shareSummary
        XCTAssertTrue(summary.contains("Aaron Judge"))
        XCTAssertTrue(summary.contains("xwOBA"))
        XCTAssertTrue(summary.contains("100th"))
    }
}
