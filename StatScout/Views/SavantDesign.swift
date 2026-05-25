import SwiftUI

enum SavantPalette {
    static let canvas       = Color(red: 0.94, green: 0.94, blue: 0.95)
    static let surface      = Color.white
    static let surfaceAlt   = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let surfaceSunk  = Color(red: 0.91, green: 0.91, blue: 0.92)
    static let hairline     = Color(red: 0.78, green: 0.78, blue: 0.80)
    static let divider      = Color(red: 0.85, green: 0.85, blue: 0.87)
    static let ink          = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let inkSecondary = Color(red: 0.25, green: 0.25, blue: 0.28)
    static let inkTertiary  = Color(red: 0.40, green: 0.40, blue: 0.43)
    static let inkOnDark    = Color.white
    static let savantNavy   = Color(red: 0.06, green: 0.13, blue: 0.32)
    static let savantRed    = Color(red: 0.78, green: 0.10, blue: 0.13)
    static let linkBlue     = Color(red: 0.00, green: 0.36, blue: 0.69)
    static let pctlHot      = Color(red: 0.80, green: 0.15, blue: 0.15)
    static let pctlMid      = Color(red: 0.75, green: 0.75, blue: 0.78)
    static let pctlCold     = Color(red: 0.15, green: 0.35, blue: 0.70)
    static let up           = Color(red: 0.16, green: 0.55, blue: 0.27)
    static let down         = savantRed
    static let flat         = inkTertiary

    static func color(forPercentile p: Int) -> Color {
        let t = max(0.0, min(1.0, Double(p) / 100.0))
        if t < 0.5 {
            return lerp(coldRGB, midRGB, t * 2.0)
        } else {
            return lerp(midRGB, hotRGB, (t - 0.5) * 2.0)
        }
    }

    private static let hotRGB: (Double, Double, Double) = (0.80, 0.15, 0.15)
    private static let midRGB: (Double, Double, Double) = (0.75, 0.75, 0.78)
    private static let coldRGB: (Double, Double, Double) = (0.15, 0.35, 0.70)

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let r = a.0 + (b.0 - a.0) * t
        let g = a.1 + (b.1 - a.1) * t
        let bl = a.2 + (b.2 - a.2) * t
        return Color(red: r, green: g, blue: bl)
    }
}

enum SavantFont {
    static func condensed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(condensedName(weight), size: size)
    }
    // Stat numbers route through the condensed face (plain zero) rather than
    // RobotoMono, whose default zero glyph carries a dot/slash. The condensed
    // family has tabular digits, so column alignment in leaderboards holds.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        condensed(size, weight: weight).monospacedDigit()
    }

    private static func condensedName(_ w: Font.Weight) -> String {
        switch w {
        case .black, .heavy:   return "RobotoCondensed-Black"
        case .bold, .semibold: return "RobotoCondensed-Bold"
        case .medium:          return "RobotoCondensed-Medium"
        default:               return "RobotoCondensed-Regular"
        }
    }
}

enum SavantType {
    static let playerName    = SavantFont.condensed(28, weight: .black)
    static let pageTitle     = SavantFont.condensed(22, weight: .black)
    static let sectionTitle  = SavantFont.condensed(13, weight: .black)
    static let cardTitle     = SavantFont.condensed(16, weight: .bold)
    static let body          = SavantFont.condensed(14, weight: .regular)
    static let bodyBold      = SavantFont.condensed(14, weight: .medium)
    static let small         = SavantFont.condensed(12, weight: .regular)
    static let smallBold     = SavantFont.condensed(12, weight: .medium)
    static let micro         = SavantFont.condensed(11, weight: .black)
    static let statHero      = SavantFont.mono(32, weight: .bold)
    static let statLarge     = SavantFont.mono(20, weight: .bold)
    static let statMed       = SavantFont.mono(14, weight: .bold)
    static let statSmall     = SavantFont.mono(12, weight: .medium)
}

enum SavantGeo {
    static let radiusCard: CGFloat = 4
    static let radiusBadge: CGFloat = 2
    static let hairline: CGFloat = 0.5
    static let barTrack: CGFloat = 4
    static let barMarker: CGFloat = 12
    static let padInline: CGFloat = 12
    static let padCard: CGFloat = 16
    static let padPage: CGFloat = 16
    static let padSection: CGFloat = 24
    static let rowHeight: CGFloat = 44
    static let rowHeightHeader: CGFloat = 28
}

