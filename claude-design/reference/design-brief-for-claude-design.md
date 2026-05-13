# StatScout — Design Brief for Claude Design

## 1. Project Overview

**Baseball Savvy StatScout** is a native SwiftUI iOS 17+ app that presents Baseball Savant/Statcast-style player percentile pages. The app pulls pre-computed player snapshots from Supabase (nightly ingestion via Python/pybaseball) and renders them as mobile-friendly player cards, leaderboards, and profile views.

**Goal of this brief:** Help Claude Design understand the *current* UI structure, components, data flow, and theming so it can evolve the app toward a closer Baseball Savant aesthetic.

---

## 2. File Structure

```
StatScout/
  StatScoutApp.swift            App entry point, injects DashboardViewModel + StatcastAPI
  Models/
    Player.swift                  Player, Metric, MetricDirection, MetricCategory, GameTrend
  Views/
    DashboardView.swift           Main hub: hero, search, team chips, category filter, featured scroll, leaderboard
    PlayerProfileView.swift       Full player page: header, grouped metric bars, recent games
    MetricLeadersView.swift       Sheet showing best/worst performer per metric
    TeamView.swift                Sheet showing team roster as leaderboard rows
    SettingsView.swift            List-style sheet with refresh info + about
    Components.swift              All reusable UI primitives (theme, bars, badges, cards, chips)
  ViewModels/
    DashboardViewModel.swift        Observable, drives DashboardView filtering + data state
  Services/
    StatcastAPI.swift             Supabase REST provider + PreviewStatcastAPI (sample data)
  Data/
    SampleData.swift              Hardcoded Aaron Judge, Shohei Ohtani, Bobby Witt Jr., Paul Skenes
```

---

## 3. Data Models

### `Player`
- `id: Int` (MLBAM ID)
- `name, team, position, handedness, imageURL, updatedAt`
- `metrics: [Metric]`
- `games: [GameTrend]`
- Computed: `overallPercentile` (average of all metric percentiles), `headlineMetric` (best percentile), `latestPercentileDelta`

### `Metric`
- `id, label, value, percentile, direction, category`
- `MetricCategory` = `.hitting | .pitching | .fielding | .running`
- `MetricDirection` = `.up | .flat | .down`

### `GameTrend`
- `id, date, opponent, summary, percentileDelta, keyMetric`

---

## 4. Current View Hierarchy & Navigation

### Root: `DashboardView` (NavigationStack)
- **HeroHeaderView** — app title, tagline, player count
- **SearchField** — filters by player name or team abbreviation
- **TeamChipRow** — horizontal scroll of unique teams; tapping opens `TeamView` sheet
- **CategoryFilter** — `All | Hitting | Pitching | Fielding | Running` chip row
- **Action row** — `Random Player` button + `Metric Leaders` button
- **Featured section** — horizontal scroll of top 5 `PlayerCard`s; tap opens `PlayerProfileView`
- **Leaderboard section** — vertical list of `LeaderboardRow`s; tap opens `PlayerProfileView`

### Sheets (from DashboardView)
- `.player(Player)` → `PlayerProfileView`
- `.team(String)` → `TeamView` (shows roster of `LeaderboardRow`s)
- `.metricLeaders` → `MetricLeadersView` (shows best/worst per metric)
- `.settings` → `SettingsView` (list with about/refresh info)

### `PlayerProfileView` (NavigationStack)
- `SavantPlayerHeader` — name/team/position + overall percentile badge
- Per-category metric groups: category title + average percentile + `MetricBar` list
- `GameTrendCard`s — recent games with delta, summary, key metric tag

---

## 5. Current Theme (`StatScoutTheme`)

```swift
static let background = LinearGradient(
    [Color(red: 0.03, 0.05, 0.10), Color(red: 0.06, 0.08, 0.16)],
    .top, .bottom
)
static let card = Color.white.opacity(0.08)
static let stroke = Color.white.opacity(0.12)
static let accent = Color(red: 0.38, 0.77, 1.00)   // light blue
static let hot = Color(red: 1.00, 0.37, 0.28)
static let savantBlue = Color(red: 0.09, 0.38, 0.74)  // dark blue (low percentile)
static let savantRed = Color(red: 0.84, 0.16, 0.16)   // red (high percentile)
```

**Current typography:** Heavy use of `.system(size:weight:design: .rounded)`, `.title3.weight(.black)`, `.caption.weight(.bold)`, `.subheadline.weight(.semibold)`.

**Current layout language:**
- Rounded rectangles (12–28pt radius)
- 1px subtle white stroke overlays
- White text on dark navy/black gradient background
- Card backgrounds at `white.opacity(0.04–0.08)`

---

## 6. Key Components (Current State)

