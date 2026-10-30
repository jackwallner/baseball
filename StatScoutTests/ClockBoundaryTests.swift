import XCTest
@testable import Baseball_Savvy_StatScout

/// Date logic pinned to a fixed clock and explicit zones, never the machine's.
///
/// Every test names the past fix it guards, or says it is a new guard.
final class ClockBoundaryTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func local(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                       _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: New Year and the season gap

    /// New guard: a fresh launch opens on the calendar year, which runs ahead
    /// of `StatScoutSeason.current` for the whole of the offseason after New
    /// Year. The flip is local midnight.
    func testOpeningSeasonFollowsTheCalendarYearInTheViewersZone() {
        XCTAssertEqual(StatScoutSeason.calendarYear(on: local(la, 2026, 12, 31, 23, 59, 59), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.calendarYear(on: local(la, 2027, 1, 1, 0, 0, 0), calendar: la), 2027)
        let instantAfterUTCNewYear = instant("2027-01-01T03:00:00Z")
        XCTAssertEqual(StatScoutSeason.calendarYear(on: instantAfterUTCNewYear, calendar: utc), 2027)
        XCTAssertEqual(StatScoutSeason.calendarYear(on: instantAfterUTCNewYear, calendar: la), 2026)
    }

    /// 2ac56f7: after New Year the default season has no data yet, and the
    /// load must land a free user on the season that does (the live one),
    /// never leave the board on an empty year. Walks the off-season, opening
    /// day, October and the following winter against a fixed clock.
    @MainActor
    func testTheSeasonLifecycleLandsOnTheLiveSeasonAtEveryStage() async {
        let live = StatScoutSeason.current
        let player = Player(
            playerId: 1, name: "Live", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: Date(), season: live, metrics: [], standardStats: [], games: []
        )
        // Winter before the season, the opener, the playoffs and the winter after.
        let moments = [
            local(la, live, 1, 2), local(la, live, 3, 26, 12), local(la, live, 10, 12, 20),
            local(la, live + 1, 1, 2),
        ]
        for moment in moments {
            let vm = DashboardViewModel(provider: MockProvider(players: [player]))
            vm.selectedSeason = StatScoutSeason.calendarYear(on: moment, calendar: la)
            await vm.load()
            XCTAssertEqual(vm.selectedSeason, live, "\(moment)")
            XCTAssertEqual(vm.seasonPlayers.map(\.playerId), [1], "\(moment)")
        }
    }

    /// d954a7fa: the phase control is a function of the data, not the date. A
    /// postseason game in the pipeline offers it on the live season only,
    /// and the winter after the final game offers nothing.
    @MainActor
    func testPhaseChoiceFollowsDataThroughPreseasonRegularPostseasonAndOffseason() {
        let live = StatScoutSeason.current
        let vm = DashboardViewModel(provider: MockProvider())
        vm.selectedSeason = live

        // Preseason and regular season: no postseason game yet.
        vm.postseasonThrough = nil
        XCTAssertFalse(vm.offersPhaseChoice)
        vm.selectPhase(.postseason)
        XCTAssertEqual(vm.selectedPhase, .regular)

        // October: the first Wild Card game has been closed out.
        vm.postseasonThrough = local(la, live, 10, 1)
        XCTAssertTrue(vm.offersPhaseChoice)
        vm.selectPhase(.postseason)
        XCTAssertEqual(vm.selectedPhase, .postseason)

        // The new calendar year, before the next season has data: the picker
        // sits on a year that is not the live season, so there is no choice
        // and the board is the regular season.
        vm.selectSeason(live + 1)
        XCTAssertFalse(vm.offersPhaseChoice)
        XCTAssertEqual(vm.selectedPhase, .regular)
    }

    // MARK: Postgres dates

    /// a73d3a23: "Through Jul 28" must name the calendar day the pipeline
    /// closed out. A bare date is local midnight of that day in the reader's
    /// zone, including the day clocks change, and never the day before.
    func testPostgresDatesLandOnLocalMidnightIncludingChangeoverDays() throws {
        for (raw, y, m, d) in [("2026-07-28", 2026, 7, 28), ("2026-11-01", 2026, 11, 1),
                               ("2027-03-14", 2027, 3, 14), ("2026-12-31", 2026, 12, 31)] {
            let parsed = try XCTUnwrap(Date.fromPostgresDate(raw, calendar: la), raw)
            let parts = la.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)
            XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [y, m, d, 0, 0], raw)
        }
        let la1101 = try XCTUnwrap(Date.fromPostgresDate("2026-11-01", calendar: la))
        let utc1101 = try XCTUnwrap(Date.fromPostgresDate("2026-11-01", calendar: utc))
        XCTAssertEqual(la1101.timeIntervalSince(utc1101), 7 * 3600, "PDT is UTC-7 until the 2 AM changeover")
        let la1102 = try XCTUnwrap(Date.fromPostgresDate("2026-11-02", calendar: la))
        XCTAssertEqual(la1102.timeIntervalSince(la1101), 25 * 3600, "the fall-back day is 25 hours long")
    }

    // MARK: Team window slide

    /// d954a7fa: callers ask for "the last N days from today"; once the data
    /// trails today the lower bound slides back by the gap so the window
    /// keeps its length. No gap, or an anchor at or past now, leaves it alone.
    func testWindowSlidesBackByExactlyTheGapBetweenDataAndNow() {
        let now = instant("2026-10-05T15:00:00Z")
        let since = instant("2026-09-28T15:00:00Z")
        let twoDays = instant("2026-10-03T15:00:00Z")
        XCTAssertEqual(DashboardViewModel.slidWindowStart(since, anchor: twoDays, now: now),
                       instant("2026-09-26T15:00:00Z"))
        XCTAssertEqual(DashboardViewModel.slidWindowStart(since, anchor: now.addingTimeInterval(-1), now: now),
                       since.addingTimeInterval(-1))
        XCTAssertEqual(DashboardViewModel.slidWindowStart(since, anchor: now, now: now), since)
        XCTAssertEqual(DashboardViewModel.slidWindowStart(since, anchor: now.addingTimeInterval(60), now: now), since)
        XCTAssertEqual(DashboardViewModel.slidWindowStart(since, anchor: nil, now: now), since)
    }

    // MARK: Game-log windows

    private func log(_ date: String) throws -> PlayerGameLog {
        let json = """
        {"player_id":1,"season":2026,"game_date":"\(date)","player_type":"batter",
         "plate_appearances":4,"batted_ball_events":3,"metrics":{}}
        """
        return try JSONDecoder().decode(PlayerGameLog.self, from: Data(json.utf8))
    }

    /// d954a7fa: game dates are Eastern midnight, whatever zone the phone is
    /// in: 04:00Z in daylight time, 05:00Z in standard time, and midnight on
    /// the changeover days still comes before the 2 AM switch.
    func testGameDatesParseAsEasternMidnightAcrossDST() throws {
        XCTAssertEqual(try log("2026-10-04").gameDate, instant("2026-10-04T04:00:00Z"))
        XCTAssertEqual(try log("2026-11-01").gameDate, instant("2026-11-01T04:00:00Z"))
        XCTAssertEqual(try log("2026-11-02").gameDate, instant("2026-11-02T05:00:00Z"))
        XCTAssertEqual(try log("2027-03-14").gameDate, instant("2027-03-14T05:00:00Z"))
        XCTAssertEqual(try log("2027-03-15").gameDate, instant("2027-03-15T04:00:00Z"))
    }

    /// d954a7fa: team form anchors on the newest game, not the clock, and a
    /// 15-day window is exactly 15 dates (the anchor day and the 14 before),
    /// across the fall-back changeover and in either zone.
    func testTeamWindowIsExactlyNDatesEndingOnTheNewestGame() throws {
        let dates = (0..<20).map { offset -> String in
            let day = la.date(from: DateComponents(year: 2026, month: 10, day: 14 + offset))!
            return DateFormatter.iso(day, la)
        }
        let logs = try dates.map { try log($0) }
        XCTAssertEqual(dates.first, "2026-10-14")
        XCTAssertEqual(dates.last, "2026-11-02")
        for calendar in [la, utc] {
            let window = RecentFormWindow.logs(logs, endingOnNewestGameWithin: 15, calendar: calendar)
            XCTAssertEqual(window.count, 15, calendar.timeZone.identifier)
            XCTAssertEqual(window.map(\.gameDate).min(), try log("2026-10-19").gameDate)
        }
        XCTAssertTrue(RecentFormWindow.logs([], endingOnNewestGameWithin: 15, calendar: la).isEmpty)
    }

    /// New guard for the player card: the cutoff is `days` calendar days
    /// before now, so on the evening of 4 November the cutoff is 9 PM on 20
    /// October (Pacific daylight time), which is exactly Eastern midnight of
    /// the 21st. A 15 * 86,400 s subtraction would land an hour later, across
    /// the fall-back day, and drop that game.
    func testPlayerWindowCutoffIsCalendarDaysAcrossTheFallBackDay() throws {
        let now = local(la, 2026, 11, 4, 21)
        let onCutoff = try log("2026-10-21")
        let dayBefore = try log("2026-10-20")
        XCTAssertEqual(la.date(byAdding: .day, value: -15, to: now), onCutoff.gameDate)
        let kept = RecentFormWindow.logs([dayBefore, onCutoff], lastDays: 15, now: now, calendar: la)
        XCTAssertEqual(kept.map(\.gameDate), [onCutoff.gameDate])
    }

    /// F-05 (2026-10-30 bug hunt): the profile's cutoff was local midnight
    /// while game dates are Eastern midnight, so west of New York the oldest
    /// day fell outside: Pacific users saw 14 days labelled 15. The window is
    /// now exactly 15 game dates ending on the data-through day in every zone.
    func testProfileWindowHoldsNDatesEndingOnTheDataThroughDayInEveryZone() throws {
        let dataThrough = local(utc, 2026, 9, 27)
        let dates = (0..<16).map { offset -> String in
            let day = utc.date(byAdding: .day, value: -offset, to: dataThrough)!
            return DateFormatter.iso(day, utc)
        }
        let logs = try dates.map { try log($0) }
        XCTAssertEqual(dates.last, "2026-09-12")
        let zones = ["America/Los_Angeles", "America/Chicago", "America/Denver", "Pacific/Honolulu",
                     "America/New_York", "Europe/Berlin", "Asia/Tokyo"]
        for zone in zones {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let anchor = try XCTUnwrap(Date.fromPostgresDate("2026-09-27", calendar: calendar))
            let window = RecentFormWindow.logs(logs, days: 15, endingOn: anchor, calendar: calendar)
            XCTAssertEqual(window.count, 15, zone)
            XCTAssertEqual(window.map(\.gameDate).min(), try log("2026-09-13").gameDate, zone)
        }
    }

    // MARK: Weekly delta

    func testWeeklyDeltaWindowEdge() {
        let now = instant("2026-11-03T12:00:00Z")
        func trend(_ id: String, ageSeconds: TimeInterval, delta: Int) -> GameTrend {
            GameTrend(id: id, date: now.addingTimeInterval(-ageSeconds), opponent: "BOS",
                      summary: "", percentileDelta: delta, keyMetric: "xwOBA")
        }
        let player = Player(
            playerId: 1, name: "T", team: "NYY", position: "RF", handedness: "R/R", imageURL: nil,
            updatedAt: now, metrics: [], standardStats: [],
            games: [
                trend("edge", ageSeconds: 7 * 86_400, delta: 4),
                trend("just-out", ageSeconds: 7 * 86_400 + 1, delta: 50),
                trend("fresh", ageSeconds: 60, delta: -1),
            ]
        )
        XCTAssertEqual(player.weeklyDelta(asOf: now), 3)
    }
}

private extension DateFormatter {
    static func iso(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
