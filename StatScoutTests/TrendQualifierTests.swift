import XCTest
@testable import Baseball_Savvy_StatScout

/// The Trends board's minimum-playing-time control.
///
/// The board used to hard-code a flat 15 PA whatever window was showing, which
/// means two different things on a 7-day board and a 30-day one. These pin the
/// rate-per-window-day behaviour that replaced it.
final class TrendQualifierTests: XCTestCase {

    private func form(pa: Int, type: String = "batter", window: Int = 15) -> RecentForm {
        let json = """
        {
          "player_id": 1, "season": 2026, "player_type": "\(type)",
          "window_days": \(window), "as_of": "2026-07-31", "team": "SEA",
          "games": 10, "plate_appearances": \(pa), "batted_ball_events": 20,
          "metrics": {}, "prior_metrics": {}, "delta": {}
        }
        """
        return try! JSONDecoder().decode(RecentForm.self, from: Data(json.utf8))
    }

    func testAllAdmitsEveryone() {
        XCTAssertTrue(TrendQualifier.all.admits(form(pa: 1), windowDays: 30))
    }

    /// The same choice has to mean the same thing on every window, which a flat
    /// count can't do: 15 PA is a regular's week and a bench bat's month.
    func testMinimumScalesWithTheWindow() {
        XCTAssertEqual(TrendQualifier.sample.minimum(isPitcher: false, windowDays: 7), 7)
        XCTAssertEqual(TrendQualifier.sample.minimum(isPitcher: false, windowDays: 30), 30)
        XCTAssertEqual(TrendQualifier.regulars.minimum(isPitcher: false, windowDays: 15), 38)
    }

    func testPitchersAreMeasuredInBattersFaced() {
        XCTAssertGreaterThan(
            TrendQualifier.sample.minimum(isPitcher: true, windowDays: 15),
            TrendQualifier.sample.minimum(isPitcher: false, windowDays: 15)
        )
        XCTAssertTrue(TrendQualifier.sample.description(isPitcher: true, windowDays: 15).hasSuffix("BF"))
        XCTAssertTrue(TrendQualifier.sample.description(isPitcher: false, windowDays: 15).hasSuffix("PA"))
    }

    func testSampleCutsAThreePAWeekAndKeepsARegular() {
        XCTAssertFalse(TrendQualifier.sample.admits(form(pa: 3, window: 15), windowDays: 15))
        XCTAssertTrue(TrendQualifier.sample.admits(form(pa: 60, window: 15), windowDays: 15))
    }

    /// Refsnyder's row: three games inside the window, none in the window before
    /// it, so the rollup ships a value and no delta. The roster has to say N/A
    /// rather than leave the column blank.
    func testARowWithNoPriorWindowHasNoDelta() {
        let row = form(pa: 9)
        XCTAssertTrue(row.delta.isEmpty)
        XCTAssertTrue(row.priorMetrics.isEmpty)
    }
}
