import Foundation

/// True when a thrown error is only this task being cancelled.
///
/// Every card in the app loads inside a `.task(id:)`, which cancels the moment
/// its id changes: a tab switch, a window flip, a season change. URLSession
/// reports that as `URLError.cancelled` rather than `CancellationError`, so a
/// plain `catch` can't tell an interrupted load from a failed one. That's what
/// put "Couldn't load team form" on screen for anyone who tapped between the
/// Trends and Teams tabs faster than a fetch could finish: nothing had failed,
/// the answer had just been superseded by the one they asked for next.
func isTaskCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}

protocol StatcastProviding: Sendable {
    func fetchPlayers() async throws -> [Player]
    func fetchHistoricalPlayers() async throws -> [Player]
    func fetchCurrentPlayers() async throws -> [Player]
    func fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase) async throws -> [PlayerGameLog]
    func fetchTeamGameLogs(
        team: String,
        season: Int,
        sinceDate: Date,
        phase: SeasonPhase
    ) async throws -> [PlayerGameLog]
    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm]
    /// The last game day the pipeline has actually closed out. See
    /// `DashboardViewModel.dataThrough` for why a write timestamp isn't enough.
    func fetchDataThroughDate(season: Int) async throws -> Date?
    /// The newest postseason game the pipeline holds for a season, or nil if the
    /// playoffs haven't started (or haven't been ingested yet).
    ///
    /// This is what wakes the postseason card. A calendar date would fire it
    /// while the boards behind it were still empty: the pipeline closes out a
    /// day once, overnight, so the first Wild Card game isn't readable until
    /// the following morning.
    func fetchPostseasonThroughDate(season: Int) async throws -> Date?
    /// Postseason player lines, including percentile bars mapped to the current
    /// regular-season curves. Savant does not publish postseason percentile
    /// leaderboards, so the UI must identify the reference season.
    func fetchPostseasonPlayers(season: Int) async throws -> [Player]
}

extension StatcastProviding {
    /// Regular season is what every existing caller means.
    func fetchGameLogs(playerId: Int, season: Int) async throws -> [PlayerGameLog] {
        try await fetchGameLogs(playerId: playerId, season: season, phase: .regular)
    }

    func fetchTeamGameLogs(team: String, season: Int, sinceDate: Date) async throws -> [PlayerGameLog] {
        try await fetchTeamGameLogs(team: team, season: season, sinceDate: sinceDate, phase: .regular)
    }
}

struct StatcastAPI: StatcastProviding {
    private let baseURL: URL
    private let apiKey: String

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func fetchPlayers() async throws -> [Player] {
        let historical = try await fetchHistoricalPlayers()
        let current = try await fetchCurrentPlayers()
        return historical + current
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        try await fetchPlayers(seasonFilter: "lt.\(StatScoutSeason.current)")
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        try await fetchPlayers(seasonFilter: "eq.\(StatScoutSeason.current)")
    }

    /// The two phases live in different tables, which is what keeps a playoff
    /// game out of a regular-season window on builds that predate this one.
    private func gameLogTable(for phase: SeasonPhase) -> String {
        switch phase {
        case .regular:    return "player_game_logs"
        case .postseason: return "player_postseason_game_logs"
        }
    }

