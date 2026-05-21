import Foundation

/// One player's contribution in one game on one side of the ball (a two-way
/// player has separate batter / pitcher rows). Powers the Recent Form card.
struct PlayerGameLog: Codable, Hashable, Sendable {
    let playerId: Int
    let season: Int
    let gameDate: Date
    let playerType: String
    let team: String?
    let opponent: String?
    let plateAppearances: Int
    let battedBallEvents: Int
    let metrics: [String: Double?]

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case gameDate = "game_date"
        case playerType = "player_type"
        case team
        case opponent
        case plateAppearances = "plate_appearances"
        case battedBallEvents = "batted_ball_events"
        case metrics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        playerType = try c.decode(String.self, forKey: .playerType)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        opponent = try c.decodeIfPresent(String.self, forKey: .opponent)
        plateAppearances = try c.decode(Int.self, forKey: .plateAppearances)
        battedBallEvents = try c.decode(Int.self, forKey: .battedBallEvents)

        // game_date arrives as "YYYY-MM-DD" from Supabase (date column, not timestamptz).
        let raw = try c.decode(String.self, forKey: .gameDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        guard let parsed = formatter.date(from: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .gameDate, in: c, debugDescription: "Invalid game_date: \(raw)")
        }
        gameDate = parsed

        // metrics is a JSONB object with nullable numeric values.
        if let dict = try? c.decode([String: Double?].self, forKey: .metrics) {
            metrics = dict
        } else {
            metrics = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(season, forKey: .season)
        try c.encode(playerType, forKey: .playerType)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encodeIfPresent(opponent, forKey: .opponent)
        try c.encode(plateAppearances, forKey: .plateAppearances)
        try c.encode(battedBallEvents, forKey: .battedBallEvents)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        try c.encode(formatter.string(from: gameDate), forKey: .gameDate)
        try c.encode(metrics, forKey: .metrics)
    }
}

/// Aggregated stats over a window (last 7/15/30 days).
struct RecentFormWindow {
    let label: String
    let days: Int
    let games: Int
    let plateAppearances: Int
    let battedBallEvents: Int
    /// Mean-of-means weighted by PA — close enough to a real recompute for
    /// rate stats like xwOBA. For per-game rate metrics (K%, BB%) this is a
    /// weighted average across games and is what users expect to see.
    let metrics: [String: Double]

    static let windows: [(label: String, days: Int)] = [
        ("Last 7", 7),
        ("Last 15", 15),
        ("Last 30", 30),
    ]

    /// Build a window from per-game logs filtered to a date range. Per-game
    /// rates are weighted by PA (or BBE for batted-ball-only metrics) to
    /// approximate a true recompute without re-aggregating pitch-level data.
    static func build(label: String, days: Int, logs: [PlayerGameLog]) -> RecentFormWindow {
        let pa = logs.reduce(0) { $0 + $1.plateAppearances }
        let bbe = logs.reduce(0) { $0 + $1.battedBallEvents }

        var combined: [String: Double] = [:]
        let allKeys = Set(logs.flatMap { $0.metrics.keys })

        for key in allKeys {
            let weight = Self.weight(for: key)
            var numer = 0.0
            var denom = 0.0
            for log in logs {
                guard let value = log.metrics[key] ?? nil else { continue }
                let w: Double
                switch weight {
                case .pa: w = Double(log.plateAppearances)
                case .bbe: w = Double(log.battedBallEvents)
                }
                guard w > 0 else { continue }
                numer += value * w
                denom += w
            }
            if denom > 0 {
                combined[key] = numer / denom
            }
        }

        return RecentFormWindow(
            label: label,
            days: days,
            games: logs.count,
            plateAppearances: pa,
            battedBallEvents: bbe,
            metrics: combined
        )
    }

    private enum Weight { case pa, bbe }

    /// Which denominator a metric is naturally a rate of. EV / HardHit% /
    /// Barrel% are per-BBE; everything else is per-PA.
    private static func weight(for key: String) -> Weight {
        switch key {
        case "ev_avg", "ev_max", "hardhit_pct", "barrel_pct",
             "opp_ev_avg", "opp_hardhit_pct", "opp_barrel_pct":
            return .bbe
        default:
            return .pa
        }
    }
}
