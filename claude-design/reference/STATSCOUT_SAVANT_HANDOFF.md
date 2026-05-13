# StatScout iOS — Baseball Savant Player-Page Visual Overhaul

> **Audience:** Claude Code / Kimi / any coding agent working on `jackwallner/baseball`.
> **Goal:** Bring the entire iOS app's UI as close to the Baseball Savant **player page** as possible. The Savant player page is the canonical reference — every screen in StatScout (dashboard, leaderboard, team, profile, metric leaders) should feel like it lives inside the same visual system as `baseballsavant.mlb.com/savant-player/...`.
> **Permission:** The repo owner has confirmed permission from MLB to mirror Baseball Savant's visual conventions. Do not water down brand parity.

This document is **prescriptive**. When a value is given (hex, point size, padding, radius), use it exactly. Open `SAVANT_PLAYER_PAGE_REFERENCE.html` next to your editor — it's a high-fidelity HTML mockup of the target Savant player page rendered at iPhone width. **Match it.**

---

## 0. The Mental Model

Everything in StatScout should look like a **slice of a Savant player page**. The dashboard is just "the leaderboard module" stacked above "the percentile rankings module" stacked above "a roster table." The team view is the same chrome wrapping a roster. The metric leaders view is a 2-column variant of the percentile rankings table. **One visual language, applied consistently.**

The Savant player page itself is built from 6 repeating modules. Learn these — they're your component vocabulary:

| Module | Visual signature | Where it appears now |
|---|---|---|
| **Player Identity Strip** | Headshot left, big name + meta right, navy background slab | Top of every player view |
| **Percentile Bar Row** | `LABEL ─── value ─── 2025 ●━━━━○━━━━ 2024 ─── pctl` | Inside Percentile Rankings module |
| **Section Bar** | Uppercase section title, red-bordered, small "info ⓘ" link | Above every grouped table |
| **Stat Table** | Zebra-striped white/grey rows, 0.5pt hairlines, monospaced numerics | Standard, Statcast, Game-by-game tables |
| **Tab Bar** | Underlined inline tabs in red on active | Top of every player page |
| **Filter Pill Row** | Inline `[Batter ▾] [2026 ▾] [Update]` controls | Above every leaderboard |

That's it. Six modules, repeated everywhere. Build them once, apply everywhere.

---

## 1. Design Tokens

**Create** `StatScout/Views/SavantTokens.swift`. **Replace** `StatScoutTheme` values; keep the type name so existing call sites compile.

### 1.1 Colors

