import Foundation

protocol PlayerCaching: Sendable {
    func loadPlayers() throws -> [Player]
    func savePlayers(_ players: [Player]) throws
}

struct DiskPlayerCache: PlayerCaching {
    private let fileURL: URL
    private let maxAge: TimeInterval

    init(fileManager: FileManager = .default, maxAge: TimeInterval = 6 * 60 * 60) {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.fileURL = directory.appending(path: "players-cache.json")
        self.maxAge = maxAge
    }

    init(fileURL: URL, maxAge: TimeInterval = 6 * 60 * 60) {
        self.fileURL = fileURL
        self.maxAge = maxAge
    }

    func loadPlayers() throws -> [Player] {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let modified = attributes[.modificationDate] as? Date, Date().timeIntervalSince(modified) > maxAge {
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

extension JSONEncoder {
    static var statScout: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
