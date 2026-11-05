#if DEBUG
import Foundation

/// Offline store captures use the app's bundled demo players and rolling-form rows.
struct ScreenshotFixtureAPI: StatcastProviding {
    private static let playerIDOverrides = [1: 592450, 669203: 677951]

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-StoreScreenshotData")
    }

    private var players: [Player] {
        SampleData.players.map { player in
            guard let playerId = Self.playerIDOverrides[player.playerId] else { return player }
            return Player(
                playerId: playerId,
                name: player.name,
                team: player.team,
                position: player.position,
                handedness: player.handedness,
                imageURL: player.imageURL,
                updatedAt: player.updatedAt,
                season: player.season,
                playerType: player.playerType,
                source: player.source,
                metrics: player.metrics,
                standardStats: player.standardStats,
                games: player.games
            )
        }
    }

    func fetchPlayers() async throws -> [Player] {
        players
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        []
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        players
    }

    func fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase) async throws -> [PlayerGameLog] {
        []
    }

    func fetchTeamGameLogs(
        team: String,
        season: Int,
        sinceDate: Date,
        phase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        []
    }

    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm] {
        let rows: [[String: Any]] = players.enumerated().compactMap { index, player in
            guard player.season == season else { return nil }
            let label = player.metrics.first(where: { $0.label == "xwOBA" })?.value
                ?? player.metrics.first(where: { $0.label == "xBA" })?.value
                ?? player.metrics.first(where: { $0.label == "xSLG" })?.value
                ?? ".300"
            let value = Double(label.replacingOccurrences(of: "%", with: "")) ?? 0.300
            let delta = 0.010 + Double(index % 4) * 0.004
            let pitcher = player.position.uppercased().contains("P")
            return [
                "player_id": player.playerId,
                "season": season,
                "player_type": pitcher ? "pitcher" : "batter",
                "window_days": windowDays,
                "team": player.team,
                "games": 12,
                "plate_appearances": 60,
                "batted_ball_events": 40,
                "metrics": ["xwoba": value],
                "prior_metrics": ["xwoba": value - delta],
                "delta": ["xwoba": delta],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: rows)
        return try JSONDecoder.statScout.decode([RecentForm].self, from: data)
    }

    func fetchDataThroughDate(season: Int) async throws -> Date? { nil }

    func fetchPostseasonThroughDate(season: Int) async throws -> Date? { nil }

    func fetchPostseasonPlayers(season: Int) async throws -> [Player] { [] }
}
#endif
