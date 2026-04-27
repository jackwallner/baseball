import Foundation

struct SampleData {
    static let players: [Player] = [
        Player(
            id: 592450,
            name: "Aaron Judge",
            team: "NYY",
            position: "RF",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/592450/spots/240"),
            updatedAt: Date(),
            metrics: [
                Metric(id: "judge-xwoba", label: "xwOBA", value: ".463", percentile: 100, direction: .up, category: .hitting),
                Metric(id: "judge-ev", label: "Avg EV", value: "96.2 mph", percentile: 100, direction: .flat, category: .hitting),
                Metric(id: "judge-barrel", label: "Barrel%", value: "26.9%", percentile: 100, direction: .up, category: .hitting),
                Metric(id: "judge-sprint", label: "Sprint", value: "27.2 ft/s", percentile: 58, direction: .down, category: .running)
            ],
            games: [
                GameTrend(id: "judge-bos-1", date: Date().addingTimeInterval(-86_400), opponent: "BOS", summary: "Two barrels and a 113 mph double pushed his quality-contact profile higher.", percentileDelta: 3, keyMetric: "Barrel%"),
                GameTrend(id: "judge-tb-1", date: Date().addingTimeInterval(-172_800), opponent: "TB", summary: "Chase decisions stabilized after an aggressive weekend series.", percentileDelta: 1, keyMetric: "xwOBA")
            ]
        ),
        Player(
            id: 660271,
            name: "Shohei Ohtani",
            team: "LAD",
            position: "DH",
            handedness: "L/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/660271/spots/240"),
            updatedAt: Date(),
            metrics: [
                Metric(id: "ohtani-xslg", label: "xSLG", value: ".676", percentile: 100, direction: .up, category: .hitting),
                Metric(id: "ohtani-hardhit", label: "Hard-Hit%", value: "61.4%", percentile: 100, direction: .up, category: .hitting),
                Metric(id: "ohtani-sprint", label: "Sprint", value: "28.1 ft/s", percentile: 82, direction: .flat, category: .running),
                Metric(id: "ohtani-arm", label: "Arm Value", value: "+2", percentile: 74, direction: .flat, category: .fielding)
            ],
            games: [
                GameTrend(id: "ohtani-sf-1", date: Date().addingTimeInterval(-86_400), opponent: "SF", summary: "Lifted three balls over 100 mph and added a stolen-base opportunity.", percentileDelta: 4, keyMetric: "xSLG"),
                GameTrend(id: "ohtani-sd-1", date: Date().addingTimeInterval(-259_200), opponent: "SD", summary: "Launch angle returned to his optimal power band.", percentileDelta: 2, keyMetric: "Hard-Hit%")
            ]
        ),
        Player(
            id: 669203,
            name: "Bobby Witt Jr.",
            team: "KC",
            position: "SS",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/669203/spots/240"),
            updatedAt: Date(),
            metrics: [
                Metric(id: "witt-sprint", label: "Sprint", value: "30.5 ft/s", percentile: 100, direction: .flat, category: .running),
                Metric(id: "witt-xba", label: "xBA", value: ".329", percentile: 99, direction: .up, category: .hitting),
                Metric(id: "witt-oaa", label: "OAA", value: "+15", percentile: 98, direction: .up, category: .fielding),
                Metric(id: "witt-ev", label: "Avg EV", value: "92.1 mph", percentile: 87, direction: .flat, category: .hitting)
            ],
            games: [
                GameTrend(id: "witt-det-1", date: Date().addingTimeInterval(-86_400), opponent: "DET", summary: "Converted two elite-difficulty plays and beat out a 30.9 ft/s infield single.", percentileDelta: 5, keyMetric: "OAA"),
                GameTrend(id: "witt-cle-1", date: Date().addingTimeInterval(-172_800), opponent: "CLE", summary: "Contact quality held while swing decisions improved.", percentileDelta: 2, keyMetric: "xBA")
            ]
        ),
        Player(
            id: 694973,
            name: "Paul Skenes",
            team: "PIT",
            position: "SP",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/694973/spots/240"),
            updatedAt: Date(),
            metrics: [
                Metric(id: "skenes-velo", label: "Fastball Velo", value: "98.8 mph", percentile: 99, direction: .flat, category: .pitching),
                Metric(id: "skenes-whiff", label: "Whiff%", value: "34.8%", percentile: 96, direction: .up, category: .pitching),
                Metric(id: "skenes-chase", label: "Chase%", value: "33.1%", percentile: 91, direction: .up, category: .pitching),
                Metric(id: "skenes-barrel", label: "Barrel Allowed", value: "4.2%", percentile: 88, direction: .flat, category: .pitching)
            ],
            games: [
                GameTrend(id: "skenes-chc-1", date: Date().addingTimeInterval(-86_400), opponent: "CHC", summary: "Generated 17 whiffs with premium fastball ride and splitter finish.", percentileDelta: 6, keyMetric: "Whiff%"),
                GameTrend(id: "skenes-mil-1", date: Date().addingTimeInterval(-345_600), opponent: "MIL", summary: "Held exit velocity down despite elevated pitch count.", percentileDelta: 1, keyMetric: "Barrel Allowed")
            ]
        )
    ]
}