### `MetricBar`
- HStack: label (left), value (center-right), percentile number (right)
- `GeometryReader` bar: background track `white.opacity(0.08)` + filled bar scaled by `percentile / 100`
- Vertical white line at 50th percentile
- **Color scale:** ≥75 = savantRed, 50–75 = orange-red, 25–50 = light blue, <25 = savantBlue
- This is the *closest* existing component to Baseball Savant’s percentile bars

### `PlayerCard` (Featured)
- Header: name + team/position + overall percentile badge (48×48)
- Headline metric callout
- Up to 3 `MetricBar`s

### `LeaderboardRow`
- Overall percentile badge (52×52, rounded rect) + name/team/position + headline metric label + percentile

### `SavantPlayerHeader`
- Name (32pt black rounded) + team/position/handedness
- Overall percentile badge (64×64, rounded rect)
- Headline metric callout with star icon

### `PercentileBadge`
- 58×58 circle, accent-colored if >90, otherwise subtle

### `TrendGlyph`
- SF Symbols arrow for `.up/.flat/.down` — green/white/orange

### `FilterChip` / `TeamChipRow`
- Capsule buttons with stroke, accent fill when selected

---

## 7. What “Baseball Savant Style” Means for This Project

Baseball Savant player pages have these distinctive traits:

1. **Percentile Bars** — Horizontal bars with a clear 50th-percentile midpoint line. Red for above-average, blue for below-average. The exact shade progression matters.
2. **Data Density** — Many metrics visible at once, not hidden behind scrolling sections.
3. **Tabular/Grid Layouts** — Tables for leaderboards, not cards. Clean alignment of names, values, and bars.
4. **Team/Position Badges** — Small, compact team abbreviations with color coding.
5. **Player Headshots** — Prominent circular or rounded headshots.
6. **Section Grouping** — Hitting/Pitching/Fielding/Running as clear grouped tables with headers.
7. **Rank + Value + Percentile** — Three-column mental model.
8. **Dark Mode First** — Savant’s dark theme is authoritative; current app is close but can be refined.

---

## 8. Design Gaps / Opportunities (What Needs Work)

| Area | Current | Target |
|------|---------|--------|
| **Percentile bars** | Good start; 4-step color | Should be smoother gradient or true Savant red→blue scale; bar height could be taller |
| **Player headshots** | `imageURL` exists but never rendered | Circular or rounded headshots in cards and profile header |
| **Dashboard density** | Vertical scroll of cards + separate leaderboard | Could unify into a single searchable, sortable table |
| **Featured scroll** | Horizontal card scroll | Could become “Trending / Top 5” compact horizontal strip with headshots |
| **Team chips** | Text-only capsules | Could use MLB-style team color badges or logos |
| **Profile grouping** | VStack per category with rounded cards | Could be tighter table-style sections with less padding, more metrics visible |
| **Game trends** | Cards with prose summaries | Could be more data-forward (date, delta sparkline, key metrics) |
| **Typography** | Rounded black everywhere | Could benefit from a clearer hierarchy: condensed/regular for names, monospace for values |
| **Navigation** | Sheets for everything | Consider pushing `PlayerProfileView` onto the `NavigationStack` instead of sheets for better wayfinding |
| **Leaderboard** | Card rows | A proper sortable table with rank #, headshot, name, team, value, bar |
| **Settings** | Plain list | Minimal; fine as-is |

---

## 9. Data Flow for Context

```
Supabase REST → StatcastAPI.fetchPlayers() → DashboardViewModel.players
                                          ↓
                                    DashboardView (filter/sort)
                                          ↓
                                    PlayerProfileView (player param)
```

- All data is read-only in the app.
- No local persistence yet (planned).
- No images are currently loaded; `imageURL` points to MLB CDN headshots.
- Sample data is used when the API fails or in previews.

---

## 10. Technical Constraints

- **iOS 17+, SwiftUI, Swift 6.0**
- **No external Swift packages** (pure SwiftUI + Foundation)
- **Portrait only**
- **XcodeGen** for project generation (`project.yml`)
- **No always-on server** — static snapshot model
- **Supabase REST** is the only backend contract

---

## 11. Suggested Files to Focus On for Redesign

Priority order for Claude Design intervention:

1. **`StatScout/Views/Components.swift`** — Theme, `MetricBar`, `PlayerCard`, `LeaderboardRow`, `SavantPlayerHeader`, `PercentileBadge`
2. **`StatScout/Views/DashboardView.swift`** — Layout and section organization
3. **`StatScout/Views/PlayerProfileView.swift`** — Profile page structure and metric grouping
4. **`StatScout/Models/Player.swift`** — Only if new computed properties or display helpers are needed

Do **not** need to touch:
- `StatScoutApp.swift`, `StatcastAPI.swift`, `DashboardViewModel.swift`, `SampleData.swift`, backend, or Supabase schema unless navigation architecture changes.
