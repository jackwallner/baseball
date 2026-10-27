import Foundation

/// Display names for Statcast metric labels. The labels are also data keys
/// (the feed sends them in English and every lookup compares against that
/// spelling), so only the text drawn on screen goes through here.
enum MetricName {
    static func localized(_ label: String) -> String {
        switch label {
        case "Bat Speed": return String(localized: "Bat Speed")
        case "Swing Length": return String(localized: "Swing Length")
        case "Avg EV Against": return String(localized: "Avg EV Against")
        case "Max EV Against": return String(localized: "Max EV Against")
        case "Max EV": return String(localized: "Max EV")
        case "EV": return String(localized: "EV")
        case "Exit Velo": return String(localized: "Exit Velo")
        case "Exit Velo Against": return String(localized: "Exit Velo Against")
        case "Fastball Velo": return String(localized: "Fastball Velo")
        case "Fastball Spin": return String(localized: "Fastball Spin")
        case "Curve Spin": return String(localized: "Curve Spin")
        case "Range (OAA)": return String(localized: "Range (OAA)")
        case "Arm Strength": return String(localized: "Arm Strength")
        case "Arm Value": return String(localized: "Arm Value")
        case "Jump": return String(localized: "Jump")
        case "Burst": return String(localized: "Burst")
        case "Sprint Speed": return String(localized: "Sprint Speed")
        case "Bolts": return String(localized: "Bolts")
        case "Acceleration": return String(localized: "Acceleration")
        case "Whiff%": return String(localized: "Whiff%")
        case "Chase%": return String(localized: "Chase%")
        case "Barrel%": return String(localized: "Barrel%")
        case "Hard-Hit%": return String(localized: "Hard-Hit%")
        case "Squared-Up%": return String(localized: "Squared-Up%")
        case "Sweet-Spot%": return String(localized: "Sweet-Spot%")
        case "Ground-Ball%": return String(localized: "Ground-Ball%")
        case "Barrel% Against": return String(localized: "Barrel% Against")
        case "Hard-Hit% Against": return String(localized: "Hard-Hit% Against")
        case "AVG Against": return String(localized: "AVG Against")
        case "OBP Against": return String(localized: "OBP Against")
        case "SLG Against": return String(localized: "SLG Against")
        case "OPS Against": return String(localized: "OPS Against")
        case "xwOBA Against": return String(localized: "xwOBA Against")
        case "xBA Against": return String(localized: "xBA Against")
        case "xSLG Against": return String(localized: "xSLG Against")
        default: return label
        }
    }
}

extension MetricCategory {
    var title: String {
        switch self {
        case .hitting: return String(localized: "Hitting")
        case .pitching: return String(localized: "Pitching")
        case .fielding: return String(localized: "Fielding")
        case .running: return String(localized: "Running")
        }
    }
}

private enum OrdinalFormat {
    nonisolated(unsafe) static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = .autoupdatingCurrent
        return f
    }()
}

extension Int {
    /// "94th" in English, "94e" in French, "第94" in Japanese.
    var ordinal: String {
        OrdinalFormat.formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