```swift
import SwiftUI

enum SavantPalette {
    // ── Surfaces (Savant is a LIGHT app)
    static let canvas       = Color(red: 0.96, green: 0.96, blue: 0.96)   // #F5F5F5  page bg
    static let surface      = Color.white                                  // #FFFFFF  table/card
    static let surfaceAlt   = Color(red: 0.97, green: 0.97, blue: 0.98)   // #F7F7F8  zebra row
    static let surfaceSunk  = Color(red: 0.93, green: 0.93, blue: 0.94)   // #ECECEE  section header bg
    static let hairline     = Color(red: 0.86, green: 0.86, blue: 0.87)   // #DBDBDD  1px rules
    static let divider      = Color(red: 0.91, green: 0.91, blue: 0.92)   // #E8E8EA

    // ── Ink
    static let ink          = Color(red: 0.10, green: 0.10, blue: 0.11)   // #1A1A1C
    static let inkSecondary = Color(red: 0.36, green: 0.36, blue: 0.39)   // #5C5C63
    static let inkTertiary  = Color(red: 0.55, green: 0.55, blue: 0.58)   // #8C8C93
    static let inkOnDark    = Color.white

    // ── Brand
    static let savantNavy   = Color(red: 0.06, green: 0.13, blue: 0.32)   // #102152  player-strip / footer
    static let savantRed    = Color(red: 0.78, green: 0.10, blue: 0.13)   // #C71A21  CTAs, active tab underline
    static let linkBlue     = Color(red: 0.00, green: 0.36, blue: 0.69)   // #005CB0  inline links

    // ── Percentile scale (CONTINUOUS gradient — no step thresholds)
    static let pctlHot      = Color(red: 0.823, green: 0.176, blue: 0.184) // #D22D2F  100th
    static let pctlMid      = Color(red: 0.749, green: 0.749, blue: 0.749) // #BFBFBF  50th
    static let pctlCold     = Color(red: 0.212, green: 0.380, blue: 0.678) // #3661AD  0th

    // Trend
    static let up   = Color(red: 0.16, green: 0.55, blue: 0.27)            // #29873F
    static let down = savantRed
    static let flat = inkTertiary

    /// Single source of truth — every percentile color in the app uses this.
    static func color(forPercentile p: Int) -> Color {
        let t = max(0.0, min(1.0, Double(p) / 100.0))
        if t < 0.5 {
            return interpolate(pctlCold, pctlMid, t * 2.0)
        } else {
            return interpolate(pctlMid, pctlHot, (t - 0.5) * 2.0)
        }
    }

    private static func interpolate(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let env = EnvironmentValues()
        let ar = a.resolve(in: env), br = b.resolve(in: env)
        return Color(
            red:   Double(ar.red   + (br.red   - ar.red)   * Float(t)),
            green: Double(ar.green + (br.green - ar.green) * Float(t)),
            blue:  Double(ar.blue  + (br.blue  - ar.blue)  * Float(t))
        )
    }
}

// Backwards-compat shim
struct StatScoutTheme {
    static let background = LinearGradient(colors: [SavantPalette.canvas, SavantPalette.canvas], startPoint: .top, endPoint: .bottom)
    static let card       = SavantPalette.surface
    static let stroke     = SavantPalette.hairline
    static let accent     = SavantPalette.savantRed
    static let hot        = SavantPalette.pctlHot
    static let savantBlue = SavantPalette.pctlCold
    static let savantRed  = SavantPalette.pctlHot
}
```

### 1.2 Typography

Savant uses Helvetica/Arial-style sans. On iOS, use **default SF Pro** without `.rounded` — it's the closest match. Stat numerics are **always monospaced**.

```swift
enum SavantType {
    // Identity
    static let playerName    = Font.system(size: 28, weight: .heavy)         // "Aaron Judge" on profile strip
    static let pageTitle     = Font.system(size: 22, weight: .heavy)         // dashboard title bar
    static let sectionTitle  = Font.system(size: 13, weight: .heavy)         // "PERCENTILE RANKINGS" - uppercase + tracking 0.8
    static let cardTitle     = Font.system(size: 16, weight: .bold)          // player name in row

    // Body
    static let body          = Font.system(size: 14, weight: .regular)
    static let bodyBold      = Font.system(size: 14, weight: .semibold)
    static let small         = Font.system(size: 12, weight: .regular)
    static let smallBold     = Font.system(size: 12, weight: .semibold)
    static let micro         = Font.system(size: 11, weight: .heavy)         // tags, labels - uppercase + tracking 0.5

    // Numerics — ALWAYS monospaced for tabular alignment
    static let statHero      = Font.system(size: 32, weight: .heavy).monospacedDigit() // big bubble in identity strip
    static let statLarge     = Font.system(size: 20, weight: .heavy).monospacedDigit()
    static let statMed       = Font.system(size: 14, weight: .bold).monospacedDigit()
    static let statSmall     = Font.system(size: 12, weight: .semibold).monospacedDigit()
}
```

**Casing rules:**
- All section headers: uppercase, `.tracking(0.8)`, `.font(SavantType.sectionTitle)`, `.foregroundStyle(SavantPalette.ink)`.
- All chips/tags (team abbr, category labels, column headers): uppercase, `.tracking(0.5)`, `.font(SavantType.micro)`.
- Player names: title case, no tracking.

### 1.3 Geometry

