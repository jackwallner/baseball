import XCTest
@testable import Baseball_Savvy_StatScout

/// Guards the two things that silently broke the boards: metric labels drifting
/// away from what the backend emits, and ranking on a value string that is
/// often empty.
@MainActor
final class StatDirectionTests: XCTestCase {

    // MARK: - Label drift

    /// `lowerIsBetter` matches by exact string, so a label that no longer
    /// exists is a silent no-op and the metric defaults to "highest first".
    /// That is how `Hard-Hit%`, `Avg EV Against`, `Max EV Against`, `xISO` and
    /// `xOBP` came to open the pitching board with the worst arms at rank 1.
    func testEveryLowerIsBetterLabelIsARealLabel() {
        for category in MetricCategory.allCases {
            guard let known = MetricCategory.knownLabels[category] else {
                return XCTFail("no known labels captured for \(category)")
            }
            for label in known where DashboardViewModel.lowerIsBetter(label: label, category: category) {
                XCTAssertTrue(
                    known.contains(label),
                    "\(category) treats '\(label)' as lower-is-better but the backend never emits it"
                )
            }
        }
    }

    func testPitcherContactAllowedIsLowerIsBetter() {
        for label in ["Hard-Hit%", "Avg EV Against", "Max EV Against", "xISO", "xOBP",
                      "xwOBA", "xBA", "xSLG", "xERA", "Barrel%", "BB%"] {
            XCTAssertTrue(
                DashboardViewModel.lowerIsBetter(label: label, category: .pitching),
                "pitching \(label): allowing less of it is better, so it must sort ascending by default"
            )
        }
    }

    func testPitcherStrikeoutsAndStuffAreHigherIsBetter() {
        for label in ["K%", "Whiff%", "Chase%", "Fastball Velo", "Fastball Spin", "Curve Spin"] {
            XCTAssertFalse(
                DashboardViewModel.lowerIsBetter(label: label, category: .pitching),
                "pitching \(label): more of it is better"
            )
        }
    }

    func testHitterSwingAndMissIsLowerIsBetter() {
        for label in ["K%", "Whiff%", "Chase%"] {
            XCTAssertTrue(
                DashboardViewModel.lowerIsBetter(label: label, category: .hitting),
                "hitting \(label): the hitter's own failure, so less is better"
            )
        }
    }

    func testHitterProductionIsHigherIsBetter() {
        for label in ["xwOBA", "xBA", "xSLG", "xISO", "xOBP", "Barrel%", "Hard-Hit%",
                      "EV", "Max EV", "BB%", "Bat Speed"] {
            XCTAssertFalse(
                DashboardViewModel.lowerIsBetter(label: label, category: .hitting),
                "hitting \(label): more of it is better"
            )
        }
    }

    /// The same string means opposite things by side, and the boards used to
    /// disagree with the Trends tab about which.
    func testSharedLabelsFlipBetweenSides() {
        for label in ["Whiff%", "Chase%"] {
            XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: label, category: .hitting))
            XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: label, category: .pitching))
        }
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Barrel%", category: .pitching))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "Barrel%", category: .hitting))
    }

    func testPriorityOrderOnlyListsRealLabels() {
        for category in MetricCategory.allCases {
            guard let known = MetricCategory.knownLabels[category] else { continue }
            for label in category.metricPriorityOrder {
                XCTAssertTrue(
                    known.contains(label),
                    "\(category) priority order lists '\(label)', which the backend never emits"
                )
            }
        }
    }

    // MARK: - Ranking

    private func player(_ id: Int, _ name: String, value: String, percentile: Int,
                        label: String = "Hard-Hit%", category: MetricCategory = .hitting) -> Player {
        Player(
            playerId: id, name: name, team: "NYY", position: "RF", handedness: "R/R",
            imageURL: nil, updatedAt: Date(), season: 2026,
            metrics: [Metric(id: "m\(id)", label: label, value: value, percentile: percentile, category: category)],
            standardStats: [], games: []
        )
    }

    /// The regression: a blank value string parses to nil, and the old
    /// comparator swept those players into a tail below everyone with a
    /// printable number no matter how much better their percentile was.
    func testBlankValuesRankByPercentileNotLast() {
        let players = [
            player(1, "Printable but poor", value: "22.0%", percentile: 5),
            player(2, "Blank but elite", value: "", percentile: 99),
            player(3, "Blank and poor", value: "", percentile: 2),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(label: "Hard-Hit%", category: .hitting, descending: true)
        )
        XCTAssertEqual(ranked.map(\.name), ["Blank but elite", "Printable but poor", "Blank and poor"])
    }

    func testPitcherBoardOpensWithTheBestArm() {
        let players = [
            player(1, "Gets hit hard", value: "48.0%", percentile: 3, label: "Hard-Hit%", category: .pitching),
            player(2, "Suppresses contact", value: "28.0%", percentile: 97, label: "Hard-Hit%", category: .pitching),
        ]
        // What the board does on open: the default direction for this metric.
        let descending = DashboardViewModel.defaultSortDescending(label: "Hard-Hit%", category: .pitching)
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(label: "Hard-Hit%", category: .pitching, descending: descending)
        )
        XCTAssertEqual(ranked.first?.name, "Suppresses contact")
    }

    /// Flipping the chip still means what it says: highest raw value first.
    func testFlippingDirectionInvertsTheBoard() {
        let players = [
            player(1, "Low ERA", value: "2.10", percentile: 95, label: "xERA", category: .pitching),
            player(2, "High ERA", value: "5.80", percentile: 8, label: "xERA", category: .pitching),
        ]
        let ascending = players.sorted(
            by: DashboardViewModel.metricComparator(label: "xERA", category: .pitching, descending: false)
        )
        XCTAssertEqual(ascending.first?.name, "Low ERA")
        let descending = players.sorted(
            by: DashboardViewModel.metricComparator(label: "xERA", category: .pitching, descending: true)
        )
        XCTAssertEqual(descending.first?.name, "High ERA")
    }

    func testEqualPercentilesBreakTiesOnValue() {
        let players = [
            player(1, "Lower value", value: "40.0%", percentile: 80),
            player(2, "Higher value", value: "44.0%", percentile: 80),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(label: "Hard-Hit%", category: .hitting, descending: true)
        )
        XCTAssertEqual(ranked.map(\.name), ["Higher value", "Lower value"])
    }

    func testPlayersMissingTheMetricSortLastInBothDirections() {
        let has = player(1, "Has it", value: "40.0%", percentile: 50)
        let lacks = Player(
            playerId: 2, name: "Lacks it", team: "NYY", position: "RF", handedness: "R/R",
            imageURL: nil, updatedAt: Date(), season: 2026,
            metrics: [Metric(id: "other", label: "xwOBA", value: ".300", percentile: 40, category: .hitting)],
            standardStats: [], games: []
        )
        for descending in [true, false] {
            let ranked = [lacks, has].sorted(
                by: DashboardViewModel.metricComparator(label: "Hard-Hit%", category: .hitting, descending: descending)
            )
            XCTAssertEqual(ranked.last?.name, "Lacks it", "descending: \(descending)")
        }
    }
}
