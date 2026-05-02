import SwiftUI

enum SavantPalette {
    static let canvas       = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let surface      = Color.white
    static let surfaceAlt   = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let surfaceSunk  = Color(red: 0.93, green: 0.93, blue: 0.94)
    static let hairline     = Color(red: 0.86, green: 0.86, blue: 0.87)
    static let divider      = Color(red: 0.91, green: 0.91, blue: 0.92)
    static let ink          = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let inkSecondary = Color(red: 0.36, green: 0.36, blue: 0.39)
    static let inkTertiary  = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let inkOnDark    = Color.white
    static let savantNavy   = Color(red: 0.06, green: 0.13, blue: 0.32)
    static let savantRed    = Color(red: 0.78, green: 0.10, blue: 0.13)
    static let linkBlue     = Color(red: 0.00, green: 0.36, blue: 0.69)
    static let pctlHot      = Color(red: 0.80, green: 0.15, blue: 0.15)
    static let pctlMid      = Color(red: 0.95, green: 0.95, blue: 0.95)
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
    private static let midRGB: (Double, Double, Double) = (0.95, 0.95, 0.95)
    private static let coldRGB: (Double, Double, Double) = (0.15, 0.35, 0.70)

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let r = a.0 + (b.0 - a.0) * t
        let g = a.1 + (b.1 - a.1) * t
        let bl = a.2 + (b.2 - a.2) * t
        return Color(red: r, green: g, blue: bl)
    }
}

enum SavantType {
    static let playerName    = Font.system(size: 28, weight: .heavy)
    static let pageTitle     = Font.system(size: 22, weight: .heavy)
    static let sectionTitle  = Font.system(size: 13, weight: .heavy)
    static let cardTitle     = Font.system(size: 16, weight: .bold)
    static let body          = Font.system(size: 14, weight: .regular)
    static let bodyBold      = Font.system(size: 14, weight: .semibold)
    static let small         = Font.system(size: 12, weight: .regular)
    static let smallBold     = Font.system(size: 12, weight: .semibold)
    static let micro         = Font.system(size: 11, weight: .heavy)
    static let statHero      = Font.system(size: 32, weight: .heavy).monospacedDigit()
    static let statLarge     = Font.system(size: 20, weight: .heavy).monospacedDigit()
    static let statMed       = Font.system(size: 14, weight: .bold).monospacedDigit()
    static let statSmall     = Font.system(size: 12, weight: .semibold).monospacedDigit()
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
        "ARI":"Arizona Diamondbacks","ATL":"Atlanta Braves","BAL":"Baltimore Orioles",
        "BOS":"Boston Red Sox","CHC":"Chicago Cubs","CWS":"Chicago White Sox",
        "CIN":"Cincinnati Reds","CLE":"Cleveland Guardians","COL":"Colorado Rockies",
        "DET":"Detroit Tigers","HOU":"Houston Astros","KC":"Kansas City Royals",
        "LAA":"Los Angeles Angels","LAD":"Los Angeles Dodgers","MIA":"Miami Marlins",
        "MIL":"Milwaukee Brewers","MIN":"Minnesota Twins","NYM":"New York Mets",
        "NYY":"New York Yankees","OAK":"Oakland Athletics","PHI":"Philadelphia Phillies",
        "PIT":"Pittsburgh Pirates","SD":"San Diego Padres","SEA":"Seattle Mariners",
        "SF":"San Francisco Giants","STL":"St. Louis Cardinals","TB":"Tampa Bay Rays",
        "TEX":"Texas Rangers","TOR":"Toronto Blue Jays","WSH":"Washington Nationals"
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
