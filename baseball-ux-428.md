# StatScout UX Flow Audit — April 28, 2026

> Comprehensive walkthrough of every user-facing route, screen transition, and state boundary. Goal: surface friction, dead-ends, and surprising behavior before shipping.

---

## 1. App Launch & Cold Start

### Route: `StatScoutApp.swift` → `RootTabView`

**What happens**
1. App reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `Info.plist` or environment.
2. If either is missing, `fatalError` crashes the app immediately — no graceful fallback, no user-facing message.
3. `RootTabView` is instantiated with a single shared `DashboardViewModel`.
4. `.task { await viewModel.load() }` fires once on first appearance.

**Friction points**
- **Crash on missing config.** A user who sideloads or gets a bad TestFlight build sees an instant crash with no explanation. There is no offline-first experience or "Config missing" sheet.
- **No splash / brand moment.** The first frame is a blank `TabView` while the network request fires. On slow connections the tab bar appears with empty leaderboards for 1–3 seconds.
- **Light mode forced globally.** `preferredColorScheme(.light)` is applied at `WindowGroup`, but the entire UI palette (`SavantPalette.canvas`, `surface`, `ink`) is tuned for dark surfaces. If a user has Light Appearance enabled at the OS level, `canvas` (near-white) plus `inkOnDark` (white) yields invisible text. The app is unreadable in light mode.

**Suggested fixes**
- Replace `fatalError` with a dedicated `ConfigMissingView` that explains the issue and offers a "Retry" button.
- Add a branded launch overlay (or at least a `ProgressView` inside the first tab) while `isLoading && players.isEmpty`.
- Either implement adaptive light-mode colors or lock the app to dark mode with `.preferredColorScheme(.dark)` and ensure every view respects it.

---

## 2. Leaders Tab (`DashboardView`)

### Route: `RootTabView` → `NavigationStack` → `DashboardView`

**What happens**
- Top: `CategoryFilter` chips (`All`, `Hitting`, `Pitching`, `Fielding`, `Running`).
- Middle (conditional): `featuredStrip` with horizontal-scroll "Trending Up" and "Trending Down" tiles.
- Bottom: `leaderboardSection` — search field + ranked table.
- Pull-to-refresh is present (`.refreshable`), which is good.

**Friction points**
- **Search text is wiped when switching tabs.** `RootTabView` has `.onChange(of: selection) { _, _ in viewModel.searchText = "" }`. If a user searches "Judge" in Leaders, switches to Teams to cross-reference, then returns to Leaders, the search is gone. This breaks comparison workflows.
- **Category chips have no counts.** A user tapping `Fielding` might see 3 players total but has no warning — the chip looks identical to `Hitting` which may have 247.
- **Featured strip is invisible when no deltas exist.** `weeklyDelta` is computed from `games` filtered to the last 7 days. Because `backend/ingest.py` hardcodes `"games": []` for every player, `biggestRisers` and `biggestFallers` are always empty in production. The strip simply vanishes with no explanation, making the dashboard feel half-built.
- **"Random Player" button is missing.** The current `DashboardView` no longer contains the Random Player pill referenced in older bug docs. Either it was removed (good) or it was never wired in this build. If it was intentionally removed, the empty space where primary actions once sat is noticeable.
- **No data-freshness indicator on the dashboard.** Users cannot tell if the leaderboard reflects last night’s games or yesterday morning’s stale data. The only timestamp is buried two taps deep in About.
- **Error state is heavy but passive.** When `errorMessage` is set, a `ContentUnavailableView` with "Data Error" + "Retry" appears. However, the `DashboardViewModel` no longer falls back to `SampleData` on error (the old `catch` block that loaded sample data appears to have been removed). This is better, but the error card still consumes the full screen with no suggestion to check Wi-Fi or wait for the nightly job.
- **Leaderboard rows show initials, not photos.** `PlayerHeadshot` exists and supports `AsyncImage`, but `LeaderboardTableRow` uses it at size 28 with a fallback to initials. On first load every row shows gray-circle initials, creating a low-fidelity impression. MLB headshot URLs are already in the model (`headshotURL`).

**Unexpected flows**
- Tapping a featured tile or leaderboard row pushes `Player.self` into the `NavigationStack`. There is no swipe-back gesture because these are standard `NavigationLink` pushes inside a `NavigationStack` — actually, swipe-back **is** supported on iOS 16+, so this is fine. The older bug doc’s complaint about "Done button only" may be stale.

---

## 3. Teams Tab (`TeamsView`)

### Route: `RootTabView` → `NavigationStack` → `TeamsView`

**What happens**
- Static grid of all 30 MLB teams (hardcoded array).
- Each tile shows team abbreviation, color circle, full name, and a red badge with player count.
- Tapping a tile pushes `TeamDestination(abbr: abbr)` → `TeamView`.