enum MLBTeamColor {
    static let primary: [String: Color] = [
        "ARI": Color(red: 0.65, green: 0.10, blue: 0.20),
        "ATL": Color(red: 0.79, green: 0.10, blue: 0.18),
        "BAL": Color(red: 0.87, green: 0.30, blue: 0.07),
        "BOS": Color(red: 0.74, green: 0.13, blue: 0.18),
        "CHC": Color(red: 0.04, green: 0.22, blue: 0.46),
        "CWS": Color(red: 0.10, green: 0.10, blue: 0.10),
        "CIN": Color(red: 0.78, green: 0.07, blue: 0.13),
        "CLE": Color(red: 0.04, green: 0.22, blue: 0.42),
        "COL": Color(red: 0.20, green: 0.16, blue: 0.42),
        "DET": Color(red: 0.05, green: 0.25, blue: 0.45),
        "HOU": Color(red: 0.92, green: 0.34, blue: 0.13),
        "KC":  Color(red: 0.00, green: 0.27, blue: 0.51),
        "LAA": Color(red: 0.74, green: 0.13, blue: 0.18),
        "LAD": Color(red: 0.00, green: 0.30, blue: 0.55),
        "MIA": Color(red: 0.00, green: 0.65, blue: 0.83),
        "MIL": Color(red: 0.07, green: 0.20, blue: 0.36),
        "MIN": Color(red: 0.00, green: 0.27, blue: 0.51),
        "NYM": Color(red: 0.00, green: 0.27, blue: 0.55),
        "NYY": Color(red: 0.00, green: 0.18, blue: 0.40),
        "OAK": Color(red: 0.00, green: 0.32, blue: 0.27),
        "PHI": Color(red: 0.90, green: 0.16, blue: 0.20),
        "PIT": Color(red: 0.99, green: 0.78, blue: 0.13),
        "SD":  Color(red: 0.18, green: 0.10, blue: 0.07),
        "SEA": Color(red: 0.00, green: 0.36, blue: 0.46),
        "SF":  Color(red: 0.99, green: 0.36, blue: 0.07),
        "STL": Color(red: 0.78, green: 0.13, blue: 0.20),
        "TB":  Color(red: 0.00, green: 0.21, blue: 0.40),
        "TEX": Color(red: 0.00, green: 0.20, blue: 0.50),
        "TOR": Color(red: 0.07, green: 0.30, blue: 0.65),
        "WSH": Color(red: 0.67, green: 0.10, blue: 0.18)
    ]
    static func color(_ abbr: String) -> Color { primary[normalizedTeamAbbreviation(abbr)] ?? SavantPalette.inkTertiary }
}

func normalizedTeamAbbreviation(_ team: String) -> String {
    let key = team.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let aliases: [String: String] = [
        "ARIZONA DIAMONDBACKS": "ARI", "AZ": "ARI", "ATLANTA BRAVES": "ATL", "BALTIMORE ORIOLES": "BAL",
        "BOSTON RED SOX": "BOS", "CHICAGO CUBS": "CHC", "CHICAGO WHITE SOX": "CWS",
        "CHW": "CWS", "CINCINNATI REDS": "CIN", "CLEVELAND GUARDIANS": "CLE",
        "CLEVELAND INDIANS": "CLE", "COLORADO ROCKIES": "COL", "DETROIT TIGERS": "DET",
        "HOUSTON ASTROS": "HOU", "KANSAS CITY ROYALS": "KC", "KCR": "KC",
        "LOS ANGELES ANGELS": "LAA", "ANAHEIM ANGELS": "LAA", "LOS ANGELES DODGERS": "LAD",
        "MIAMI MARLINS": "MIA", "MILWAUKEE BREWERS": "MIL", "MINNESOTA TWINS": "MIN",
        "NEW YORK METS": "NYM", "NEW YORK YANKEES": "NYY", "ATHLETICS": "OAK",
        "OAKLAND ATHLETICS": "OAK", "ATH": "OAK", "PHILADELPHIA PHILLIES": "PHI",
        "PITTSBURGH PIRATES": "PIT", "SAN DIEGO PADRES": "SD", "SDP": "SD",
        "SEATTLE MARINERS": "SEA", "SAN FRANCISCO GIANTS": "SF", "SFG": "SF",
        "ST. LOUIS CARDINALS": "STL", "ST LOUIS CARDINALS": "STL", "TAMPA BAY RAYS": "TB",
        "TBR": "TB", "TEXAS RANGERS": "TEX", "TORONTO BLUE JAYS": "TOR",
        "WASHINGTON NATIONALS": "WSH", "WSN": "WSH"
    ]
    return aliases[key] ?? key
}

func teamFullName(_ abbr: String) -> String {
    let map: [String: String] = [
        "ARI":"Arizona","ATL":"Atlanta","BAL":"Baltimore",
        "BOS":"Boston","CHC":"Chicago (NL)","CWS":"Chicago (AL)",
        "CIN":"Cincinnati","CLE":"Cleveland","COL":"Colorado",
        "DET":"Detroit","HOU":"Houston","KC":"Kansas City",
        "LAA":"Los Angeles (AL)","LAD":"Los Angeles (NL)","MIA":"Miami",
        "MIL":"Milwaukee","MIN":"Minnesota","NYM":"New York (NL)",
        "NYY":"New York (AL)","OAK":"Oakland","PHI":"Philadelphia",
        "PIT":"Pittsburgh","SD":"San Diego","SEA":"Seattle",
        "SF":"San Francisco","STL":"St. Louis","TB":"Tampa Bay",
        "TEX":"Texas","TOR":"Toronto","WSH":"Washington"
    ]
    let normalized = normalizedTeamAbbreviation(abbr)
    return map[normalized] ?? abbr
}

struct StatScoutTheme {
    static let background = LinearGradient(colors: [SavantPalette.canvas, SavantPalette.canvas], startPoint: .top, endPoint: .bottom)
    static let card       = SavantPalette.surface
    static let stroke     = SavantPalette.hairline
    static let accent     = SavantPalette.savantRed
    static let hot        = SavantPalette.pctlHot
    static let savantBlue = SavantPalette.pctlCold
    static let savantRed  = SavantPalette.pctlHot
    static let savantOrange = Color(red: 0.90, green: 0.40, blue: 0.30)
    static let savantMidBlue = Color(red: 0.30, green: 0.55, blue: 0.85)

    static func percentileColor(_ percentile: Int) -> Color {
        SavantPalette.color(forPercentile: percentile)
    }
}
