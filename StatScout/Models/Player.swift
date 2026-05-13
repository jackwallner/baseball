import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(playerId)-\(season ?? 0)" }
    let playerId: Int
    let name: String
    let team: String
    let position: String
    let handedness: String
    let imageURL: URL?
    let updatedAt: Date
    let season: Int?
    let playerType: String?
    let source: String?
    let metrics: [Metric]
    let standardStats: [StandardStat]?
    let games: [GameTrend]

    enum CodingKeys: String, CodingKey {
        case playerId = "id"
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

    init(playerId: Int, name: String, team: String, position: String, handedness: String, imageURL: URL?, updatedAt: Date, season: Int? = nil, playerType: String? = nil, source: String? = nil, metrics: [Metric], standardStats: [StandardStat]?, games: [GameTrend]) {
        self.playerId = playerId
        self.name = name
        self.team = team
        self.position = position
        self.handedness = handedness
        self.imageURL = imageURL
        self.updatedAt = updatedAt
        self.season = season
        self.playerType = playerType
        self.source = source
        self.metrics = metrics
        self.standardStats = standardStats
        self.games = games
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(Int.self, forKey: .playerId)
        name = try container.decode(String.self, forKey: .name)
        team = try container.decode(String.self, forKey: .team)
        position = try container.decode(String.self, forKey: .position)
        handedness = try container.decode(String.self, forKey: .handedness)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        season = try container.decodeIfPresent(Int.self, forKey: .season)
        playerType = try container.decodeIfPresent(String.self, forKey: .playerType)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        metrics = try container.decode([Metric].self, forKey: .metrics)
        standardStats = try container.decodeIfPresent([StandardStat].self, forKey: .standardStats)
        games = try container.decodeIfPresent([GameTrend].self, forKey: .games) ?? []
    }

    var overallPercentile: Int {
        guard !metrics.isEmpty else { return 0 }
        if playerType == "two_way" {
            let categoryAverages = Dictionary(grouping: metrics) { $0.category }
                .values
                .map { group in
                    Double(group.map(\.percentile).reduce(0, +)) / Double(group.count)
                }
            return Int(round(categoryAverages.max() ?? 0))
        }
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
        let headline = headlineMetric.map { metric in
            let valueText = metric.value.isEmpty ? "\(metric.percentile.ordinal) percentile" : "\(metric.value), \(metric.percentile.ordinal) percentile"
            return "\(metric.label) \(valueText)"
        } ?? "\(overallPercentile.ordinal) overall percentile"
        return "\(name) · \(team) \(position)\nOverall: \(overallPercentile.ordinal) percentile\nTop stat: \(headline)\nStatScout"
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

    /// The preferred display order of metric labels within this category,
    /// matching Baseball Savant's convention.
    var metricPriorityOrder: [String] {
        switch self {
        case .hitting:
            return ["xwOBA", "xBA", "xSLG", "wOBA", "BA", "SLG", "OBP", "OPS", "ISO",
                    "K%", "BB%", "Whiff%", "Barrel%", "HardHit%", "EV", "LA", "Sprint Speed"]
        case .pitching:
            return ["xwOBA", "xERA", "K%", "BB%", "Whiff%", "Barrel%", "Chase%",
                    "EV", "HardHit%", "GB%", "FB%"]
        case .fielding:
            return ["Range (OAA)", "Arm Strength", "Arm Value", "Jump", "Burst"]
        case .running:
            return ["Sprint Speed", "Bolts", "Acceleration"]
        }
    }

    /// Returns a comparator for sorting metric labels within this category.
    func sortMetrics(_ a: String, _ b: String) -> Bool {
        let order = metricPriorityOrder
        let ia = order.firstIndex(of: a) ?? order.count
        let ib = order.firstIndex(of: b) ?? order.count
        return ia < ib
    }
}

struct TeamRoute: Hashable {
    let abbr: String
    let players: [Player]
}

extension Player {
    func matchesPlayerType(for category: MetricCategory?) -> Bool {
        guard let category else { return true }
        switch category {
        case .hitting: return playerType != "pitcher"
        case .pitching: return playerType != "batter"
        case .fielding, .running: return true
        }
    }

    /// Position to surface in the UI. When the snapshot has no fielding position
    /// (TBD / empty) but the player has metrics, fall back to the player type
    /// label so we never show "TBD" next to real stats.
    var displayPosition: String {
        let trimmed = position.trimmingCharacters(in: .whitespaces).uppercased()
        if !trimmed.isEmpty && trimmed != "TBD" && trimmed != "—" && trimmed != "-" {
            return position
        }
        switch playerType?.lowercased() {
        case "pitcher": return "P"
        case "hitter", "batter": return "DH"
        case "two_way": return "TWP"
        default: return position
        }
    }

    var initials: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return "" }
        guard parts.count > 1 else { return String(first.prefix(1)) }

        let last = parts.last!
        let suffix = last.trimmingCharacters(in: .punctuationCharacters).uppercased()
        let hasSuffix = ["JR", "SR", "II", "III", "IV", "V"].contains(suffix)

        if hasSuffix && parts.count > 2 {
            // Use part before suffix as last name (e.g., "Bobby Witt Jr." → "BW")
            let lastName = parts[parts.count - 2]
            return String(first.prefix(1)) + String(lastName.prefix(1))
        }

        // Standard case: first initial + last initial
        return String(first.prefix(1)) + String(last.prefix(1))
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
