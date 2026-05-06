# StatScout Release-Readiness Test Plan

A rigorous, screen-by-screen checklist driven by simulator screenshots. Run on the lowest-supported iPhone (iPhone 15 / iOS 17) **and** the largest current device (iPhone 17 Pro Max / iOS 26) **and** any iPad capable. Run each tab in **light** and **dark** system appearance — the app forces light, but verify status bar / system controls render correctly in both.

How to run a screen-driven pass:

```sh
# 1. Boot, build, install
xcrun simctl boot "iPhone 17 Pro"
source ~/.baseball_credentials
xcodegen generate
xcodebuild -project StatScout.xcodeproj -scheme StatScout \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/statscout-build build
xcrun simctl install booted "/tmp/statscout-build/Build/Products/Debug-iphonesimulator/Baseball Savvy StatScout.app"
xcrun simctl launch booted com.jackwallner.baseball

# 2. Drive interactions via idb
idb_companion --udid <udid> &
idb connect localhost 10882
idb ui tap <x_pt> <y_pt>          # tap in device points (iPhone 17 Pro = 402×874)
idb ui swipe <x1> <y1> <x2> <y2>  # scroll
idb ui text "Yankees"             # type into focused field

# 3. Capture
xcrun simctl io booted screenshot /tmp/shot.png
```

---

## 0 · Cold-launch / first-frame

- [ ] Delete the app, reinstall, launch. **First frame** must show: navy header, season pill, search bar, four category tabs, leaderboard column header, and a centered spinner. **No** "About StatScout" link, **no** "No player data is available for the 2026 season" empty state.
- [ ] Status-bar text is **white** over the navy header (not gray).
- [ ] After ≤8 s on simulator, leaderboard populates with the most recent season that has data (currently 2025 — *not* 2026).
- [ ] No crashes on the very first cold launch with an empty cache and slow network.
- [ ] Force-quit → relaunch — second launch reads cache instantly (≤1 s to first row).

## 1 · Dashboard / Leaders tab

### Layout
- [ ] Season pill, search field, and **all four** category tabs (HITTING, PITCHING, FIELDING, RUNNING) are visible — none are clipped at the right edge.
- [ ] Search field accepts input; clearing it restores the unfiltered list.
- [ ] Status bar 12-hr / 24-hr time renders white.
- [ ] Floating bottom tab bar does not permanently obscure rows — user can scroll the last row above the bar.

### Season picker
- [ ] Tapping `Season 2025 ⌄` opens a menu listing every season with bundled or fetched data (currently 2015–2025).
- [ ] 2026 is **not** listed until/unless the live feed actually returns 2026 rows.
- [ ] Selecting a season repaints the leaderboard within ~200 ms.

### Category tabs
- [ ] HITTING / PITCHING / FIELDING / RUNNING each show ≥ 1 player when data is loaded.
- [ ] Selecting a category that has zero qualifying players in the chosen season renders the "No players in category" empty state, **not** a blank scroll area.

### Search
- [ ] Typing a player name filters live; partial matches work ("guerre" → Vladimir Guerrero Jr.).
- [ ] Typing a team abbr or full name filters by team ("NYY", "Yankees").
- [ ] Empty result shows the "No players found — Try a different search term" empty state.

### Leaderboard rows
- [ ] Long names ("Vladimir Guerrero Jr.", "Ronald Acuña Jr.") fit one line via auto-shrinking; never truncate with `…` while there is whitespace beside the row.
- [ ] Avatar circle loads without flicker after first cache.
- [ ] Team color dot matches the abbreviation.
- [ ] Percentile pill color matches the value (red ≥75, blue ≤25, neutral mid).
- [ ] Sort direction arrow flips when the sort header is tapped and "Highest first / Lowest first" is toggled.
- [ ] Sort metric menu lists every metric available in the chosen category for the selected season; checkmark sits on the active metric.
- [ ] Tapping a row navigates to the player profile for **that exact season**.

### Pull-to-refresh
- [ ] Pull-down triggers `viewModel.load()`; the `Through <date>` line updates afterward.
- [ ] Refreshing while offline keeps the cached data and surfaces the "Showing saved data" message — **not** an empty leaderboard.

## 2 · Player profile

### Header
- [ ] Identity strip shows avatar, full name (auto-shrinks if long), team full name, and `Position · Handedness`. With empty handedness, the line shows just "RF" (no trailing `·` or dash).
- [ ] Top-right icon is `arrow.up.right.square` and is labeled "Open on Baseball Savant" for VoiceOver.
- [ ] Back chevron returns to the previous list and preserves scroll position.

### Tab pills (Percentiles / Standard Stats / Year Compare)
- [ ] All three pills are tappable; the active pill is red, others are surface.
- [ ] Switching tabs is instant (<100 ms) and does not refetch data.

### Percentiles
- [ ] PERCENTILE RANKINGS section bar shows the current season picker (chevron only when ≥2 seasons exist for this player) and the ⓘ button that opens a sheet explaining the color scale.
- [ ] Each metric row shows: label, percentile bar (color graded), percentile pill, and **the actual stat value** to the right (e.g., `xwOBA … 100 … 0.460`).
- [ ] Metrics that lack a real value should not show a stale percentile-as-value — verify on `xISO`, `xOBP`, `Hard-Hit%` for an elite hitter and file backend tickets for any that still display only a percentile.
- [ ] Tapping a metric row navigates to the metric leaderboard.
- [ ] The 50-percentile vertical tick on each bar is intentional; if not desired, remove it from `MetricBar`.

