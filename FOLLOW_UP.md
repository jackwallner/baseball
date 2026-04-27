# StatScout Deferred & Follow-up Items

## Immediate Actions Required

1. **Rotate the leaked Supabase anon key** — the old key (`eyJhbGciOiJIUzI1NiIs...`) is in git history forever. Generate a new anon key in the Supabase dashboard and update GitHub Secrets / Xcode scheme env vars.
2. **Set build environment variables** for iOS:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   Add them to your Xcode scheme’s environment variables for local runs, or pass them as build settings (`-DSUPABASE_URL=...`) in CI.
3. **Run `xcodegen generate`** to regenerate the project with the new test target, entitlements, and Info.plist references.
4. **Apply the Supabase migration** to add `created_at` and enforce `season NOT NULL`.

## Deferred Features (Not Bugs)

### Raw Stat Values (CRITICAL-2 lite)
- **Status:** `value` field no longer stores `"100 PCTL"`; it stores `""` when no raw value is available.
- **Why deferred:** pybaseball’s `statcast_*_percentile_ranks` DataFrames contain percentiles (0–100), not raw stats. Real raw values (e.g., `.463 xwOBA`) live in separate Baseball Savant leaderboards or the `statcast_*` detail tables.
- **Next step:** Add a second ingestion pass that fetches raw values from `pybaseball.statcast_batter` / `statcast_pitcher` and merges them into the `value` field by `player_id`.

### Metric Direction / Trends (HIGH-5)
- **Status:** `direction` is still `"flat"` for all metrics.
- **Why deferred:** Computing a real trend requires historical snapshots (previous day/week). The schema now has `created_at`, but a dedicated `player_snapshots_history` table and a trend-comparison job are needed.
- **Next step:** After a few nightly runs accumulate history, add a comparison query and populate `direction`.

### Recent Games Section (HIGH-2)
- **Status:** The `GameTrendCard` and "Recent Games" section are conditionally hidden when `games` is empty.
- **Why deferred:** There is no data source for game-to-game trends in the current ingestion pipeline.
- **Next step:** Integrate a daily box-score or game-log feed (MLB Stats API or pybaseball game logs) and populate the `games` JSONB array.

### Workspace Files
- `IDEWorkspaceChecks.plist` was added, but xcodegen may overwrite `StatScout.xcodeproj` contents on regeneration. Commit the plist after running `xcodegen generate`.
- The empty `swiftpm/` directory is a harmless placeholder for future SPM dependencies.

## Known Limitations

- **Team index** (`player_snapshots_team_idx`) will become useful once team enrichment from pybaseball is fully working. Currently most rows return `"TBD"` because the Savant percentile-rank DataFrame column names vary by pybaseball version.
- **Off-season season logic** defaults to the previous year before April. This is correct but should be overridable via `STATCAST_SEASON` env var.
- **iOS unit tests** compile but cannot be run until `xcodegen generate` creates the `StatScoutTests` target in the Xcode project.
