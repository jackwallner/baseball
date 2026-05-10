import Foundation

protocol StatcastProviding: Sendable {
    func fetchPlayers() async throws -> [Player]
    func fetchHistoricalPlayers() async throws -> [Player]
    func fetchCurrentPlayers() async throws -> [Player]
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
        try await fetchPlayers(seasonFilter: "lt.2026")
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        try await fetchPlayers(seasonFilter: "eq.2026")
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
                    URLQueryItem(name: "order", value: "updated_at.desc"),
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

            let page = try JSONDecoder.statScout.decode([Player].self, from: data)
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return all
    }
}

#if DEBUG
struct PreviewStatcastAPI: StatcastProviding {
    func fetchPlayers() async throws -> [Player] {
        SampleData.players
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) < 2026 }
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) >= 2026 }
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
