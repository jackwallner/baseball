# StatScout Cohesion Audit — April 28, 2026

> Comprehensive cross-layer review of the StatScout iOS app, backend ingestion, Supabase schema, CI/CD, and build config.
> Many surface-level bugs from the prior audit have been fixed. This document focuses on what remains broken,
> half-built, or architecturally incoherent across the stack.

---

## 1. Data Contract Mismatches (Backend → iOS)

### HIGH-1: iOS model hardcodes `season`, `playerType`, and `source` to `nil` despite backend populating them
- **Files:** `StatScout/Models/Player.swift:11-13`, `backend/ingest.py:433-435`
- **Issue:** The backend upserts `season`, `player_type`, and `source` to Supabase. The iOS `Player` struct declares these as `let season: Int? = nil` with a literal default value. Because Swift `Codable` skips decoding when a `let` property has a default value, the app **never reads** these fields from the API response.
- **Impact:** The profile view hardcodes "2026" (`PlayerProfileView.swift:101`). The app cannot filter by season, player type, or data source. The backend wastes bandwidth and storage on JSON the app ignores.
- **Fix direction:** Remove the default values and make them non-optional if the backend always provides them, or drop them from the backend upsert if the app doesn't need them.

### HIGH-2: Backend always writes `games: []` while iOS has full Recent Games UI
- **Files:** `backend/ingest.py:438`, `StatScout/Views/PlayerProfileView.swift` (trend sections), `SampleData.swift:32-35`
- **Issue:** `merge_player_row` hardcodes `"games": []` for every player. The iOS app has `GameTrend` model, decoding keys, `latestGame`, `weeklyDelta`, `biggestRisers`, `biggestFallers`, `FeaturedTile` delta badges, and full UI for Recent Games — all of which render **nothing** in production.
- **Impact:** "Biggest Movers" carousel is always empty for real data. The sample data has fake game trends that make the feature look built during development, but users never see it.
- **Fix direction:** Either implement a nightly game-log ingestion pass (e.g., pybaseball `statcast_search` by player + date), or strip the Recent Games UI from the app until the data exists.

### MEDIUM-1: Two-way player `overallPercentile` averages unrelated metrics
- **Files:** `StatScout/Models/Player.swift:34-38`
- **Issue:** `overallPercentile` takes the arithmetic mean of **all** metrics. A two-way player like Ohtani will have hitting, fielding, running, **and** pitching percentiles averaged together. A 100th-percentile hitter who is a 50th-percentile pitcher shows 75th overall — a meaningless number.
- **Impact:** Leaderboard sorting by "overall" is misleading for the most interesting players. Featured carousel picks based on this number.
- **Fix direction:** Compute `overallPercentile` per category, or use the maximum category average, or split two-way players into separate cards per role.

### MEDIUM-2: `MetricRankingView` cannot disambiguate same-label metrics across categories
- **Files:** `StatScout/Views/MetricRankingView.swift:7-13`, `StatScout/ViewModels/DashboardViewModel.swift:73-89`
- **Issue:** `metricPercentile(for:)` uses `first { $0.label == metricLabel }`. A two-way player has "xwOBA" in both Hitting and Pitching. Tapping "xwOBA" from the Hitting section might show the pitching percentile if it happens to appear first in the array.
- **Impact:** Metric drill-down pages show wrong percentiles for two-way players.
- **Fix direction:** Pass both `label` and `category` in `MetricRoute`, and filter by both.

### MEDIUM-3: FanGraphs standard stats use `qual=1` — includes players with negligible playing time
- **Files:** `backend/ingest.py:339`, `backend/ingest.py:347`
- **Issue:** `batting_stats(season, qual=1)` and `pitching_stats(season, qual=1)` include players with a single plate appearance or a single inning pitched. These players then get merged into the dataset and appear in leaderboards with inflated/deflated percentiles because their Statcast sample sizes are tiny.
- **Impact:** Leaderboards include non-qualifying players, making the app less trustworthy for fantasy or media use.
- **Fix direction:** Use `qual=100` for batters (100 PA) and `qual=10` for pitchers (10 IP) to match FanGraphs default qualifying thresholds.

