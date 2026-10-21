import XCTest
@testable import Baseball_Savvy_StatScout

/// The unfolded iPhone Duo splits into a tabs pane and a detail pane either
/// side of the fold. Everything else, the folded Duo included, keeps one column.
@MainActor
final class UnfoldedSplitTests: XCTestCase {

    func testCompactWidthNeverSplits() {
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 470...481))
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
    }

    func testTooNarrowForTwoPhonePanesStaysSingleColumn() {
        // The unfolded Duo held in portrait is regular width but 669 pt wide.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
        XCTAssertNil(UnfoldedSplit.make(width: 719, isRegularWidth: true, fold: nil))
    }

    func testPanesSitAtTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 470...481)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 470, secondaryX: 481, secondaryWidth: 470))
    }

    func testFoldOffCentreStillLeavesNothingUnderIt() {
        // A trailing vertical bar shortens the container, not the fold.
        let split = UnfoldedSplit.make(width: 880, isRegularWidth: true, fold: 470...481)
        XCTAssertEqual(split?.primaryWidth, 470)
        XCTAssertEqual(split?.secondaryX, 481)
        XCTAssertEqual(split?.secondaryWidth, 399)
    }

    func testNoReportedFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldThatWouldSqueezeAPaneFallsBackToAnEvenSplit() {
        let split = UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 300...310)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
        let late = UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 500...520)
        XCTAssertEqual(late, UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
    }

    func testEveryPaneIsAtLeastPhoneWidth() {
        for width in stride(from: 720, through: 1400, by: 37) {
            let w = CGFloat(width)
            for fold in [nil, (w / 2 - 6)...(w / 2 + 6), 360...372] as [ClosedRange<CGFloat>?] {
                guard let split = UnfoldedSplit.make(width: w, isRegularWidth: true, fold: fold) else {
                    return XCTFail("no split at \(w)")
                }
                XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
                XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
                XCTAssertGreaterThanOrEqual(split.secondaryX, split.primaryWidth)
                XCTAssertEqual(split.secondaryX + split.secondaryWidth, w)
            }
        }
    }

    func testDetailMatchesTheSamePageWhateverTheSlate() {
        let judge = Player(
            playerId: 592450, name: "Aaron Judge", team: "NYY", position: "RF",
            handedness: "R", imageURL: nil, updatedAt: Date(), season: 2025,
            playerType: "batter", metrics: [], standardStats: nil, games: []
        )
        let regular = PaneDetail.player(PlayerRoute(player: judge, phase: .regular, season: 2025))
        let october = PaneDetail.player(PlayerRoute(player: judge, phase: .postseason, season: 2025))
        XCTAssertTrue(regular.matches(october))
        XCTAssertFalse(regular.matches(.team(TeamDestination(abbr: "NYY"))))
        XCTAssertFalse(regular.matches(nil))
        XCTAssertTrue(PaneDetail.team(TeamDestination(abbr: "NYY")).matches(.team(TeamDestination(abbr: "NYY"))))
    }
}