| Token | Value | Use |
|---|---|---|
| `radiusCard` | 4pt | cards, tables, chips |
| `radiusBadge` | 2pt | percentile pills |
| `radiusFull` | 50% | headshots only |
| `hairline` | 0.5pt | `Divider()` between table rows |
| `barTrack` | 4pt | percentile bar height |
| `barMarker` | 12pt | percentile circle marker diameter |
| `padInline` | 12pt | row internal padding |
| `padCard` | 16pt | card internal padding |
| `padPage` | 16pt | page horizontal padding |
| `padSection` | 24pt | between major sections |
| `rowHeight` | 44pt | data rows in tables |
| `rowHeightHeader` | 28pt | column-header rows |

**Savant is not a rounded aesthetic.** No radius exceeds 4pt except headshots. No shadows anywhere — separation comes from 0.5pt hairlines and zebra striping.

---

## 2. The Six Canonical Modules

### Module 1 · Player Identity Strip

The slab at the top of every Savant player page.

```
┌──────────────────────────────────────────────────────┐
│                                                      │  ← navy band (#102152) full bleed
│   ⬤        AARON JUDGE                       100     │
│  [pic]     New York Yankees                  PCTL    │  ← number in red gradient color
│   72       #99 · RF · R/R · 6'7" · 282 lb            │
│                                                      │
└──────────────────────────────────────────────────────┘
```