**Friction points**
- **All 30 teams render even before data loads.** On first launch every badge shows `0`. The grid is fully interactive, but every destination will be an empty roster. This sets up a "0 players" disappointment loop.
- **No division or league grouping.** Teams are sorted alphabetically by abbreviation (`allTeams.sorted()`). A fan looking for "NYY" scans a flat grid; there is no AL/NL or East/Central/West grouping.
- **Team tiles do not reflect actual roster state from the backend.** `viewModel.players(forTeam: abbr)` filters the in-memory array. If the nightly job fails and the array is empty, all 30 tiles show `0`. There is no "data not loaded yet" vs "team truly has zero tracked players" distinction.
- **Team colors rely on `MLBTeamColor.color(abbr)` which normalizes via `normalizedTeamAbbreviation`.** This works, but `TBD` (the fallback for unmapped teams) maps to `nil` and falls back to `inkTertiary` — a generic gray. If a player has `team = "TBD"`, the team chip and profile header look broken.

**Unexpected flows**
- `TeamsView` does not share the `CategoryFilter` from the Leaders tab. A user cannot filter the roster by hitters vs pitchers. This is probably intentional (team-first), but two-way players like Ohtani are simply sorted by `overallPercentile` with no type badge.

---

## 4. Team Roster Drill-down (`TeamView`)

### Route: `TeamsView` → `TeamDestination` → `TeamView`

**What happens**
- `TeamIdentityStrip` shows team color circle, full name, and "2026 Season" subtitle.
- Roster list uses the same `LeaderboardTableRow` component as the main dashboard, ranked by `overallPercentile` within that team.

**Friction points**
- **"2026 Season" is hardcoded.** `TeamIdentityStrip` has `Text("2026 Season")` as a literal. If the app is used in 2027 or if spring-training data is loaded, the label is misleading.
- **No empty-state messaging beyond the generic.** `TeamView` shows "No players tracked" with `person.2.slash`, but it does not explain *why* (e.g., "Data refreshes nightly — check back tomorrow" or "Nightly job may have failed").
- **Roster rank is team-relative, not league-relative.** The `#` column is `index + 1` inside the filtered array. A user sees "#1" for the best player on the Royals and "#1" for the best player on the Dodgers, but those `#1`s are not comparable. Baseball fans expect a global percentile or league rank next to the team rank.
- **No way to sort or filter within a roster.** Users cannot sort by batting average, last name, or position. Pitchers and hitters are interleaved.

---

## 5. Metrics Tab (`MetricLeadersView`)

### Route: `RootTabView` → `NavigationStack` → `MetricLeadersView`

**What happens**
- Data is pre-computed in `DashboardViewModel.updateAllMetrics()` whenever `players` changes.
- Grouped by `MetricCategory` (Hitting, Pitching, Fielding, Running).
- For each metric, a header row shows `METRIC | BEST | WORST`.
- Tapping a metric label pushes `MetricRoute(label:)` → `MetricRankingView`.
- Tapping a player name in the Best/Worst column pushes `Player.self` → `PlayerProfileView`.

**Friction points**
- **Entire tab is blank until first successful load.** If the user opens the app and immediately taps Metrics before `load()` finishes, they see a generic `ContentUnavailableView` ("No metric data" / "Check back after the nightly update"). This is correct, but the timing is unforgiving — there is no skeleton or shimmer.
- **Metric names are raw backend labels with no glossary.** "xwOBA", "xSLG", "OAA", "Barrel%" are displayed as-is. Casual fans have no in-app way to learn what these mean.
- **"Worst" column may be misleading for metrics where low is good.** For pitching metrics like `xERA` or `Barrel%` (allowed), the "worst" player is the one with the highest (poorest) percentile. The UI does not invert the framing — it simply sorts ascending and calls the bottom "Worst". A 5th-percentile xERA is actually *good* (low earned-run average), but the app labels that pitcher as "Worst". This is a semantic bug in the presentation layer.
- **Two-way players create key collision in `allMetrics`.** `DashboardViewModel.updateAllMetrics()` keys by `"\(metric.label)|\(metric.category.rawValue)"`, which is correct and prevents the old bug where Hitting xwOBA and Pitching xwOBA collided. Verified in `DashboardViewModelTests.swift`.

---

## 6. Metric Ranking Drill-down (`MetricRankingView`)

### Route: `MetricLeadersView` → `MetricRoute` → `MetricRankingView`

**What happens**
- Filters all players to those who have the metric, sorts by that metric’s percentile descending.
- Uses `LeaderboardTableRow` with an optional `metricLabel` override so the percentile bar reflects the specific metric rather than overall.

