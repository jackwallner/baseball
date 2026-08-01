import Foundation

extension Date {
    /// Parses a Postgres `date` column ("YYYY-MM-DD").
    ///
    /// These arrive with no time and no zone, so they can't go through the
    /// ISO8601 decoding strategy the rest of the payload uses. Anchoring them
    /// at local midnight is what makes "Through Jul 28" mean the same calendar
    /// day the pipeline closed out, whatever zone the reader is in.
    static func fromPostgresDate(_ raw: String) -> Date? {
        let bits = raw.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var parts = DateComponents()
        parts.year = bits[0]
        parts.month = bits[1]
        parts.day = bits[2]
        return Calendar.current.date(from: parts)
    }
}

/// One player's rolling window, as stored in `public.player_recent_form`.
///
/// Mirrors Baseball Savant's rolling leaderboard shape: the current window,
/// the equal-length window immediately before it, and the change between them.
/// The delta is the interesting column, a .380 xwOBA means more when you can
/// see it was .250 a fortnight ago.
struct RecentForm: Codable, Hashable, Sendable, Identifiable {
    let playerId: Int
    let season: Int
    let playerType: String
    let windowDays: Int
    /// Last game date included. Lets the UI say "through Jul 24" rather than
    /// implying the window runs to today when the pipeline is a day behind.
    let asOf: Date?
    let team: String?
    let games: Int
    let plateAppearances: Int
    let battedBallEvents: Int
    let metrics: [String: Double]
    let priorMetrics: [String: Double]
    let delta: [String: Double]

    var id: String { "\(playerId)-\(playerType)-\(windowDays)" }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case playerType = "player_type"
        case windowDays = "window_days"
        case asOf = "as_of"
        case team
        case games
        case plateAppearances = "plate_appearances"
        case battedBallEvents = "batted_ball_events"
        case metrics
        case priorMetrics = "prior_metrics"
        case delta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        playerType = try c.decode(String.self, forKey: .playerType)
        windowDays = try c.decode(Int.self, forKey: .windowDays)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        plateAppearances = try c.decodeIfPresent(Int.self, forKey: .plateAppearances) ?? 0
        battedBallEvents = try c.decodeIfPresent(Int.self, forKey: .battedBallEvents) ?? 0

        // as_of is a Postgres `date`, so it arrives as "YYYY-MM-DD" and won't
        // parse with the ISO8601 strategy the rest of the payload uses.
        if let raw = try c.decodeIfPresent(String.self, forKey: .asOf) {
            asOf = Date.fromPostgresDate(raw)
        } else {
            asOf = nil
        }

        // Null metric values mean "no data in this window" (see the rollup's
        // omit-rather-than-zero rule), so they're dropped rather than coerced.
        func numbers(_ key: CodingKeys) -> [String: Double] {
            guard let raw = try? c.decodeIfPresent([String: Double?].self, forKey: key) else { return [:] }
            return raw.compactMapValues { $0 }
        }
        metrics = numbers(.metrics)
        priorMetrics = numbers(.priorMetrics)
        delta = numbers(.delta)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(season, forKey: .season)
        try c.encode(playerType, forKey: .playerType)
        try c.encode(windowDays, forKey: .windowDays)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encode(games, forKey: .games)
        try c.encode(plateAppearances, forKey: .plateAppearances)
        try c.encode(battedBallEvents, forKey: .battedBallEvents)
        try c.encode(metrics, forKey: .metrics)
        try c.encode(priorMetrics, forKey: .priorMetrics)
        try c.encode(delta, forKey: .delta)
    }

    /// Small samples make wild deltas. Below this the UI still shows the numbers
    /// but tags them, matching the Recent Form card's existing convention.
    var isSmallSample: Bool {
        plateAppearances < (playerType == "pitcher" ? 30 : 15)
    }
}