**Specs:**
- Background: `SavantPalette.savantNavy` (#102152), full edge-to-edge.
- Headshot: 72×72 circle, white 2pt stroke, on the left, with 16pt page padding.
- Name: `SavantType.playerName`, `inkOnDark`. Right under name: team full name in `SavantType.bodyBold`, white-opacity-0.85.
- Meta line: `#99 · RF · R/R` in `SavantType.small`, white-opacity-0.65, with `·` separators in white-opacity-0.35.
- Right side: stacked pill — big number `SavantType.statHero` colored by `color(forPercentile:)` (background fill) with white text, and "PCTL" underneath in `SavantType.micro`. The pill is 64×64, 2pt radius. Use this only when an "overall percentile" makes sense (not on the dashboard hero).
- Padding: 16pt vertical, 16pt horizontal. Total height ≈ 104pt.

```swift
struct PlayerIdentityStrip: View {
    let player: Player
    var showOverallBadge: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlayerHeadshot(url: player.headshotURL, initials: player.initials, size: 72)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(SavantType.playerName)
                    .foregroundStyle(SavantPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(teamFullName(player.team))
                    .font(SavantType.bodyBold)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(player.position) · \(player.handedness)")
                    .font(SavantType.small)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            if showOverallBadge {
                OverallPercentileBadge(percentile: player.overallPercentile)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavantPalette.savantNavy)
    }
}
```

### Module 2 · Percentile Bar Row

The single most important visual. This is what makes a Savant page look like a Savant page. **It is NOT a filled bar. It is a horizontal track with a circular marker.**

```
  Exit Velocity                       91.4 mph    87
  ─────────────────────────────────────────────────────
  ░░░░░░░░░░░░░░░░░│░░░░░░░░░░░░●░░░░░░░░░░░░░░░░░
                   ↑ 50th tick   ↑ marker at 87% (red)
```

**Anatomy:**
- **Track**: full width minus value/pctl gutters, height 4pt, radius 2pt, fill `SavantPalette.hairline`.
- **50th-percentile midline**: 1pt vertical rule from y = -3 to y = +3 (track height + 2pt above and below), color `SavantPalette.inkTertiary`.
- **Marker**: 12pt circle, fill = `SavantPalette.color(forPercentile:)`, white 2pt stroke, centered at `width * pctl / 100`, vertically centered on the track.
- **Above the bar**: HStack — `[label flex]  [value 64pt right]  [pctl 32pt right]`.
  - label: `SavantType.smallBold`, `ink`
  - value: `SavantType.statSmall`, `inkSecondary`
  - pctl: `SavantType.statSmall`, `color(forPercentile:)`

**Implementation (replace existing `MetricBar`):**

```swift
struct MetricBar: View {
    let metric: Metric
    var showValue: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(metric.label)
                    .font(SavantType.smallBold)
                    .foregroundStyle(SavantPalette.ink)
                Spacer(minLength: 8)
                if showValue {
                    Text(metric.value)
                        .font(SavantType.statSmall)
                        .foregroundStyle(SavantPalette.inkSecondary)
                        .frame(minWidth: 64, alignment: .trailing)
                }
                Text("\(metric.percentile)")
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.color(forPercentile: metric.percentile))
                    .frame(width: 32, alignment: .trailing)
            }
            GeometryReader { proxy in
                let p = max(0, min(100, metric.percentile))
                let x = max(6, min(proxy.size.width - 6, proxy.size.width * CGFloat(p) / 100.0))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SavantPalette.hairline)
                        .frame(height: 4)
                        .frame(maxHeight: .infinity)
                    Rectangle()
                        .fill(SavantPalette.inkTertiary)
                        .frame(width: 1, height: 10)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height / 2)
                    Circle()
                        .fill(SavantPalette.color(forPercentile: p))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(x: x, y: proxy.size.height / 2)
                }
            }
            .frame(height: 12)
        }
    }
}
```

### Module 3 · Section Bar

Above every grouped table or list.

```
┌────────────────────────────────────────────────┐
│  HITTING                              AVG  92  │  ← surfaceSunk bg, 28pt tall, red 2pt left border
└────────────────────────────────────────────────┘
```

- 28pt tall, `SavantPalette.surfaceSunk` background (#ECECEE).
- 2pt `SavantPalette.savantRed` border on the leading edge only.
- Title: `SavantType.sectionTitle` uppercase, `.tracking(0.8)`, `ink`, padded 12pt from leading red bar.
- Optional right-aligned `AVG ##` callout: `SavantType.micro` uppercase + `SavantType.statSmall`, percentile colored, 12pt right padding.

```swift
struct SavantSectionBar: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(SavantPalette.savantRed).frame(width: 2)
            Text(title.uppercased())
                .font(SavantType.sectionTitle)
                .tracking(0.8)
                .foregroundStyle(SavantPalette.ink)
                .padding(.leading, 10)
            Spacer()
            if let trailing { trailing.padding(.trailing, 12) }
        }
        .frame(height: 28)
        .background(SavantPalette.surfaceSunk)
    }
}
```

### Module 4 · Stat Table

Used for: leaderboard, recent games, metric leaders, team roster.

- Wrapped in a white card: 4pt radius, 0.5pt `hairline` stroke, no shadow.
- Inside: `VStack(spacing: 0)` of rows separated by `Rectangle().fill(SavantPalette.divider).frame(height: 0.5)`.
- **Header row**: 28pt tall, `surfaceAlt` background, column labels uppercase `SavantType.micro` `inkTertiary`, `.tracking(0.5)`.
- **Data row**: 44pt tall, alternating `surface` / `surfaceAlt` backgrounds (zebra). Tap target = full row.
- **Numeric columns** right-aligned, monospaced, `SavantType.statMed`.
- **Text columns** left-aligned. Player name + meta stacked: name `SavantType.cardTitle`, meta `SavantType.small inkTertiary`.

### Module 5 · Tab Bar (sub-page nav)

For switching content within a player page (Standard / Statcast / Pitch Arsenal / Game Logs / Splits, etc.). Use this on `PlayerProfileView`.

```
   STANDARD   STATCAST   GAME LOGS   SPLITS
   ────────                                       ← 2pt red underline on active
```

- Horizontal `ScrollView`, no chrome.
- Each tab: 12pt vertical pad, 14pt horizontal pad. Label `SavantType.smallBold`, uppercase `.tracking(0.5)`.
- Active: `ink` text + 2pt `savantRed` underline at the bottom of the tab.
- Inactive: `inkTertiary` text, no underline.
- The whole bar sits on `surface` with a 0.5pt `hairline` bottom rule.

### Module 6 · Filter Pill Row

For dashboard / team / leaderboard filters. Replaces the current rounded capsule chips and the red "Random Player" button.

```
  [ Batters  ▾ ]  [ All Teams  ▾ ]  [ 2026  ▾ ]   [ UPDATE ]
```

- Each select: white fill, 1pt `hairline` stroke, 4pt radius, 32pt tall, 12pt horizontal pad. Text `SavantType.smallBold` `ink`. Trailing 11pt chevron `▾` in `inkSecondary`.
- "UPDATE" CTA: `savantRed` fill, white text, `SavantType.micro` uppercase tracked, 4pt radius, 32pt tall, 14pt horizontal pad.
- Row sits on `surface` with 12pt vertical padding.

---

## 3. Atomic Components

### `PlayerHeadshot`

```swift
struct PlayerHeadshot: View {
    let url: URL?
    let initials: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(SavantPalette.surfaceAlt)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(SavantPalette.hairline, lineWidth: 0.5))
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(SavantPalette.inkTertiary)
    }
}
```

Add to `Player`:
```swift
extension Player {
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
    var headshotURL: URL? {
        imageURL ?? URL(string: "https://midfield.mlbstatic.com/v1/people/\(id)/spots/120")
    }
}
```

### `OverallPercentileBadge`

A solid filled rectangle, percentile-colored.

```swift
struct OverallPercentileBadge: View {
    let percentile: Int
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            Text("\(percentile)").font(SavantType.statHero).foregroundStyle(.white)
            Text("PCTL").font(SavantType.micro).tracking(0.6).foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: size, height: size)
        .background(SavantPalette.color(forPercentile: percentile))
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
```

### `TeamColorDot`

```swift
struct TeamColorDot: View {
    let abbr: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(MLBTeamColor.color(abbr)).frame(width: size, height: size)
    }
}
```

### MLB team color map

(Add to `Components.swift` or `SavantTokens.swift`.)

```swift
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
    static func color(_ abbr: String) -> Color { primary[abbr.uppercased()] ?? SavantPalette.inkTertiary }
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
    return map[abbr.uppercased()] ?? abbr
}
```

---

## 4. Screen-by-Screen Rebuild

### 4.1 `PlayerProfileView` — the canonical Savant page

This is what we're emulating. Layout, top to bottom:

1. **Player Identity Strip** (`PlayerIdentityStrip`, navy slab, full bleed).
2. **Tab bar** (`SavantTabs`) on white surface — tabs: `[STANDARD] [STATCAST] [GAME LOGS] [SPLITS]`. Default tab is `STATCAST`. Other tabs are non-functional placeholders for now (just show "Coming soon" text).
3. **Percentile Rankings card** — white surface, 4pt radius, hairline stroke. Top row: `SavantSectionBar(title: "PERCENTILE RANKINGS")`. Then per-category sub-blocks:
   - Sub-section bar (smaller): `HITTING · 2026` left, `AVG 92` callout right, 24pt tall, `surfaceAlt` bg, 1pt `divider` bottom.
   - Tight `VStack(spacing: 0)` of `MetricBar`s, each 12pt vertical padding, 16pt horizontal, separated by 0.5pt dividers.
   - Repeat for `PITCHING` / `FIELDING` / `RUNNING`.
4. **Standard Stats card** — second white card, `SavantSectionBar(title: "STANDARD STATS · 2026")`. Inside: a 2-column key-value grid: each row is `[label sm/inkSecondary] [value statMed/ink right]`. 4 rows visible; sourced from `player.metrics` filtered to `category == .hitting` (or whichever applies). For now, just show the player's `Metric.value` strings under each `Metric.label` — same data as percentile, but presented as flat key-value.
5. **Recent Games card** — `SavantSectionBar(title: "GAME-BY-GAME")`. Stat-table style:
   - Header row columns: `DATE` (60pt) · `OPP` (44pt) · `Δ PCTL` (52pt right) · `KEY` (flex right).
   - Data rows from `player.games`. Δ column colored: `up` if positive, `down` if negative, `flat` if 0. With `▲ +3` / `▼ -2` glyphs.

Remove from current implementation:
- The big rounded gradient header card.
- All `RoundedRectangle(cornerRadius: 12)` wrappers around individual metrics.
- The `SectionHeader` "Recent Games" card-row pattern.
- Sheet presentation — push onto a `NavigationStack` instead.

### 4.2 `DashboardView` — leaderboard-first

Treat the dashboard as "the percentile-rankings leaderboard" page, not a marketing landing.

Layout, top to bottom:
1. **App header** (replaces `HeroHeaderView`): 56pt navy slab with the wordmark `savant` (italic heavy white, lowercase) on the left and `STATSCOUT` micro pill on the right. Below the slab, a 36pt white breadcrumb strip showing `Leaderboard › Percentile Rankings`.
2. **Filter Pill Row** (Module 6): `[Batters ▾]` `[All Teams ▾]` `[2026 ▾]` `[UPDATE]`.
3. **Category tab bar** (Module 5, narrow 36pt height): `[ALL] [HITTING] [PITCHING] [FIELDING] [RUNNING]`. Bound to `viewModel.selectedCategory`.
4. **Featured strip** — *thin* horizontal scroll, 96pt tall, `surfaceAlt` background. Each tile 240pt × 80pt: 56×56 headshot left, vertical stack right with name/team/headline metric pctl. Top 5 by `overallPercentile`.
5. **Stat Table** — main leaderboard. Columns: `RK` (28pt) · `PLAYER` (flex, with 28×28 headshot + name + team-dot+abbr on second line) · `VAL` (60pt right) · `PCTL BAR` (96pt min) · `PCTL` (32pt right). 44pt rows, zebra, hairline separated.

Remove:
- Gradient hero card.
- Team chip row (move teams into the filter pill row dropdown).
- "Random Player" red capsule.
- "Metric Leaders" rounded pill (move into a toolbar overflow menu — `Image(systemName: "ellipsis.circle")`).
- Search field is fine, but restyle: 32pt tall, 1pt `hairline` stroke, 4pt radius, no fill tint. Magnifying glass `inkTertiary`.

### 4.3 `TeamView`

Use the same Player Identity Strip skeleton, but for a team:
- Navy slab, 72pt-tall block with team logo placeholder (use a 56×56 colored circle with `MLBTeamColor.color(team)` filled, and the abbreviation white inside in `SavantType.statLarge`).
- Right of logo: full team name (`SavantType.playerName`, white) and "{count} Players · 2026 Season" meta line.
- Below: a `SavantSectionBar("ROSTER")` then the same Stat Table component as the dashboard leaderboard.

### 4.4 `MetricLeadersView`

- Navy slab header with title "METRIC LEADERS" and small subtitle "Best & worst per Statcast metric".
- One white card per `MetricCategory`, each opened by a `SavantSectionBar`.
- Inside each: a stat table. Columns: `METRIC` (flex) · `BEST` (40% width) · `WORST` (40% width).
  - `METRIC` cell: label, `SavantType.smallBold ink`.
  - `BEST` cell: 24×24 headshot + name (smallBold ink, 1 line) + value in red (`SavantType.statSmall pctlHot`).
  - `WORST` cell: same layout in `pctlCold`.

### 4.5 `SettingsView`

- Light-mode rewrite: `Form` with `.formStyle(.grouped)` on `SavantPalette.canvas` background. Section headers uppercase tracked. Cells use system defaults — don't over-style. Add a navy "About StatScout" header strip at top with the savant-style wordmark.

### 4.6 `StatScoutApp.swift`

Add `.preferredColorScheme(.light)` at the root view. The app is light-mode only.

---

## 5. Navigation Architecture

Convert the current sheet-driven flow to a real `NavigationStack`:

```swift
NavigationStack {
    DashboardView(...)
        .navigationDestination(for: Player.self) { player in
            PlayerProfileView(player: player)
        }
        .navigationDestination(for: TeamRoute.self) { route in
            TeamView(team: route.abbr, players: route.players)
        }
}
```

Where `TeamRoute: Hashable`. This gives us back-chevrons and proper iOS navigation. Keep `MetricLeadersView` and `SettingsView` as sheets — those are utility/secondary surfaces.

Update `SheetDestination` enum: drop `.player` and `.team`, keep `.settings` and `.metricLeaders` only.

---

## 6. File Plan

| Path | Action | Why |
|---|---|---|
| `StatScout/Views/SavantTokens.swift` | **CREATE** | Palette, type, geometry, MLB color/name maps |
| `StatScout/Views/SavantModules.swift` | **CREATE** | The 6 modules from §2 |
| `StatScout/Views/Components.swift` | **REWRITE** | New atomic components from §3, keep names that other views reference |
| `StatScout/Views/PlayerProfileView.swift` | **REWRITE** | §4.1 |
| `StatScout/Views/DashboardView.swift` | **REWRITE** | §4.2 |
| `StatScout/Views/TeamView.swift` | **REWRITE** | §4.3 |
| `StatScout/Views/MetricLeadersView.swift` | **REWRITE** | §4.4 |
| `StatScout/Views/SettingsView.swift` | Light-mode rewrite | §4.5 |
| `StatScout/Models/Player.swift` | Add extensions | `initials`, `headshotURL` |
| `StatScout/Data/SampleData.swift` | Set `imageURL` | Use `https://midfield.mlbstatic.com/v1/people/{id}/spots/240` |
| `StatScout/StatScoutApp.swift` | Add `.preferredColorScheme(.light)` | App is light-mode |

XcodeGen will auto-pick up new Swift files in `StatScout/Views/`. Don't touch `project.yml`.

---

## 7. Acceptance Checklist

- [ ] `PlayerProfileView` matches `SAVANT_PLAYER_PAGE_REFERENCE.html` (the companion mockup) within reasonable margin.
- [ ] App background is near-white (#F5F5F5). No navy backgrounds **except** identity strips and the app header.
- [ ] No corner radius exceeds 4pt anywhere except `PlayerHeadshot` (circle).
- [ ] No `.rounded` font design used.
- [ ] No shadows. Separation is hairlines + zebra only.
- [ ] Every percentile-tinted color uses the continuous `SavantPalette.color(forPercentile:)` gradient (no `if pctl > 75` step thresholds).
- [ ] `MetricBar` shows a 12pt circle marker on a 4pt gray track with a 50th-percentile midline. **Not a filled bar.**
- [ ] Stat numbers all monospaced.
- [ ] Section headers all uppercase + tracked + heavy weight.
- [ ] Every player row shows a real MLB CDN headshot (with initials fallback).
- [ ] Leaderboard reads as a table with header row, zebra rows, hairline separators — not as a stack of rounded cards.
- [ ] Identity Strip renders navy with white name and a percentile-colored badge to the right.
- [ ] `PlayerProfileView` is pushed onto the nav stack (back chevron visible), not presented as a sheet.
- [ ] `Update` CTA is `#C71A21` red, 4pt radius.
- [ ] Section bars have a 2pt red leading edge and `surfaceSunk` background.

---

## 8. What NOT To Do

- ❌ Don't add gradient backgrounds (the app's previous navy gradient is gone).
- ❌ Don't add SF Symbol gradient/hierarchical fills or `.symbolEffect`.
- ❌ Don't add emoji.
- ❌ Don't add shadows or `.shadow()` modifiers.
- ❌ Don't use `.rounded` font design.
- ❌ Don't introduce 3rd-party Swift packages.
- ❌ Don't invent new metrics or sections beyond what `Player.metrics` / `Player.games` already provides.
- ❌ Don't change the data model, view-model, API service, or backend.
- ❌ Don't make `MetricBar` a filled rectangle — the marker dot is non-negotiable.

---

## 9. Companion Reference

Open `SAVANT_PLAYER_PAGE_REFERENCE.html` in a browser. It renders:
- The **Aaron Judge player page** at iPhone 14 width (390pt), built with the exact tokens above. This is your visual target.
- A side-by-side dashboard mockup so you can see how the same modules tile into other screens.

When in doubt, **inspect the HTML and copy the values into SwiftUI.** Geometry, colors, typography, and module proportions are all 1:1 with what your SwiftUI implementation should produce.
