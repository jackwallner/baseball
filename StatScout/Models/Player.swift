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

    /// Average of the per-category averages, not of every metric.
    ///
    /// A flat mean over `metrics` weights a category by how many metrics happen
    /// to be present that season, so a hitter with four fielding metrics had his
    /// "overall" pulled a third of the way toward his glove while a hitter with
    /// one had it barely moved. Averaging each category first gives both the
    /// same shape. A two-way player still takes his best side rather than a
    /// blend of bat and arm.
    var overallPercentile: Int {
        guard !metrics.isEmpty else { return 0 }
        let categoryAverages = Dictionary(grouping: metrics) { $0.category }
            .values
            .map { group in
                Double(group.map(\.percentile).reduce(0, +)) / Double(group.count)
            }
        guard !categoryAverages.isEmpty else { return 0 }
        if playerType == "two_way" {
            return Int(round(categoryAverages.max() ?? 0))
        }
        return Int(round(categoryAverages.reduce(0, +) / Double(categoryAverages.count)))
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
    /// Which line this stat belongs to. A two-way player has two stats labelled
    /// "H" (hits collected, hits allowed) and this is the only thing that tells
    /// them apart. Optional because rows ingested before the backend started
    /// emitting it have no category, in which case `resolvedCategory` infers one.
    let category: MetricCategory?

    init(id: String, label: String, value: String, category: MetricCategory? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.category = category
    }

    /// Best available category. Falls back to the label for legacy rows: the
    /// pitching-only labels are unambiguous, the fielding ones likewise, and
    /// anything left over is a hitting stat. A legacy two-way row still can't
    /// be split correctly, but nothing can fix that from the client side.
    func resolvedCategory(playerType: String?) -> MetricCategory {
        if let category { return category }
        if Self.pitchingOnlyLabels.contains(label) { return .pitching }
        if Self.fieldingLabels.contains(label) { return .fielding }
        return playerType == "pitcher" ? .pitching : .hitting
    }

    private static let pitchingOnlyLabels: Set<String> = [
        "ERA", "WHIP", "W", "L", "SV", "IP", "ER", "K/9", "BB/9", "K/BB", "QS", "GS", "BF"
    ]
    private static let fieldingLabels: Set<String> = ["E", "A", "PO", "DP", "FLD%", "GF"]

    /// Labels a two-way player carries twice, once per line.
    static let ambiguousLabels: Set<String> = ["H", "R", "HR", "BB", "SO", "G"]
}

extension Array where Element == StandardStat {
    /// The stat with this label on the given side.
    ///
    /// Matching on label alone is fine for the 99.9% of players with one line,
    /// but a two-way player has an "H" for hits collected and an "H" for hits
    /// allowed, and `first(where:)` would hand back whichever the backend
    /// happened to emit first.
    func stat(_ label: String, category: MetricCategory, playerType: String?) -> StandardStat? {
        let key = label.uppercased()
        guard StandardStat.ambiguousLabels.contains(key) else {
            return first { $0.label.uppercased() == key }
        }
        return first {
            $0.label.uppercased() == key
                && $0.resolvedCategory(playerType: playerType) == category
        }
    }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let category = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
        }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown metric category: \(value)"
            )
        }
        self = category
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Every metric label the backend actually emits for this category.
    ///
    /// These lists used to be hand-written from memory and had drifted badly:
    /// the pitching one asked for "HardHit%", "EV", "LA", "GB%" and "FB%", none
    /// of which exist, while the real "Hard-Hit%", "Avg EV Against", "Max EV
    /// Against", "xISO" and "xOBP" went unlisted. `StandardStatsTests` asserts
    /// these stay in step with a captured sample of live labels.
    static let knownLabels: [MetricCategory: Set<String>] = [
        .hitting: ["xwOBA", "xBA", "xSLG", "xISO", "xOBP", "K%", "BB%", "Whiff%",
                   "Chase%", "Barrel%", "Hard-Hit%", "EV", "Max EV", "Squared-Up%",
                   "Bat Speed", "Swing Length"],
        .pitching: ["xwOBA", "xERA", "xBA", "xSLG", "xISO", "xOBP", "K%", "BB%",
                    "Whiff%", "Chase%", "Barrel%", "Hard-Hit%", "Avg EV Against",
                    "Max EV Against", "Fastball Velo", "Fastball Spin", "Curve Spin"],
        .fielding: ["Range (OAA)", "Arm Strength", "Arm Value", "Jump", "Burst"],
        .running: ["Sprint Speed", "Bolts", "Acceleration"],
    ]

    /// The preferred display order of metric labels within this category,
    /// matching Baseball Savant's convention. Labels not listed here sort
    /// alphabetically after the ones that are.
    var metricPriorityOrder: [String] {
        switch self {
        case .hitting:
            return ["xwOBA", "xBA", "xSLG", "xISO", "xOBP", "K%", "BB%", "Whiff%",
                    "Chase%", "Barrel%", "Hard-Hit%", "EV", "Max EV", "Squared-Up%",
                    "Bat Speed", "Swing Length"]
        case .pitching:
            return ["xwOBA", "xERA", "xBA", "xSLG", "xISO", "xOBP", "K%", "BB%",
                    "Whiff%", "Chase%", "Barrel%", "Hard-Hit%", "Avg EV Against",
                    "Max EV Against", "Fastball Velo", "Fastball Spin", "Curve Spin"]
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
        let type = playerType?.lowercased()
        switch category {
        case .hitting:
            // Pitchers carry batter-shaped fields in their feed (HR allowed, etc.),
            // a strict whitelist keeps them off the hitting board even when those
            // fields are present. nil falls through to "include" so we don't drop
            // legitimate batters who lost their role label upstream.
            return type != "pitcher"
        case .pitching:
            return type == "pitcher" || type == "two_way"
        case .fielding, .running:
            return true
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
