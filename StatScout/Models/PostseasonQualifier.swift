import Foundation

/// MLB's own rate-stat qualifier, applied to the postseason boards.
///
/// The postseason boards used to rank everyone who had stepped on the field,
/// so a pinch hitter who went 1-for-1 led the AVG board at 1.000 and a
/// one-PA cameo topped xwOBA, above the regulars the board was opened for.
/// MLB.com's postseason leaders use the regular-season rule scaled to each
/// club's own games: 3.1 plate appearances (rounded) or 1 inning per team
/// game. Measured per club, because a team swept in the Wild Card round has
/// played two games while the pennant winners have played ten.
struct PostseasonQualifier {
    static let plateAppearancesPerGame = 3.1
    static let inningsPerGame = 1.0

    /// Games each club has played, keyed by normalized abbreviation.
    let teamGames: [String: Double]

    /// A club's games played is its busiest position player's games played.
    /// Pitchers are left out: their G counts appearances, not team games.
    init(players: [Player]) {
        var games: [String: Double] = [:]
        for player in players where player.playerType?.lowercased() != "pitcher" {
            guard let value = Self.number("G", .hitting, player) else { continue }
            let team = normalizedTeamAbbreviation(player.team)
            games[team] = max(games[team] ?? 0, value)
        }
        teamGames = games
    }

    func qualifies(_ player: Player, for category: MetricCategory) -> Bool {
        guard let games = teamGames[normalizedTeamAbbreviation(player.team)], games > 0 else {
            return false
        }
        if category == .pitching {
            let innings = Self.innings(Self.number("IP", .pitching, player) ?? 0)
            return innings >= games * Self.inningsPerGame
        }
        let plateAppearances = Self.number("PA", .hitting, player) ?? 0
        return plateAppearances >= (games * Self.plateAppearancesPerGame).rounded()
    }

    /// Box-score innings ("4.2") to real innings (4.667).
    static func innings(_ boxScore: Double) -> Double {
        let whole = boxScore.rounded(.towardZero)
        let outs = ((boxScore - whole) * 10).rounded()
        return whole + outs / 3
    }

    private static func number(_ label: String, _ category: MetricCategory, _ player: Player) -> Double? {
        guard let stat = player.standardStats?.stat(label, category: category, playerType: player.playerType) else {
            return nil
        }
        return Double(stat.value.trimmingCharacters(in: .whitespaces))
    }
}