### Standard Stats
- [ ] Sectioned by "STANDARD STATS · <year>" with rows for AVG / OBP / SLG / OPS / HR / RBI / R / H / 2B / 3B / BB / SO / SB.
- [ ] Right-aligned monospace numbers; alternating row backgrounds.
- [ ] Empty state when the player has no traditional stats is "Standard stats unavailable".

### Year Compare
- [ ] Lists each year of available history with the player's overall percentile per season.
- [ ] Single-season players see a friendly empty state, not a blank.

## 3 · Teams tab

### Teams list
- [ ] "<year> Season — 30 teams" header is correct.
- [ ] Search filters by abbr or full name.
- [ ] Star toggles a single favorite; the favorite team pins to the top of the list.
- [ ] Tapping a team row navigates to the team detail page.
- [ ] Last visible row is reachable above the floating tab bar by scrolling.

### Team detail
- [ ] Header strip shows team color circle + abbreviation + full name + season label.
- [ ] Players are listed sorted by overall percentile, descending.
- [ ] Tapping a player row navigates to that player's profile in the selected season.
- [ ] Empty state when a team has zero tracked players is "No players tracked for <team>".

## 4 · Metrics tab

### Metric Leaders
- [ ] Sectioned by category (Hitting / Pitching / Fielding / Running), each with METRIC / BEST / LOWEST columns.
- [ ] Long names auto-shrink (`minimumScaleFactor 0.7`) — never `…`-truncate while there is whitespace.
- [ ] Tapping a metric label navigates to the metric ranking page.
- [ ] Tapping a player avatar/name navigates to that player's profile.
- [ ] Section header bar in the navigation says "Metric Leaders".

### Metric ranking page
- [ ] Page title and section bar match the metric (e.g., `xwOBA · Hitting`).
- [ ] **Leaderboard column header reads the metric name** (e.g., `XWOBA`), not "OVERALL".
- [ ] Sort arrow toggles ascending/descending.
- [ ] Empty-state when no players have the metric for the selected season is rendered.

## 5 · About / settings sheet

- [ ] Reachable via the "About StatScout" link at the bottom of the populated leaderboard.
- [ ] Cards: Statscout intro, Data (Nightly Refresh + Last Updated), Support & Privacy (with working external links), Version, Disclaimer.
- [ ] Drag-indicator on the sheet; swipe-down dismisses.
- [ ] All static text legible in light mode (no light-gray-on-white).

## 6 · Color scheme & contrast

- [ ] App is locked to light color scheme via `.preferredColorScheme(.light)` — flipping the system between Light and Dark in Settings does **not** invert the canvas to white text on white backgrounds.
- [ ] Status bar style is `lightContent` (Info.plist) so it stays white over the navy header.
- [ ] All `ContentUnavailableView` instances render readable text on the canvas.

## 7 · Network states

- [ ] **Offline first launch**: app opens with bundled historical data; no spinner stuck; banner explains stale data.
- [ ] **Online but feed broken (5xx / 4xx)**: user keeps cached rows; banner says "Showing saved data. Pull to refresh to try again".
- [ ] **Decode error** (server returns malformed JSON): banner says "Data format changed — app may need an update".
- [ ] **Slow network**: spinner shows on the very first launch only, never on subsequent launches that have cache.

## 8 · Accessibility

- [ ] VoiceOver: every NavigationLink row reads name, team, percentile.
- [ ] Season picker has accessibilityLabel "Season" + value; metric rankings ⓘ button announces "More information".
- [ ] Dynamic Type at the largest accessibility size: text scales without clipping; rows grow vertically.
- [ ] Color isn't the only signal — high/low percentile is also conveyed by the numeric pill.

## 9 · Devices

- [ ] iPhone SE (3rd gen) — narrowest non-Dynamic-Island layout; verify the four category tabs still fit, and the bottom tab bar pill doesn't crowd content.
- [ ] iPhone 17 / iPhone Air — primary target; baseline.
- [ ] iPhone 17 Pro Max — verify generous bottom safe-area inset.
- [ ] iPad (any) — if iPad install is permitted, verify navigation stack adapts; otherwise restrict to iPhone in `TARGETED_DEVICE_FAMILY`.

## 10 · Build / pipeline

- [ ] `xcodegen generate` produces a clean project from `project.yml`.
- [ ] `xcodebuild ... build` succeeds for both Debug and Release with the env vars in `~/.baseball_credentials`.
- [ ] Release archive uploads to TestFlight via `scripts/testflight.sh` without provisioning warnings.
- [ ] `PrivacyInfo.xcprivacy` is bundled (privacy manifest required for iOS 17+).
- [ ] Unit + UI test targets compile (even if currently empty), so future tests can be added without rebuilding the project.
- [ ] No secrets land in commits; `~/.baseball_credentials` stays out of the repo.

---

## Known follow-ups for backend

These are not display bugs in the app — they are real data gaps the app correctly *renders* but should be fixed upstream:

1. `xISO`, `xOBP`, `Hard-Hit%` percentile rows show no actual numeric value next to the bar for some players. The backend should always emit the raw stat alongside the percentile.
2. Some MLB players still have empty `handedness` strings — the profile now hides the dash, but the data should be filled in.