    func fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase) async throws -> [PlayerGameLog] {
        let endpoint = baseURL
            .appending(path: "rest/v1/\(gameLogTable(for: phase))")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "player_id", value: "eq.\(playerId)"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "order", value: "game_date.desc"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data)
        return rows.compactMap(\.value)
    }

    func fetchTeamGameLogs(
        team: String,
        season: Int,
        sinceDate: Date,
        phase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let sinceString = formatter.string(from: sinceDate)

        var all: [PlayerGameLog] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/\(gameLogTable(for: phase))")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "team", value: "eq.\(team)"),
                    URLQueryItem(name: "season", value: "eq.\(season)"),
                    URLQueryItem(name: "game_date", value: "gte.\(sinceString)"),
                    URLQueryItem(name: "order", value: "game_date.desc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ])
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data)
            let page = rows.compactMap(\.value)
            all.append(contentsOf: page)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    /// Every player's rolling window for one length, the whole league in a
    /// single small fetch (~440 KB), which is what makes ranking by recent form
    /// viable at all. Aggregating the raw game logs client-side would be ~2.4 MB
    /// and a multi-second wait before anything could be sorted.
    func fetchRecentForm(season: Int, windowDays: Int) async throws -> [RecentForm] {
        var all: [RecentForm] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/player_recent_form")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "season", value: "eq.\(season)"),
                    URLQueryItem(name: "window_days", value: "eq.\(windowDays)"),
                    URLQueryItem(name: "order", value: "player_id.asc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ])
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<RecentForm>].self, from: data)
            all.append(contentsOf: rows.compactMap(\.value))
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    /// One row, one column: the newest `as_of` in the rolling-window table.
    ///
    /// Settings used to report only when the pipeline last wrote rows, which is
    /// "today" even on a night that found no new games to close out — so it read
    /// as fresh while the Trends board still said "Through Jul 27". This is the
    /// number both screens can agree on.
    func fetchDataThroughDate(season: Int) async throws -> Date? {
        struct CoverageRow: Decodable {
            let asOf: String?

            enum CodingKeys: String, CodingKey {
                case asOf = "as_of"
            }
        }

        let endpoint = baseURL
            .appending(path: "rest/v1/player_recent_form")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "as_of"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "order", value: "as_of.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([CoverageRow].self, from: data)
        guard let raw = rows.first?.asOf else { return nil }
        return Date.fromPostgresDate(raw)
    }

    func fetchPostseasonThroughDate(season: Int) async throws -> Date? {
        struct Row: Decodable {
            let gameDate: String?

            enum CodingKeys: String, CodingKey {
                case gameDate = "game_date"
            }
        }

        let endpoint = baseURL
            .appending(path: "rest/v1/player_postseason_game_logs")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "game_date"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "order", value: "game_date.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard let raw = rows.first?.gameDate else { return nil }
        return Date.fromPostgresDate(raw)
    }

    func fetchPostseasonPlayers(season: Int) async throws -> [Player] {
        var all: [Player] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/player_postseason_stats")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "season", value: "eq.\(season)"),
                    URLQueryItem(name: "order", value: "id.asc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ])
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<Player>].self, from: data)
            all.append(contentsOf: rows.compactMap(\.value))
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    private func fetchPlayers(seasonFilter: String) async throws -> [Player] {
        var all: [Player] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/player_snapshots")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "season", value: seasonFilter),
                    // Stable key so offset paging can't skip/duplicate rows when
                    // updated_at changes mid-fetch.
                    URLQueryItem(name: "order", value: "id.asc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset))
                ])
            // Bypass URLCache so the shared headshot cache can't serve a stale page.
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<Player>].self, from: data)
            let page = rows.compactMap(\.value)
            // A non-empty page that decodes to zero players means the schema
            // changed under us, surface it instead of silently going blank.
            if !rows.isEmpty && page.isEmpty {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "All player rows failed to decode")
                )
            }
            all.append(contentsOf: page)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }
}

/// Decodes an element if possible, otherwise yields nil instead of throwing,
/// so one malformed row can't fail the entire page.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

#if DEBUG
struct PreviewStatcastAPI: StatcastProviding {
    func fetchPlayers() async throws -> [Player] {
        SampleData.players
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) < StatScoutSeason.current }
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) >= StatScoutSeason.current }
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
        []
    }

    func fetchDataThroughDate(season: Int) async throws -> Date? {
        nil
    }

    func fetchPostseasonThroughDate(season: Int) async throws -> Date? {
        nil
    }

    func fetchPostseasonPlayers(season: Int) async throws -> [Player] {
        []
    }
}
#endif

extension JSONDecoder {
    static var statScout: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return decoder
    }
}