/// Season metric label ↔ the rolling rollup's column for it, plus the one
/// formatter for a window value.
///
/// The leaderboard, the team roster and the team cards all need to ask "what
/// is this player's xwOBA over the last 15 days"; each had grown its own
/// private copy of the mapping, which is how a metric ends up trending on one
/// screen and blank on the next.
enum RecentMetricKey {
    /// Pitcher rows read the opponent-facing variants, a pitcher's xwOBA is
    /// what hitters managed against him.
    static func key(for label: String, isPitcher: Bool) -> String {
        switch label {
        case "xwOBA": return isPitcher ? "opp_xwoba" : "xwoba"
        case "xBA": return isPitcher ? "opp_xba" : "xba"
        case "xSLG": return isPitcher ? "opp_xslg" : "xslg"
        case "xISO": return "xiso"
        case "Barrel%": return isPitcher ? "opp_barrel_pct" : "barrel_pct"
        case "Hard-Hit%": return isPitcher ? "opp_hardhit_pct" : "hardhit_pct"
        case "Sweet-Spot%": return "sweetspot_pct"
        case "EV", "Avg EV Against": return isPitcher ? "opp_ev_avg" : "ev_avg"
        case "Max EV", "Max EV Against": return isPitcher ? "opp_ev_max" : "ev_max"
        case "K%": return "k_pct"
        case "BB%": return "bb_pct"
        case "Whiff%": return "whiff_pct"
        case "Chase%": return "chase_pct"
        case "Bat Speed": return "bat_speed"
        case "Swing Length": return "swing_length"
        case "Fastball Velo": return "fb_velo_avg"
        case "Fastball Spin": return "fb_spin_avg"
        default: return label.lowercased()
        }
    }

    /// How many decimals the metric's delta moves in. Rate stats are thousandths,
    /// percentages and speeds are tenths, spin is whole rpm.
    static func decimals(for label: String) -> Int {
        if label.hasSuffix("Spin") { return 0 }
        if label.hasSuffix("%") { return 1 }
        if label.contains("EV") || label.contains("Velo") || label == "Bat Speed" { return 1 }
        return 3
    }

    /// Matches the player page's conventions, Savant writes rate stats without
    /// the leading zero, and a speed carries its unit.
    static func format(_ value: Double, label: String) -> String {
        if label.hasSuffix("%") { return String(format: "%.1f%%", value) }
        if label.hasSuffix("Spin") { return String(format: "%.0f", value) }
        if label == "Swing Length" { return String(format: "%.2f", value) }
        if label.contains("EV") || label.contains("Velo") || label == "Bat Speed" {
            return String(format: "%.1f", value)
        }
        if value < 10 {
            return String(format: "%.3f", value).replacingOccurrences(of: "0.", with: ".")
        }
        return String(format: "%.1f", value)
    }
}

/// Which rolling window is on screen. Mirrors `RecentFormWindow.windows` so the
/// per-player card and the league leaderboard offer the same choices.
enum RecentWindow: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case fortnight = 15
    case month = 30

    var id: Int { rawValue }
    /// Always says "days". The window is calendar days, not games, and "Last
    /// 15" beside a row that also reports a game count ("· 12G") read as
    /// fifteen *games* to everyone who wasn't the person who wrote it.
    var label: String { "Last \(rawValue) days" }
    /// Segment-width version of the same wording: still explicit about the
    /// unit, short enough for three of them across a phone.
    var segmentLabel: String { "\(rawValue) days" }
    var shortLabel: String { "\(rawValue)d" }
}

/// How much playing time inside a rolling window a player needs before the
/// Trends board will rank him.
///
/// Expressed as a rate per window day rather than a flat count, because the flat
/// count `isSmallSample` uses means two different things depending on which
/// window is showing: 15 PA over seven days is an everyday hitter, 15 PA over
/// thirty is a bench bat whose one hot week produces a delta big enough to bury
/// every real riser. The rate keeps "Regulars" meaning the same thing on all
/// three boards.
enum TrendQualifier: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case sample = "Min Sample"
    case regulars = "Regulars"

    var id: String { rawValue }

    /// Plate appearances per window day for a hitter. A pitcher's equivalent is
    /// batters faced, which `RecentForm.plateAppearances` already holds for a
    /// pitcher row, and he faces more of them per appearance than a hitter gets
    /// trips to the plate.
    private var battingRate: Double {
        switch self {
        case .all: return 0
        case .sample: return 1
        case .regulars: return 2.5
        }
    }

    private var pitchingRate: Double {
        switch self {
        case .all: return 0
        case .sample: return 2
        case .regulars: return 4
        }
    }

    func minimum(isPitcher: Bool, windowDays: Int) -> Int {
        Int(((isPitcher ? pitchingRate : battingRate) * Double(windowDays)).rounded())
    }

    func admits(_ form: RecentForm, windowDays: Int) -> Bool {
        guard self != .all else { return true }
        return form.plateAppearances >= minimum(
            isPitcher: form.playerType == "pitcher",
            windowDays: windowDays
        )
    }

    /// Spells the active threshold out in the window's own numbers, so "Min
    /// Sample" and "Regulars" don't read as synonyms.
    func description(isPitcher: Bool, windowDays: Int) -> String {
        guard self != .all else { return "No minimum" }
        return "\(minimum(isPitcher: isPitcher, windowDays: windowDays))+ \(isPitcher ? "BF" : "PA")"
    }
}
