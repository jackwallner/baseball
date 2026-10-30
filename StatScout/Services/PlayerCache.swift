import Foundation

protocol PlayerCaching: Sendable {
    func loadPlayers() throws -> [Player]
    func savePlayers(_ players: [Player]) throws
}

struct DiskPlayerCache: PlayerCaching {
    let fileURL: URL
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

/// Two-tier cache: the bundled history for past seasons, an expiring disk
/// copy for the current season.
struct TwoTierPlayerCache: PlayerCaching {
    private let directory: URL
    private let current: DiskPlayerCache
    private let bundle: Bundle
    private let bundleResourceName: String

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        bundle: Bundle = .main,
        bundleResourceName: String = "players-historical"
    ) {
        let directory = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory
        self.current = DiskPlayerCache(fileURL: directory.appending(path: "players-current.json"), maxAge: 48 * 60 * 60)
        self.bundle = bundle
        self.bundleResourceName = bundleResourceName
    }

    /// Copies of the bundle that older builds kept in Caches.
    private var staleHistoricalCopies: [URL] {
        [
            directory.appending(path: "players-historical.plist"),
            directory.appending(path: "players-historical.json"),
        ]
    }

    func loadPlayers() throws -> [Player] {
        let historicalPlayers = loadHistoricalPlayers()
        let currentPlayers = (try? current.loadPlayers()) ?? []
        return historicalPlayers + currentPlayers
    }

    func loadCurrentPlayers() throws -> [Player] {
        try current.loadPlayers()
    }

    /// Past seasons, read straight from the app bundle every time.
    ///
    /// Older builds copied the bundle into Caches on first launch and read
    /// that copy back first from then on, so a new bundle never reached an
    /// existing install: at the next rollover the season just finished would
    /// have dropped out of every board. The copy decoded no faster than the
    /// bundle, so it goes, along with the legacy JSON one.
    func loadHistoricalPlayers() -> [Player] {
        for url in staleHistoricalCopies {
            try? FileManager.default.removeItem(at: url)
        }
        guard let bundleURL = bundle.url(forResource: bundleResourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: bundleURL),
              let players = try? PropertyListDecoder.statScout.decode([Player].self, from: data) else {
            return []
        }
        return players
    }

    func savePlayers(_ players: [Player]) throws {
        // Past seasons come from the bundle, so only the live season is kept.
        let currentPlayers = players.filter { ($0.season ?? 0) >= StatScoutSeason.current }
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

extension PropertyListEncoder {
    static var statScout: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}

extension PropertyListDecoder {
    /// Conversion script stores dates as native plist Date values, so default decoding works.
    static var statScout: PropertyListDecoder { PropertyListDecoder() }
}
