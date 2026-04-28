import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let team: String
    let position: String
    let handedness: String
    let imageURL: URL?
    let updatedAt: Date
    let season: Int? = nil
    let playerType: String? = nil
    let source: String? = nil
    let metrics: [Metric]
    let standardStats: [StandardStat]
    let games: [GameTrend]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case team
        case position
        case handedness
        case imageURL = "image_url"
        case updatedAt = "updated_at"
        case season
        case playerType = "player_type"
        case source
        case metrics
        case standardStats = "standard_stats"
        case games
    }

    var overallPercentile: Int {
        guard !metrics.isEmpty else { return 0 }
        let total = metrics.map(\.percentile).reduce(0, +)
        return Int(round(Double(total) / Double(metrics.count)))
    }

    var headlineMetric: Metric? {
        metrics.sorted { $0.percentile > $1.percentile }.first
    }

    var latestGame: GameTrend? {
        games.sorted { $0.date > $1.date }.first
    }

    var latestPercentileDelta: Int {
        latestGame?.percentileDelta ?? 0
    }

    var weeklyDelta: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return games.filter { $0.date >= cutoff }
            .map(\.percentileDelta)
            .reduce(0, +)
    }

    var shareSummary: String {
        let topSignal = headlineMetric.map { metric in
            let valueText = metric.value.isEmpty ? "\(metric.percentile.ordinal) percentile" : "\(metric.value), \(metric.percentile.ordinal) percentile"
            return "\(metric.label) \(valueText)"
        } ?? "\(overallPercentile.ordinal) overall percentile"
        return "\(name) · \(team) \(position)\nOverall: \(overallPercentile.ordinal) percentile\nTop signal: \(topSignal)\nStatScout"
    }

    func percentile(for category: MetricCategory) -> Int? {
        let categoryMetrics = metrics.filter { $0.category == category }
        guard !categoryMetrics.isEmpty else { return nil }
        let total = categoryMetrics.map(\.percentile).reduce(0, +)
        return Int(round(Double(total) / Double(categoryMetrics.count)))
    }
}

struct Metric: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    let percentile: Int
    let category: MetricCategory
}

struct StandardStat: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
}

enum MetricDirection: String, Codable, Hashable, Sendable {
    case up
    case flat
    case down
}

enum MetricCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case hitting = "Hitting"
    case pitching = "Pitching"
    case fielding = "Fielding"
    case running = "Running"
}

struct TeamRoute: Hashable {
    let abbr: String
    let players: [Player]
}

extension Player {
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
    var headshotURL: URL? {
        imageURL ?? URL(string: "https://midfield.mlbstatic.com/v1/people/\(id)/spots/240")
    }
}

struct GameTrend: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let date: Date
    let opponent: String
    let summary: String
    let percentileDelta: Int
    let keyMetric: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case opponent
        case summary
        case percentileDelta = "percentile_delta"
        case keyMetric = "key_metric"
    }
}