**Friction points**
- **No toggle for ascending/descending.** For metrics where lower is better (e.g., pitching xERA), users still see highest percentile first. There is no way to flip the sort.
- **No percentile bar color consistency with the main leaderboard.** `PercentileBarMini` uses the same `SavantPalette.color(forPercentile:)` logic, so this is actually consistent now.
- **Title is just the raw metric label.** The nav bar shows "xwOBA" with no category context. A user who navigated through Pitching → xwOBA sees the same title as Hitting → xwOBA.

---

## 7. Player Profile (`PlayerProfileView`)

### Route: Anywhere → `Player.self` → `PlayerProfileView`

**What happens**
- `PlayerIdentityStrip`: headshot (AsyncImage → initials fallback), name, team full name, position / handedness, overall percentile badge.
- `SavantTabs`: `Standard`, `Advanced`, `Splits`.
- **Advanced:** `percentileRankingsCard` — grouped by category, each metric is a tappable row with a percentile bar and value.
- **Standard:** `standardStatsGridCard` — 2-column grid of traditional stats (AVG, OBP, etc.).
- **Splits:** `comingSoon("Splits")` empty state.
- Toolbar trailing: `ShareLink(item: player.shareSummary)`.

**Friction points**
- **"Splits" tab is a permanent dead end.** It has been "coming soon" since at least the last audit. The tab occupies prime horizontal real estate and trains users to distrust the other tabs. Remove the tab until implemented, or gate it behind a feature flag.
- **Standard stats grid shows "unavailable" even when the backend has data.** The empty state message says "Traditional stats will appear after the nightly data refresh." If standard stats are present but the user is on a pitcher with no hitting stats (or vice versa), the message is misleading — they may *never* appear for that player type.
- **Metric bars show raw values and percentiles, but no league average reference.** Baseball Savant shows a faint line at 50th percentile. The app does not, making it hard to visually gauge whether 72nd percentile is "pretty good" or "elite".
- **No game log / trend history.** `games` is always `[]` in production. The profile promises context but delivers only a static snapshot. A user who saw a featured tile claiming "+4 weekly delta" cannot drill into *which* games drove that delta.
- **Share sheet text is well-constructed but the share icon is buried in the nav bar.** It’s discoverable enough, but there is no preview of what will be shared before the sheet opens.
- **Headshot loads from MLB CDN with no caching.** Every profile visit re-fetches the 240px image. Slow networks cause the gray-circle initials to flicker in first.
- **Overall percentile badge is prominent but potentially misleading for two-way players.** Ohtani’s overall is an average of hitting *and* pitching percentiles. A 50th-percentile overall could mask 95th-percentile hitting and 5th-percentile pitching, or vice versa. There is no breakdown hint on the badge.

**Unexpected flows**
- Tapping a metric row inside Advanced pushes `MetricRoute(label: metric.label)` → `MetricRankingView` filtered to *all* players, not just that player’s category. This is fine for exploration but can be disorienting: a pitcher’s `xSLG` row leads to a global leaderboard that includes hitters (if the metric label overlaps).

---

## 8. About Tab (`AboutView`)

### Route: `RootTabView` → `NavigationStack` → `AboutView`

**What happens**
- App description, nightly-refresh explanation, last-updated timestamp, support link, privacy link, version string, disclaimer.

**Friction points**
- **Tab label says "About" but icon is `info.circle`.** Users expect a gear icon for settings. The content is purely informational. Either rename the tab to "About" with no gear expectation, or add actual settings (dark mode toggle, cache clear, data-source info).
- **Last Updated timestamp is the max `updated_at` across all loaded players.** If one player refreshed 2 hours ago and the rest refreshed yesterday, the label shows 2 hours ago — which looks like the whole dataset is fresh. A more honest signal would be "Data from 847 players · freshest 2h ago · stalest 14h ago" or at least the min date.
- **No force-refresh button.** Users who just read "Nightly Refresh" and realize data is stale have no manual recourse. They must pull-to-refresh on the Leaders tab or force-quit.
- **Support link opens a GitHub Pages URL in Safari.** This is fine, but there is no in-app email composer or feedback form for users who don’t want to leave the app.

---

## 9. Cross-Cutting Navigation & State Issues

**Global `DashboardViewModel` is shared across all tabs.**
- Pros: single source of truth; team counts, metric leaders, and search all use the same `players` array.
- Cons: a failure in `load()` affects every tab simultaneously. There is no per-tab retry or partial-success state.

**Tab switch resets search.**
- Cited above. This is the most annoying cross-tab friction. Users exploring via search lose context when they tab away.

**No deep linking or state restoration.**
- If the app is backgrounded and purged, the user returns to the first tab (Leaders) with no recollection of which player profile or team roster they were viewing.
- No URL scheme means users cannot share a link that opens directly to a player or team.