### MEDIUM-4: `normalize_team_abbr` falls through to raw input, creating data-quality orphans
- **Files:** `backend/ingest.py:234-284`
- **Issue:** If pybaseball returns an unrecognized team string (e.g., `"Los Angeles Angels of Anaheim"` or a typo), `normalize_team_abbr` returns it verbatim. The iOS `normalizedTeamAbbreviation()` has a similar alias map but with different coverage. A team name that slips through the backend aliases won't match the iOS aliases, breaking team search and roster views.
- **Impact:** Players can end up under team codes that exist in neither the 30-team grid nor the alias map.
- **Fix direction:** Normalize to a strict 30-team whitelist; log and reject unrecognized values rather than passing them through.

---

## 2. iOS App — Swift Layer

### MEDIUM-5: `project.yml` hardcodes Supabase secrets in build settings
- **File:** `project.yml:32`, `project.yml:36`
- **Issue:** `SUPABASE_URL` and `SUPABASE_ANON_KEY` are embedded as literal strings in the Debug and Release config sections of `project.yml`. These values are baked into `Info.plist` at build time and therefore into the binary.
- **Impact:** The anon key is readable by anyone who inspects the IPA. While RLS limits writes, a leaked key allows unbounded `select` queries, enabling scraping and potential rate-limit abuse.
- **Fix direction:** Inject via environment variables at build time (`$(SUPABASE_ANON_KEY)`) and reject builds where the variable is empty. Never commit real keys to `project.yml`.

### MEDIUM-6: `PlayerProfileView` hardcodes season year "2026"
- **Files:** `StatScout/Views/PlayerProfileView.swift:101`, `StatScout/Views/PlayerProfileView.swift:147`
- **Issue:** Both the Percentile Rankings card and the Standard Stats grid show "2026" as a literal string. Because `Player.season` is always decoded as `nil` (see HIGH-1), the view cannot display the actual season.
- **Impact:** In 2027 the app will still say "2026". Off-season data will mislead users.
- **Fix direction:** Fix HIGH-1 first, then bind the label to `player.season`.

### MEDIUM-7: `RootTabView` clears search text on every tab switch
- **File:** `StatScout/Views/RootTabView.swift:38-40`
- **Issue:** `.onChange(of: selection)` unconditionally sets `viewModel.searchText = ""`. A user who searches "Judge", switches to Teams to browse, then returns to Leaders loses their search.
- **Impact:** Frustrating UX; state feels ephemeral.
- **Fix direction:** Only clear search when returning to the Leaders tab, or persist search across tabs if it makes sense.

### MEDIUM-8: No local data caching — every cold start hits Supabase
- **Files:** `StatScout/ViewModels/DashboardViewModel.swift:92-117`, `StatScout/StatScoutApp.swift:27`
- **Issue:** The app fetches the entire `player_snapshots` table (~800 rows, ~200 KB JSON) on every launch. No `URLCache`, no disk persistence, no `UserDefaults` timestamp check.
- **Impact:** Slow launches on poor connections. Unnecessary Supabase egress. App is unusable offline (shows error state instead of stale-but-recent data).
- **Fix direction:** Cache the decoded `[Player]` array to disk with a TTL (e.g., 6 hours). Show cached data immediately while refreshing in background.

### LOW-1: `MetricRankingView` navigation title is just the label, no category context
- **File:** `StatScout/Views/MetricRankingView.swift:52`
- **Issue:** Tapping "xwOBA" under Pitching shows a page titled "xwOBA". There is no indication this is the pitching leaderboard, not the hitting one.
- **Impact:** Confusing for two-way players or shared metric labels.
- **Fix direction:** Append category to the title: "xwOBA · Pitching".

### LOW-2: `Player.initials` drops suffixes (Jr., III)
- **File:** `StatScout/Models/Player.swift:108-110`
- **Issue:** `name.split(separator: " ").prefix(2)` takes only the first two words. "Bobby Witt Jr." → "BW", "Vladimir Guerrero Jr." → "VG".
- **Impact:** Headshot placeholders look incorrect for players with suffixes.
- **Fix direction:** Include the last word if it starts with a Roman numeral or "Jr./Sr.".

