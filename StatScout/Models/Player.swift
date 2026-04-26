import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let team: String
    let position: String
    let handedness: String
    let imageURL: URL?
    let updatedAt: Date
    let metrics: [Metric]
    let games: [GameTrend]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case team
        case position
        case handedness
        case imageURL = "image_url"
        case updatedAt = "updated_at"
        case metrics
        case games
    }

    var overallPercentile: Int {
        guard !metrics.isEmpty else { return 0 }
        return metrics.map(\.percentile).reduce(0, +) / metrics.count
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

    var shareSummary: String {
        let topSignal = headlineMetric.map { "\($0.label) \($0.value), \($0.percentile.ordinal) percentile" } ?? "\(overallPercentile.ordinal) overall percentile"
        return "\(name) · \(team) \(position)\nOverall: \(overallPercentile.ordinal) percentile\nTop signal: \(topSignal)\nStatScout"
    }

    func percentile(for category: MetricCategory) -> Int? {
        let categoryMetrics = metrics.filter { $0.category == category }
        guard !categoryMetrics.isEmpty else { return nil }
        return categoryMetrics.map(\.percentile).reduce(0, +) / categoryMetrics.count
    }
}

struct Metric: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    let percentile: Int
    let direction: MetricDirection
    let category: MetricCategory
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
