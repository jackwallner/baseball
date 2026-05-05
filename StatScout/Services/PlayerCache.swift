import Foundation

protocol PlayerCaching: Sendable {
    func loadPlayers() throws -> [Player]
    func savePlayers(_ players: [Player]) throws
}

struct DiskPlayerCache: PlayerCaching {
    private let fileURL: URL
    private let maxAge: TimeInterval?

    /// Pass `nil` for maxAge to disable expiration (permanent cache).
    init(fileManager: FileManager = .default, maxAge: TimeInterval? = 48 * 60 * 60) {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.fileURL = directory.appending(path: "players-cache.json")
        self.maxAge = maxAge
    }

    init(fileURL: URL, maxAge: TimeInterval? = 48 * 60 * 60) {
        self.fileURL = fileURL
        self.maxAge = maxAge
    }

    func loadPlayers() throws -> [Player] {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let maxAge = maxAge,
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > maxAge {
            throw URLError(.resourceUnavailable)
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.statScout.decode([Player].self, from: data)
    }

    func savePlayers(_ players: [Player]) throws {
        let data = try JSONEncoder.statScout.encode(players)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Two-tier cache: permanent for historical data, expiring for current season.
struct TwoTierPlayerCache: PlayerCaching {
    private let historical: DiskPlayerCache
    private let current: DiskPlayerCache
    private let bundleResourceName: String

    init(fileManager: FileManager = .default, bundleResourceName: String = "players-historical") {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.historical = DiskPlayerCache(fileURL: directory.appending(path: "players-historical.json"), maxAge: nil)
        self.current = DiskPlayerCache(fileURL: directory.appending(path: "players-current.json"), maxAge: 48 * 60 * 60)
        self.bundleResourceName = bundleResourceName
    }

    func loadPlayers() throws -> [Player] {
        let historicalPlayers = loadHistoricalPlayers()
        let currentPlayers = (try? current.loadPlayers()) ?? []
        return historicalPlayers + currentPlayers
    }

    private func loadHistoricalPlayers() -> [Player] {
        // 1. Try the permanent disk cache first.
        if let cached = try? historical.loadPlayers(), !cached.isEmpty {
            return cached
        }
        // 2. First install: seed from the bundled JSON shipped with the app.
        guard let bundleURL = Bundle.main.url(forResource: bundleResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: bundleURL),
              let players = try? JSONDecoder.statScout.decode([Player].self, from: data),
              !players.isEmpty else {
            return []
        }
        // Persist to disk cache so future launches are instant.
        try? historical.savePlayers(players)
        return players
    }

    func savePlayers(_ players: [Player]) throws {
        let historicalPlayers = players.filter { ($0.season ?? 0) < 2026 }
        let currentPlayers = players.filter { ($0.season ?? 0) >= 2026 }
        if !historicalPlayers.isEmpty {
            try historical.savePlayers(historicalPlayers)
        }
        if !currentPlayers.isEmpty {
            try current.savePlayers(currentPlayers)
        }
    }
}

extension JSONEncoder {
    static var statScout: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
