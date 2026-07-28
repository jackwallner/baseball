import Foundation

/// A metric the Trends board can rank by.
///
/// Keyed to the game-log / rollup column rather than the season metric label,
/// because Trends reads `player_recent_form` directly and never touches the
/// season snapshot.
struct TrendMetric: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    /// Suffix appended to a value, e.g. "%" or " mph". Empty for rate stats.
    let unit: String
    /// Also drives the delta formatting on the row.
    let decimals: Int
    /// True where a falling number is the improvement: a hitter's chase rate,
    /// anything a pitcher gives up.
    let lowerIsBetter: Bool

    var id: String { key }

    func format(_ value: Double) -> String {
        let text = String(format: "%.\(decimals)f", value)
        // Savant writes rate stats without the leading zero (.312, not 0.312).
        return (decimals == 3 ? text.replacingOccurrences(of: "0.", with: ".") : text) + unit
    }

    /// The traditional line, which the rollup derives from summed counts rather
    /// than by averaging per-game rates. Kept in its own group because it
    /// answers a different question from the Statcast metrics: what actually
    /// happened, not what the contact quality deserved.
    static let battingStandard: [TrendMetric] = [
        .init(key: "avg", label: "AVG", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "obp", label: "OBP", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "slg", label: "SLG", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "ops", label: "OPS", unit: "", decimals: 3, lowerIsBetter: false),
    ]

    /// Same four, read as what the pitcher allowed, so every one of them is
    /// better going down.
    static let pitchingStandard: [TrendMetric] = [
        .init(key: "avg", label: "AVG Against", unit: "", decimals: 3, lowerIsBetter: true),
        .init(key: "obp", label: "OBP Against", unit: "", decimals: 3, lowerIsBetter: true),
        .init(key: "slg", label: "SLG Against", unit: "", decimals: 3, lowerIsBetter: true),
        .init(key: "ops", label: "OPS Against", unit: "", decimals: 3, lowerIsBetter: true),
    ]

    static let batting: [TrendMetric] = [
        .init(key: "xwoba", label: "xwOBA", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "xba", label: "xBA", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "xslg", label: "xSLG", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "xiso", label: "xISO", unit: "", decimals: 3, lowerIsBetter: false),
        .init(key: "barrel_pct", label: "Barrel%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "hardhit_pct", label: "Hard-Hit%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "sweetspot_pct", label: "Sweet-Spot%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "ev_avg", label: "Exit Velo", unit: " mph", decimals: 1, lowerIsBetter: false),
        .init(key: "bat_speed", label: "Bat Speed", unit: " mph", decimals: 1, lowerIsBetter: false),
        .init(key: "bb_pct", label: "BB%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "k_pct", label: "K%", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "whiff_pct", label: "Whiff%", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "chase_pct", label: "Chase%", unit: "%", decimals: 1, lowerIsBetter: true),
    ]

    /// A pitcher's line is what the opposition did, so almost all of it reads
    /// backwards from the hitter's.
    static let pitching: [TrendMetric] = [
        .init(key: "opp_xwoba", label: "xwOBA Against", unit: "", decimals: 3, lowerIsBetter: true),
        .init(key: "opp_xba", label: "xBA Against", unit: "", decimals: 3, lowerIsBetter: true),
        .init(key: "opp_xslg", label: "xSLG Against", unit: "", decimals: 3, lowerIsBetter: true),
        .init(key: "k_pct", label: "K%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "whiff_pct", label: "Whiff%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "chase_pct", label: "Chase%", unit: "%", decimals: 1, lowerIsBetter: false),
        .init(key: "bb_pct", label: "BB%", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "opp_barrel_pct", label: "Barrel% Against", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "opp_hardhit_pct", label: "Hard-Hit% Against", unit: "%", decimals: 1, lowerIsBetter: true),
        .init(key: "opp_ev_avg", label: "Exit Velo Against", unit: " mph", decimals: 1, lowerIsBetter: true),
        .init(key: "fb_velo_avg", label: "Fastball Velo", unit: " mph", decimals: 1, lowerIsBetter: false),
        .init(key: "fb_spin_avg", label: "Fastball Spin", unit: " rpm", decimals: 0, lowerIsBetter: false),
        .init(key: "gb_pct", label: "Ground-Ball%", unit: "%", decimals: 1, lowerIsBetter: false),
    ]

    static func statcast(for side: TrendSide) -> [TrendMetric] {
        side == .pitching ? pitching : batting
    }

    static func standard(for side: TrendSide) -> [TrendMetric] {
        side == .pitching ? pitchingStandard : battingStandard
    }

    /// Statcast metrics first, then the traditional line, in one list, the
    /// picker groups them into sections rather than making the user pick a
    /// mode before picking a stat.
    static func list(for side: TrendSide) -> [TrendMetric] {
        statcast(for: side) + standard(for: side)
    }
}

/// Which side of the ball the Trends board is ranking. Mixing them was never an
/// option: the same key means opposite things to a hitter and a pitcher.
enum TrendSide: String, CaseIterable, Identifiable, Sendable {
    case batting
    case pitching

    var id: String { rawValue }
    var label: String { self == .batting ? "Hitting" : "Pitching" }
    /// Matches `player_recent_form.player_type`.
    var playerType: String { self == .batting ? "batter" : "pitcher" }
}
