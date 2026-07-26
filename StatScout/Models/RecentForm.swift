import Foundation

/// One player's rolling window, as stored in `public.player_recent_form`.
///
/// Mirrors Baseball Savant's rolling leaderboard shape: the current window,
/// the equal-length window immediately before it, and the change between them.
/// The delta is the interesting column — a .380 xwOBA means more when you can
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
            var parts = DateComponents()
            let bits = raw.split(separator: "-").compactMap { Int($0) }
            if bits.count == 3 {
                parts.year = bits[0]; parts.month = bits[1]; parts.day = bits[2]
                asOf = Calendar.current.date(from: parts)
            } else {
                asOf = nil
            }
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

/// Which rolling window is on screen. Mirrors `RecentFormWindow.windows` so the
/// per-player card and the league leaderboard offer the same choices.
enum RecentWindow: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case fortnight = 15
    case month = 30

    var id: Int { rawValue }
    var label: String { "Last \(rawValue)" }
    var shortLabel: String { "\(rawValue)d" }
}