### LOW-3: `TeamsView` eagerly computes `playerCount` for every team tile on every render
- **File:** `StatScout/Views/TeamsView.swift:25`
- **Issue:** `viewModel.players(forTeam: abbr).count` filters the full player array (O(n)) inside a `ForEach` over 30 teams. This is O(30n) = O(n) but repeated on every SwiftUI evaluation.
- **Impact:** Minor performance hit; acceptable for 800 players but scales poorly.
- **Fix direction:** Pre-compute a `Dictionary<String, Int>` in the view model.

### LOW-4: `AboutView` tab is labeled "About" but icon is `info.circle`
- **File:** `StatScout/Views/RootTabView.swift:34`
- **Issue:** Users looking for Settings will not tap "About". The gear-like icon (`info.circle`) suggests settings, but the page has no toggles, no cache-clear, no theme switch.
- **Impact:** The prior audit called this a dead-end UX; the rename to "About" partially fixed it but the icon still mismatches.
- **Fix direction:** Use `gear` icon if adding settings later; otherwise accept the `info.circle` as-is.

### LOW-5: ShareLink generates text but no deep link or rich preview
- **File:** `StatScout/Views/PlayerProfileView.swift:42`
- **Issue:** `ShareLink(item: player.shareSummary)` shares plain text. There is no URL, no universal link, no Open Graph metadata.
- **Impact:** Shared messages in iMessage look like raw text, not a rich card.
- **Fix direction:** Build a web-hosted player profile page (e.g., GitHub Pages) and share that URL with the summary as the preview text.

---

## 3. Backend — Python Ingestion

### MEDIUM-9: `_fetch_standard_stats` silently swallows exceptions and returns empty DataFrames
- **Files:** `backend/ingest.py:337-353`
- **Issue:** `batting_stats` and `pitching_stats` are wrapped in `try/except` that logs and returns empty DataFrames. If FanGraphs is down or rate-limits the request, the ingestion continues with zero standard stats for every player.
- **Impact:** Standard stats tab shows "Standard stats unavailable" for all players. The app looks broken even though percentile data is fine.
- **Fix direction:** Treat FanGraphs failure as a warning, not a silent zeroing. Consider standard stats non-critical and let the app show a "temporarily unavailable" message rather than a generic empty state.

