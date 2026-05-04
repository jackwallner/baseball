import Foundation

struct SampleData {
    // Players for 2026 season
    static let players: [Player] = [
        Player(
            playerId: 1,
            name: "Aaron Judge",
            team: "NYY",
            position: "RF",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/592450/spots/240"),
            updatedAt: Date(),
            season: 2026,
            metrics: [
                Metric(id: "judge-xwoba", label: "xwOBA", value: ".463", percentile: 100, category: .hitting),
                Metric(id: "judge-ev", label: "EV", value: "96.2", percentile: 100, category: .hitting),
                Metric(id: "judge-barrel", label: "Barrel%", value: "26.9%", percentile: 100, category: .hitting),
                Metric(id: "judge-sprint", label: "Sprint Speed", value: "27.2 ft/s", percentile: 58, category: .running)
            ],
            standardStats: [
                StandardStat(id: "std-AVG", label: "AVG", value: ".312"),
                StandardStat(id: "std-OBP", label: "OBP", value: ".458"),
                StandardStat(id: "std-SLG", label: "SLG", value: ".701"),
                StandardStat(id: "std-OPS", label: "OPS", value: "1.159"),
                StandardStat(id: "std-HR", label: "HR", value: "58"),
                StandardStat(id: "std-RBI", label: "RBI", value: "144"),
                StandardStat(id: "std-R", label: "R", value: "133"),
                StandardStat(id: "std-H", label: "H", value: "180"),
                StandardStat(id: "std-BB", label: "BB", value: "133"),
                StandardStat(id: "std-SO", label: "SO", value: "179"),
                StandardStat(id: "std-SB", label: "SB", value: "13")
            ],
            games: [
                GameTrend(id: "judge-bos-1", date: Date().addingTimeInterval(-86_400), opponent: "BOS", summary: "Two barrels and a 113 mph double pushed his quality-contact profile higher.", percentileDelta: 3, keyMetric: "Barrel%"),
                GameTrend(id: "judge-tb-1", date: Date().addingTimeInterval(-172_800), opponent: "TB", summary: "Chase decisions stabilized after an aggressive weekend series.", percentileDelta: 1, keyMetric: "xwOBA")
            ]
        ),
        Player(
            playerId: 660271,
            name: "Shohei Ohtani",
            team: "LAD",
            position: "DH",
            handedness: "L/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/660271/spots/240"),
            updatedAt: Date(),
            season: 2026,
            metrics: [
                Metric(id: "ohtani-xslg", label: "xSLG", value: ".676", percentile: 100, category: .hitting),
                Metric(id: "ohtani-hardhit", label: "Hard-Hit%", value: "61.4%", percentile: 100, category: .hitting),
                Metric(id: "ohtani-sprint", label: "Sprint Speed", value: "28.1 ft/s", percentile: 82, category: .running),
                Metric(id: "ohtani-arm", label: "Arm Value", value: "+2", percentile: 74, category: .fielding)
            ],
            standardStats: [
                StandardStat(id: "std-AVG", label: "AVG", value: ".310"),
                StandardStat(id: "std-OBP", label: "OBP", value: ".390"),
                StandardStat(id: "std-SLG", label: "SLG", value: ".660"),
                StandardStat(id: "std-OPS", label: "OPS", value: "1.050"),
                StandardStat(id: "std-HR", label: "HR", value: "54"),
                StandardStat(id: "std-RBI", label: "RBI", value: "130"),
                StandardStat(id: "std-R", label: "R", value: "118"),
                StandardStat(id: "std-H", label: "H", value: "178"),
                StandardStat(id: "std-BB", label: "BB", value: "91"),
                StandardStat(id: "std-SO", label: "SO", value: "162"),
                StandardStat(id: "std-SB", label: "SB", value: "59")
            ],
            games: [
                GameTrend(id: "ohtani-sf-1", date: Date().addingTimeInterval(-86_400), opponent: "SF", summary: "Lifted three balls over 100 mph and added a stolen-base opportunity.", percentileDelta: 4, keyMetric: "xSLG"),
                GameTrend(id: "ohtani-sd-1", date: Date().addingTimeInterval(-259_200), opponent: "SD", summary: "Launch angle returned to his optimal power band.", percentileDelta: 2, keyMetric: "Hard-Hit%")
            ]
        ),
        Player(
            playerId: 669203,
            name: "Bobby Witt Jr.",
            team: "KC",
            position: "SS",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/669203/spots/240"),
            updatedAt: Date(),
            season: 2026,
            metrics: [
                Metric(id: "witt-sprint", label: "Sprint Speed", value: "30.5 ft/s", percentile: 100, category: .running),
                Metric(id: "witt-xba", label: "xBA", value: ".329", percentile: 99, category: .hitting),
                Metric(id: "witt-oaa", label: "Range (OAA)", value: "+15", percentile: 98, category: .fielding),
                Metric(id: "witt-ev", label: "Avg EV", value: "92.1", percentile: 87, category: .hitting)
            ],
            standardStats: [
                StandardStat(id: "std-AVG", label: "AVG", value: ".332"),
                StandardStat(id: "std-OBP", label: "OBP", value: ".389"),
                StandardStat(id: "std-SLG", label: "SLG", value: ".588"),
                StandardStat(id: "std-OPS", label: "OPS", value: ".977"),
                StandardStat(id: "std-HR", label: "HR", value: "32"),
                StandardStat(id: "std-RBI", label: "RBI", value: "109"),
                StandardStat(id: "std-R", label: "R", value: "121"),
                StandardStat(id: "std-H", label: "H", value: "211"),
                StandardStat(id: "std-BB", label: "BB", value: "45"),
                StandardStat(id: "std-SO", label: "SO", value: "77"),
                StandardStat(id: "std-SB", label: "SB", value: "31")
            ],
            games: [
                GameTrend(id: "witt-det-1", date: Date().addingTimeInterval(-86_400), opponent: "DET", summary: "Converted two elite-difficulty plays and beat out a 30.9 ft/s infield single.", percentileDelta: 5, keyMetric: "OAA"),
                GameTrend(id: "witt-cle-1", date: Date().addingTimeInterval(-172_800), opponent: "CLE", summary: "Contact quality held while swing decisions improved.", percentileDelta: 2, keyMetric: "xBA")
            ]
        ),
        Player(
            playerId: 694973,
            name: "Paul Skenes",
            team: "PIT",
            position: "SP",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/694973/spots/240"),
            updatedAt: Date(),
            season: 2026,
            metrics: [
                Metric(id: "skenes-velo", label: "Fastball Velo", value: "98.8", percentile: 99, category: .pitching),
                Metric(id: "skenes-whiff", label: "Whiff%", value: "34.8%", percentile: 96, category: .pitching),
                Metric(id: "skenes-chase", label: "Chase%", value: "33.1%", percentile: 91, category: .pitching),
                Metric(id: "skenes-barrel", label: "Barrel Allowed", value: "4.2%", percentile: 88, category: .pitching)
            ],
            standardStats: [
                StandardStat(id: "std-ERA", label: "ERA", value: "1.96"),
                StandardStat(id: "std-WHIP", label: "WHIP", value: "0.95"),
                StandardStat(id: "std-W", label: "W", value: "11"),
                StandardStat(id: "std-L", label: "L", value: "3"),
                StandardStat(id: "std-SV", label: "SV", value: "0"),
                StandardStat(id: "std-IP", label: "IP", value: "133.1"),
                StandardStat(id: "std-H", label: "H", value: "87"),
                StandardStat(id: "std-R", label: "R", value: "32"),
                StandardStat(id: "std-ER", label: "ER", value: "29"),
                StandardStat(id: "std-BB", label: "BB", value: "39"),
                StandardStat(id: "std-SO", label: "SO", value: "170")
            ],
            games: [
                GameTrend(id: "skenes-chc-1", date: Date().addingTimeInterval(-86_400), opponent: "CHC", summary: "Generated 17 whiffs with premium fastball ride and splitter finish.", percentileDelta: 6, keyMetric: "Whiff%"),
                GameTrend(id: "skenes-mil-1", date: Date().addingTimeInterval(-345_600), opponent: "MIL", summary: "Held exit velocity down despite elevated pitch count.", percentileDelta: 1, keyMetric: "Barrel Allowed")
            ]
        ),
        // Players for 2025 season (different players to verify year switching works)
        Player(
            playerId: 2,
            name: "Juan Soto",
            team: "NYY",
            position: "LF",
            handedness: "L/L",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/665742/spots/240"),
            updatedAt: Date(),
            season: 2025,
            metrics: [
                Metric(id: "soto-xwoba", label: "xwOBA", value: ".410", percentile: 98, category: .hitting),
                Metric(id: "soto-bb", label: "BB%", value: "18.5%", percentile: 99, category: .hitting)
            ],
            standardStats: [
                StandardStat(id: "std-AVG", label: "AVG", value: ".288"),
                StandardStat(id: "std-OBP", label: "OBP", value: ".420"),
                StandardStat(id: "std-HR", label: "HR", value: "41")
            ],
            games: []
        ),
        Player(
            playerId: 3,
            name: "Vladimir Guerrero Jr.",
            team: "TOR",
            position: "1B",
            handedness: "R/R",
            imageURL: URL(string: "https://midfield.mlbstatic.com/v1/people/665489/spots/240"),
            updatedAt: Date(),
            season: 2025,
            metrics: [
                Metric(id: "vlad-xslg", label: "xSLG", value: ".612", percentile: 97, category: .hitting),
                Metric(id: "vlad-barrel", label: "Barrel%", value: "15.8%", percentile: 95, category: .hitting)
            ],
            standardStats: [
                StandardStat(id: "std-AVG", label: "AVG", value: ".323"),
                StandardStat(id: "std-OBP", label: "OBP", value: ".396"),
                StandardStat(id: "std-HR", label: "HR", value: "30")
            ],
            games: []
        )
    ]
}