**Navigation stack is not cleared on tab re-selection.**
- iOS standard behavior is to pop to root when re-tapping a tab. `TabView` in SwiftUI does this automatically *only* if you implement the delegate pattern or use the new `tabItem { }` behaviors. In the current code, re-tapping a tab does nothing to the `NavigationStack` — the user stays deep in a player profile, which may be desired or confusing depending on intent.

---

## 10. Data Freshness & Trust Signals

**Where users look for "Is this data current?"**
1. Dashboard — no timestamp.
2. Player profile — no "as of" date.
3. About tab — one aggregated timestamp, easily misinterpreted.

**Missing trust signals**
- No "Updated just now / 6h ago / 1d ago" relative-time label on the dashboard header.
- No visual indicator when data is older than 24 hours (e.g., amber timestamp or banner).
- No explanation of why a player might be missing (qualifying PA/IP thresholds, nightly job delay, off-day).

---

## 11. Edge Cases & Error States

| Scenario | Current Behavior | UX Problem |
|----------|------------------|------------|
| App launches with airplane mode | `errorMessage` set; blank leaderboard with "Can't reach data feed" | No offline cache; no cached player list from last session |
| Nightly job fails, data is 48h old | No warning; timestamp shows max(updated_at) which could be yesterday | User assumes stats are current; makes fantasy decisions on stale data |
| Player has `metrics = []` | `overallPercentile` = 0; badge shows `0` in cold blue | Looks like the player is terrible, when actually they have no tracked stats |
| Player has `standardStats = []` | Grid shows "Standard stats unavailable" | Message implies a temporary gap, but for some players it may be permanent |
| Team has zero tracked players | `TeamView` shows "No players tracked" with `person.2.slash` | No CTA — "Browse all leaders" or "Check back after tonight's games" |
| Search returns zero results | `ContentUnavailableView` with magnifying glass | Correct, but no fuzzy match or "Did you mean?" |
| Two-way player (e.g., Ohtani) | Both hitting and pitching metrics grouped under separate category headers in Advanced tab | Good, but overall badge blends them, masking extremes |
| MetricRankingView for metric with 1 player | Shows `#1` with no comparison context | User cannot tell if this player is league-best or the only qualifier |

---

## 12. Top 10 Friction Points (Ranked by User Impact)

1. **No data-freshness signal on primary screens.** Users cannot tell if they are looking at today’s data or last week’s.
2. **"Splits" tab is permanently dead UI.** Sets expectation and disappoints every user who taps it.
3. **Featured / Biggest Movers strip is invisible in production.** `games` array is always empty, so the most visually engaging part of the dashboard never renders.
4. **Light mode is broken globally.** `preferredColorScheme(.light)` on a dark-themed palette makes the app unreadable.
5. **Search cleared on tab switch.** Destroys comparison workflows.
6. **Standard stats empty-state copy is misleading.** "Will appear after nightly refresh" is false for players who will never have that stat type.
7. **No in-app glossary for advanced metrics.** Casual fans see "xwOBA" and bounce.
8. **Team roster has no league/division context or global percentile reference.** `#1` on a bad team looks identical to `#1` on a good team.
9. **About tab promises settings, delivers static text.** The gear/info mismatch erodes trust.
10. **No offline cache or last-known-good fallback.** Every launch is a network lottery.

---

## Appendix: File References

| File | Relevance |
|------|-----------|
| `StatScout/StatScoutApp.swift` | Launch flow, fatalError, color scheme |
| `StatScout/Views/RootTabView.swift` | Tab architecture, search reset, shared VM |
| `StatScout/Views/DashboardView.swift` | Leaders tab, search, featured strip, error states |
| `StatScout/Views/TeamsView.swift` | Team grid, hardcoded 30 teams, badge counts |
| `StatScout/Views/TeamView.swift` | Roster drill-down, hardcoded season year |
| `StatScout/Views/MetricLeadersView.swift` | Metrics tab, best/worst display |
| `StatScout/Views/MetricRankingView.swift` | Metric-specific leaderboard |
| `StatScout/Views/PlayerProfileView.swift` | Profile tabs, share, standard stats, splits |
| `StatScout/Views/SettingsView.swift` | About tab, last-updated, support links |
| `StatScout/ViewModels/DashboardViewModel.swift` | Data loading, filtering, metric aggregation |
| `StatScout/Models/Player.swift` | Domain model, overallPercentile, weeklyDelta |
| `StatScout/Services/StatcastAPI.swift` | Network layer, decoder, Supabase REST |
| `backend/ingest.py` | Data pipeline, games hardcoded empty, team/position enrichment |