### MEDIUM-10: Standard stats name normalization is fragile across data sources
- **Files:** `backend/ingest.py:311-312`, `backend/ingest.py:493-499`
- **Issue:** Standard stats are looked up by `_normalize_name(row["Name"])`, which strips dots and apostrophes. pybaseball Statcast names are "Ohtani, Shohei" while FanGraphs names are "Shohei Ohtani" (the `display_name` function reverses Statcast's `Last, First` format). But for names like "Guerrero Jr., Vladimir" vs "Vladimir Guerrero Jr.", the normalization may mismatch because the comma placement differs.
- **Impact:** Some players never get standard stats attached despite appearing in both datasets.
- **Fix direction:** Use `player_id` (MLBAM ID) as the join key instead of name. Map FanGraphs rows by `playerid` to MLBAM ID via pybaseball's player ID lookup.

### MEDIUM-11: MLB roster lookup makes 60+ HTTP requests sequentially
- **File:** `backend/ingest.py:356-391`
- **Issue:** For each of ~30 teams, the script fetches both `active` and `40Man` rosters in a blocking `for` loop. If MLB Stats API is slow or rate-limits, the ingestion times out.
- **Impact:** GitHub Actions 10-minute timeout is generous but wasteful. A slow API day causes the entire job to fail even though percentile data might be fine.
- **Fix direction:** Parallelize with `asyncio`/`aiohttp`, or make roster enrichment an optional second step that doesn't block the main upsert.

### LOW-6: `STATCAST_SEASON` env var overrides `_default_season` with no validation
- **File:** `backend/ingest.py:33`
- **Issue:** If someone sets `STATCAST_SEASON=2099`, the script will request that year from pybaseball, get an empty DataFrame, and exit with error. The env var is not validated against a reasonable range.
- **Impact:** Accidental misconfiguration causes a failed workflow.
- **Fix direction:** Clamp to `[_default_season() - 1, _default_season()]` or validate against known Statcast history (2015–present).

### LOW-7: `build_metrics` silently skips metrics when pybaseball column names drift
- **File:** `backend/ingest.py:195-214`
- **Issue:** `if key not in row: continue` means a renamed column (e.g., Savant renames `exit_velocity` to `avg_exit_velocity`) disappears without a trace. The nightly workflow logs missing columns at the DataFrame level, but not which specific metrics were skipped per player.
- **Impact:** Data quality degrades over time as Baseball Savant evolves its CSV exports. Users notice missing metrics before developers do.
- **Fix direction:** Log each skipped metric with the player's name and ID. Add a nightly metric-coverage report (e.g., "xwOBA present for 98% of players").

---

## 4. Database / Supabase

### MEDIUM-12: No composite index for common query patterns
- **File:** `supabase/migrations/20260426203657_create_player_snapshots.sql:18-22`
- **Issue:** Indexes exist on `team`, `position`, `updated_at`, `season`, and `player_type` individually. The app fetches `select * order by updated_at desc` — a single-column index is fine. But future features (e.g., "best hitters on the Yankees") will need `(team, player_type, season)` or similar composites.
- **Impact:** Query performance degrades as filters stack.
- **Fix direction:** Add a composite index on `(season, team, player_type)` once those filters are wired into the API.

### LOW-8: `games` JSONB column is always `'[]'` — wasted storage and I/O
- **Files:** `supabase/migrations/20260426203657_create_player_snapshots.sql:15`, `backend/ingest.py:438`
- **Issue:** Every row stores an empty JSON array for `games`. At 800+ players, this is minor, but it bloats every `select *` response.
- **Impact:** Unnecessary bandwidth. Schema implies a feature that doesn't exist.
- **Fix direction:** Drop the column until game trends are implemented, or store them in a separate `player_games` table (one row per game) for proper indexing and time-series queries.

---

## 5. CI/CD & Infrastructure

### MEDIUM-13: Failure notification posts to a static issue number (#1)
- **File:** `.github/workflows/nightly-statcast.yml:45-56`
- **Issue:** `github.rest.issues.createComment({ issue_number: 1, ... })` assumes issue #1 exists and is open. If the repo has no issues, or #1 is closed/locked, the notification step fails.
- **Impact:** Silent failure of the failure-notification step. The `continue-on-error: true` hides it.
- **Fix direction:** Use a dedicated Slack/Discord webhook, or create an issue programmatically with `github.rest.issues.create` and store the number as an Actions output.

### MEDIUM-14: Cron at 08:00 UTC may be before Baseball Savant updates
- **File:** `.github/workflows/nightly-statcast.yml:5`
- **Issue:** 08:00 UTC is 4:00 AM EDT / 1:00 AM PDT. Baseball Savant daily leaderboards typically update between 3:00–6:00 AM ET after the West Coast games finish. The job may run before the data is ready, ingesting yesterday's data again.
- **Impact:** Data is effectively 24–48 hours stale.
- **Fix direction:** Move to 14:00 UTC (10:00 AM EDT) or later, or add a check that verifies the pybaseball DataFrame's `last_updated` or row count changed from the previous run.

### LOW-9: Artifact upload on failure only includes source code, not logs
- **File:** `.github/workflows/nightly-statcast.yml:36-44`
- **Issue:** The artifact path is `backend/tests/` and `backend/*.py`. It does not include `pytest` output, `pip` logs, or the actual stdout from the ingestion script.
- **Impact:** Debugging a failure requires re-running locally with the same env vars.
- **Fix direction:** Redirect ingestion output to a log file and upload it, or use `actions/upload-artifact` to capture the full `GITHUB_WORKSPACE` logs.

---

## 6. Xcode Project & Build Config

### MEDIUM-15: `StatScout.entitlements` is an empty placeholder
- **File:** `StatScout/StatScout.entitlements`
- **Issue:** The file contains only a comment. It is referenced in `project.yml` and `CODE_SIGN_ENTITLEMENTS` but contributes nothing to the signed binary.
- **Impact:** Adding capabilities later (e.g., push notifications for nightly refresh alerts) requires regenerating the entitlements file and reconfiguring the Apple Developer Portal. The placeholder gives a false sense of readiness.
- **Fix direction:** Either remove the file and `CODE_SIGN_ENTITLEMENTS` setting until needed, or add the explicit `<dict/>` with a comment that no capabilities are enabled.

### LOW-10: `PrivacyInfo.xcprivacy` claims `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1`
- **File:** `StatScout/PrivacyInfo.xcprivacy`
- **Issue:** Reason `E174.1` is "Disk space check for app functionality." The app does not check available disk space. It uses `URLSession` and `SwiftUI` only. This privacy manifest entry appears to be copy-pasted from a template.
- **Impact:** App Store review may flag a mismatched privacy manifest. If Apple audits the reason code against actual API usage, it could delay approval.
- **Fix direction:** Remove the `NSPrivacyAccessedAPITypes` array entirely if the app uses no required-reason APIs. Add `NSPrivacyCollectedDataTypes` documentation even if empty.

### LOW-11: `project.yml` duplicates `Assets.xcassets` path
- **File:** `project.yml:16`
- **Issue:** `StatScout` is recursively included as a source path, which already contains `Assets.xcassets`. The explicit `Assets.xcassets` path may cause a duplicate reference warning.
- **Impact:** Build warning clutter.
- **Fix direction:** Remove the redundant explicit path.

---

## 7. Cross-Layer Cohesion — The "Not Cohesive" List

These are not single bugs but architectural mismatches that make the codebase feel half-finished:

### C-1: The "Recent Games" ghost feature
- Backend: empty array. iOS: full model, decoding, view model logic, UI cards, preview data, and tests.
- **Verdict:** Either build the ingestion or delete the iOS code until it's ready.

### C-2: The "Splits" tab tease
- `PlayerProfileView` has a "Splits" tab that always renders `comingSoon("Splits")`.
- **Verdict:** Remove the tab until there is a data source and backend contract for splits data.

### C-3: Standard stats from two different data sources with no provenance
- Percentile data comes from Baseball Savant. Standard stats come from FanGraphs. The app presents them side-by-side as if they're from the same source and same player pool, but the qualifying thresholds differ (`qual=1` in FanGraphs vs whatever Savant uses).
- **Verdict:** Add a subtle source citation ("FanGraphs" / "Baseball Savant") or align the qualifying logic.

### C-4: `season` is a ghost field
- Backend writes it, database stores it, iOS ignores it, UI hardcodes a year.
- **Verdict:** Fix the decode path or remove the field from all layers.

### C-5: Two-way players are not first-class
- The backend detects two-way players and merges their metrics. The iOS app shows all metrics in one list with category headers. `overallPercentile` averages unrelated skills. `MetricRankingView` cannot distinguish hitting vs pitching xwOBA.
- **Verdict:** Treat two-way players as two distinct personas (hitter card + pitcher card) or add a role toggle in the profile.

---

## Bug Count Summary

| Severity | Count |
|----------|-------|
| HIGH     | 4     |
| MEDIUM   | 15    |
| LOW      | 11    |
| Cohesion | 5     |
| **Total**| **35** |

---

## Recommended Fix Order

1. **Data contract:** Remove or wire `season`, `playerType`, `source` (HIGH-1). Fix `overallPercentile` for two-way players (MEDIUM-1).
2. **Kill or build Recent Games:** Either ingest game trends (HIGH-2) or strip the UI and model fields.
3. **Security:** Move Supabase key out of `project.yml` (MEDIUM-5).
4. **Backend quality:** Fix FanGraphs `qual` thresholds (MEDIUM-3), use `player_id` for standard stats join (MEDIUM-10), parallelize roster lookup (MEDIUM-11).
5. **iOS polish:** Cache player data (MEDIUM-8), fix metric ranking category disambiguation (MEDIUM-2), stop clearing search on tab switch (MEDIUM-7).
6. **CI/CD:** Fix failure notification target (MEDIUM-13), adjust cron time (MEDIUM-14).
7. **App Store readiness:** Fix privacy manifest (LOW-10), clean up entitlements placeholder (MEDIUM-15).
