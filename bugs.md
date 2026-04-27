# StatScout Bug Audit

> Full-path audit of the StatScout iOS app, backend ingestion, Supabase schema, CI/CD, and build config.
> **Do not fix without reviewing each section — many bugs are cross-layer.**

---

## 1. Security & Secrets

### CRITICAL-1: Supabase anon key hardcoded in app binary
- **File:** `StatScout/StatScoutApp.swift:7`
- **Issue:** The Supabase anon key is embedded as a string literal.
- **Impact:** Anyone who extracts the IPA can read the key and query the database.
- **Fix direction:** Move to `Info.plist` / build-time injection, or use a secrets manager.

### HIGH-1: TestFlight upload script exposes Apple ID and email
- **File:** `scripts/upload-testflight.sh:14-15`
- **Issue:** `apple-id` and `username` are hardcoded in the repo.
- **Impact:** PII in git history; breaks for any other developer.
- **Fix direction:** Read from environment variables or local config.

---

## 2. Data Contract / Cross-Layer Mismatches

### CRITICAL-2: Backend stores percentile string in `value`, iOS expects raw stat value
- **File:** `backend/ingest.py:87`
- **Issue:** `build_metrics` sets `"value": f"{percentile} PCTL"`, but the iOS `MetricBar` displays `metric.value` next to the label. The user sees **"xwOBA: 100 PCTL"** instead of **"xwOBA: .463"**.
- **Impact:** Production data makes the app’s primary metric display meaningless.
- **Fix direction:** Pass the raw stat value from the pybaseball row into `value`, not the percentile.

### CRITICAL-3: ISO8601 decoder cannot handle fractional seconds from Supabase
- **File:** `StatScout/Services/StatcastAPI.swift:46`
- **Issue:** `decoder.dateDecodingStrategy = .iso8601` uses `ISO8601DateFormatter` with default options, which does **not** accept fractional seconds. Supabase REST often returns `2026-04-26T20:36:57.123456+00:00`.
- **Impact:** JSON decoding fails for every row with a fractional-second timestamp, causing the entire fetch to throw.
- **Fix direction:** Use a custom `DateFormatter` with `fractionalSeconds` or `ISO8601DateFormatter` configured with `.withFractionalSeconds`.

### HIGH-2: Backend never populates `games`, so Recent Games is always empty in production
- **File:** `backend/ingest.py:115`
- **Issue:** `merge_player_row` hardcodes `"games": []`.
- **Impact:** `PlayerProfileView` conditionally shows the Recent Games section, so it will never appear for real data.
- **Fix direction:** Generate game-trend stubs from a second data source, or remove the section until implemented.

### HIGH-3: Backend hardcodes every player’s team to `"MLB"`
- **File:** `backend/ingest.py:106`
- **Issue:** `"team": "MLB"` ignores whatever team column `pybaseball` returns.
- **Impact:** Team chips, team search, and team roster sheets all collapse to a single "MLB" chip in production.
- **Fix direction:** Map the actual `team` column from the DataFrame row.

### HIGH-4: Backend hardcodes position and leaves handedness blank
- **File:** `backend/ingest.py:107-108`
- **Issue:** Position is always `"Hitter"` / `"Pitcher"` / `"Two-way"`; handedness is `""`.
- **Impact:** Profile headers display generic positions; handedness field is useless.
- **Fix direction:** Map actual `position` and `handedness` / `bats` / `throws` columns from Statcast.

### HIGH-5: Backend hardcodes `direction: "flat"` for all metrics
- **File:** `backend/ingest.py:89`
- **Issue:** Every metric gets `"flat"`, but `MetricDirection` supports `up`/`down`.
- **Impact:** Trend glyphs/directions never reflect actual movement (even though the UI currently ignores them — see DEAD-1).
- **Fix direction:** Compute direction from period-over-period delta, or remove `direction` from the contract until supported.

### MEDIUM-1: Unused backend fields sent to Supabase are ignored by iOS model
- **Files:** `backend/ingest.py:111-113`, `StatScout/Models/Player.swift:14-24`
- **Issue:** `season`, `player_type`, and `source` are upserted but `Player.CodingKeys` does not include them.
- **Impact:** App cannot filter by season or player type; backend bloats rows with unused JSON.
- **Fix direction:** Add fields to `Player` if needed, or drop them from the upsert.

---

## 3. iOS App — Swift Layer

### CRITICAL-4: `DashboardViewModel.load()` silently falls back to sample data on **any** error
- **File:** `StatScout/ViewModels/DashboardViewModel.swift:77-86`
- **Issue:** All exceptions (network, decode, 5xx) trigger the same catch block that loads `SampleData.players` with a generic message.
- **Impact:** Users never see real error states; a broken backend looks like it’s “not connected yet.”
- **Fix direction:** Distinguish decode errors, network errors, and empty responses. Only fall back to sample data in preview/debug builds.

### HIGH-6: `allMetrics` dictionary key collides across categories
- **File:** `StatScout/ViewModels/DashboardViewModel.swift:56-74`
- **Issue:** `metricMap` is keyed by `metric.label` only. A label like `"xwOBA"` exists in both **Hitting** and **Pitching**. The first category processed wins; the second is silently merged into the wrong leaderboard bucket.
- **Impact:** Two-way players (e.g., Ohtani) corrupt the Metric Leaders view.
- **Fix direction:** Key by `(label, category)` tuple or a composite string.

### HIGH-7: `lastUpdated` returns `Date()` when no players are loaded
- **File:** `StatScout/ViewModels/DashboardViewModel.swift:15-17`
- **Issue:** `players.map(\.updatedAt).max() ?? Date()` shows **right now** when the array is empty.
- **Impact:** `SettingsView` displays a false “Last Updated: <today>” timestamp even if the fetch failed hours ago.
- **Fix direction:** Return `nil` or a sentinel when empty; update the UI to show “—”.

### MEDIUM-2: `searchIsTeamQuery` is computed but never consumed
- **File:** `StatScout/ViewModels/DashboardViewModel.swift:23-26`
- **Issue:** The property exists but no view references it.
- **Impact:** Dead logic; intended team-search highlighting is missing.
- **Fix direction:** Use it to style the search field, or remove it.

### MEDIUM-3: `isLoading` is toggled but never rendered
- **File:** `StatScout/ViewModels/DashboardViewModel.swift:12`, `StatScout/Views/DashboardView.swift`
- **Issue:** `DashboardView` never checks `viewModel.isLoading` to show a progress indicator.
- **Impact:** Users tap nothing and see no feedback during the initial fetch.
- **Fix direction:** Add a `ProgressView` overlay when `isLoading == true`.

### MEDIUM-4: No pull-to-refresh on Dashboard
- **File:** `StatScout/Views/DashboardView.swift:30`
- **Issue:** The `ScrollView` lacks `.refreshable`.
- **Impact:** Users must force-quit and reopen to update data.
- **Fix direction:** Attach `.refreshable { await viewModel.load() }`.

### MEDIUM-5: Integer division truncates category/overall averages
- **File:** `StatScout/Models/Player.swift:28`, `StatScout/Models/Player.swift:51`
- **Issue:** `reduce(0, +) / metrics.count` uses Swift integer division. Averages like `75.9` truncate to `75`.
- **Impact:** A player with percentiles `75, 76, 77` shows overall `76` instead of `76` — minor, but inconsistent with Baseball Savant rounding.
- **Fix direction:** Use `Double` average then round.

### MEDIUM-6: Inconsistent percentile color thresholds across views
- **Files:** `StatScout/Views/Components.swift:303`, `StatScout/Views/Components.swift:346`, `StatScout/Views/Components.swift:366`, `StatScout/Views/Components.swift:390`, `StatScout/Views/PlayerProfileView.swift:31`
- **Issue:** Some views use `> 75` for red, others use `>= 75`. Same for `< 25` vs `<= 25`.
- **Impact:** A 75th-percentile metric shows red in one place and white/gray in another.
- **Fix direction:** Centralize threshold constants in `StatScoutTheme`.

### MEDIUM-7: `PlayerCard` headline arrow is always `arrow.up.forward`
- **File:** `StatScout/Views/Components.swift:310`
- **Issue:** The icon is hardcoded, ignoring `metric.direction`.
- **Impact:** A declining metric still shows an up arrow.
- **Fix direction:** Use `TrendGlyph(direction: metric.direction)` instead.

### MEDIUM-8: `GameTrendCard` uses `.black` text on accent-blue capsule
- **File:** `StatScout/Views/PlayerProfileView.swift:97`
- **Issue:** `Text(game.keyMetric)` is `.foregroundStyle(.black)` over `StatScoutTheme.accent` (light blue).
- **Impact:** Poor contrast on some displays; not theme-aware.
- **Fix direction:** Use `.white` or derive from background luminance.

### MEDIUM-9: `MetricBar` mid-range color is hardcoded, not themed
- **File:** `StatScout/Views/Components.swift:444`
- **Issue:** 50–75 range uses inline `Color(red: 0.90, green: 0.40, blue: 0.30)`.
- **Impact:** Inconsistent theming; harder to maintain.
- **Fix direction:** Add a `StatScoutTheme.savantOrange` constant.

### MEDIUM-10: No empty states in MetricLeadersView or TeamView
- **Files:** `StatScout/Views/MetricLeadersView.swift:24-34`, `StatScout/Views/TeamView.swift:28-32`
- **Issue:** If `metrics` or `players` arrays are empty, the views show blank white space with no message.
- **Impact:** Looks like a loading hang or crash.
- **Fix direction:** Add empty-state `ContentUnavailableView` or custom placeholder.

### LOW-1: `PercentileBadge` and `TrendGlyph` are dead code
- **Files:** `StatScout/Views/Components.swift:380-394`, `StatScout/Views/Components.swift:463-486`
- **Issue:** Defined but never instantiated anywhere in the project.
- **Impact:** Build bloat and maintenance overhead.
- **Fix direction:** Delete or wire them into views where they belong.

### LOW-2: `SettingsView` has no actual settings
- **File:** `StatScout/Views/SettingsView.swift`
- **Issue:** The view is purely informational. No toggles, no data-source switch, no account/logout.
- **Impact:** Dead-end UX; users expect actionable controls behind a gear icon.
- **Fix direction:** Add a toggle for sample-data fallback, or remove the gear until settings exist.

### LOW-3: App does not enforce dark mode
- **Files:** `StatScout/Views/*`
- **Issue:** All views assume a dark canvas. If the user enables light mode, `Color.white.opacity(0.08)` backgrounds become nearly invisible and white text becomes unreadable.
- **Impact:** Completely broken UI in light mode.
- **Fix direction:** Add `.preferredColorScheme(.dark)` at the app root, or implement adaptive colors.

### LOW-4: `imageURL` is decoded but never displayed
- **Files:** `StatScout/Models/Player.swift:9`, `StatScout/Views/Components.swift`
- **Issue:** The backend populates MLB headshot URLs, yet `PlayerCard`, `LeaderboardRow`, and `SavantPlayerHeader` ignore them.
- **Impact:** Wasted bandwidth and missing visual identity.
- **Fix direction:** Add `AsyncImage` to header and card views.

### LOW-5: `RandomPlayerButton` does nothing when `players` is empty
- **File:** `StatScout/Views/DashboardView.swift:55-58`
- **Issue:** The closure is only executed if `randomPlayer != nil`; otherwise the button tap is silently ignored.
- **Impact:** Confusing UX on first launch or after a total failure.
- **Fix direction:** Disable the button when empty, or show an alert.

---

## 4. Backend — Python Ingestion

### CRITICAL-5: No error handling around pybaseball network calls
- **File:** `backend/ingest.py:129-130`
- **Issue:** `statcast_batter_percentile_ranks` and `statcast_pitcher_percentile_ranks` are bare calls. If Baseball Savant is down or pybaseball’s scraper breaks (common when Savant HTML changes), the script crashes with an unhandled exception.
- **Impact:** GitHub Actions job fails, zero rows upserted, no data refresh.
- **Fix direction:** Wrap in `try/except`, log traceback, and exit with a non-zero code so Actions shows red.

### CRITICAL-6: No request batching — 700+ row upsert may exceed Supabase limits
- **File:** `backend/ingest.py:144`
- **Issue:** `client.table("player_snapshots").upsert(rows, ...)` sends all ~700 MLB players in one HTTP request.
- **Impact:** Supabase free tier / PostgREST may reject oversized payloads (often ~1 MB or row-count limits).
- **Fix direction:** Batch into chunks of 100–200 rows.

### HIGH-8: `percentile_value` crashes on non-numeric string values
- **File:** `backend/ingest.py:68-71`
- **Issue:** `pd.isna(value)` catches `NaN`/`None`, but if the DataFrame contains a string like `"N/A"`, it passes through and `float("N/A")` raises `ValueError`.
- **Impact:** Script aborts mid-ingest for the specific player; partial data is lost because the upsert happens at the end.
- **Fix direction:** Wrap `float()` in a try/except and return `None` on any exception.

### HIGH-9: Potential pybaseball column-name mismatch for fielding/running metrics
- **File:** `backend/ingest.py:34-36`
- **Issue:** `sprint_speed`, `arm_strength`, and `oaa` are listed in `BATTER_METRICS`, but `statcast_batter_percentile_ranks` may not include these columns (they come from separate Savant leaderboards).
- **Impact:** These metrics are silently skipped for every player; the backend produces incomplete data without logging.
- **Fix direction:** Verify pybaseball column names empirically, or split fielding/running into a separate ingestion pass with the correct API calls.

### MEDIUM-11: `display_name` breaks on names with multiple commas
- **File:** `backend/ingest.py:60-65`
- **Issue:** `value.split(",", 1)` only handles one comma. A name like `"De La Cruz, Elly, Jr."` becomes `"Elly, Jr. De La Cruz"`.
- **Impact:** Incorrect player names for players with suffixes.
- **Fix direction:** Use `rsplit(",", 1)` or a proper name-parsing library.

### MEDIUM-12: `player_id` cast may crash on NaN
- **File:** `backend/ingest.py:76`, `backend/ingest.py:97`
- **Issue:** `int(row["player_id"])` assumes the column is present and non-null. If Savant returns a partial row, this throws.
- **Impact:** Crash aborts the entire script, not just the single row.
- **Fix direction:** Wrap in `try/except` and log bad rows.

### MEDIUM-13: `build_snapshot_rows` lacks logging / observability
- **File:** `backend/ingest.py:125-138`
- **Issue:** No counts of batters vs pitchers, no logging of skipped players, no visibility into column misses.
- **Impact:** Debugging production ingestion failures is guesswork.
- **Fix direction:** Add `logging.info` calls for row counts, skipped counts, and column availability.

### LOW-6: `on_conflict="id"` API compatibility risk with supabase-py 2.x
- **File:** `backend/ingest.py:144`
- **Issue:** The exact positional / keyword argument shape of `upsert(..., on_conflict=...)` changed across major versions of `postgrest-py`. If the pinned `supabase==2.10.0` resolves to an incompatible `postgrest-py` version, the call may silently ignore the conflict clause and insert-duplicates instead of upserting.
- **Impact:** Duplicate primary-key errors or duplicate rows.
- **Fix direction:** Verify the exact API in the resolved dependency tree, or switch to an explicit `insert` with `on_conflict` in the query string.

### LOW-7: `STATCAST_SEASON` defaults to current year even in off-season
- **File:** `backend/ingest.py:15`
- **Issue:** `datetime.now(UTC).year` returns the calendar year. If the job runs in January or February, it requests a season that has no Statcast data yet.
- **Impact:** pybaseball may return an empty DataFrame, resulting in zero upserts and an empty app.
- **Fix direction:** Default to the most recently completed season, or validate the response is non-empty before truncating.

---

## 5. Database / Supabase

### MEDIUM-14: Migration and schema.sql are identical — no incremental history
- **Files:** `supabase/migrations/20260426203657_create_player_snapshots.sql`, `supabase/schema.sql`
- **Issue:** Both files contain the same `create table` + redundant `alter` statements. The migration should be a delta; `schema.sql` should be the current cumulative state. Having the same content in both makes it impossible to reason about what changed when.
- **Impact:** Future migrations will be hard to write and review.
- **Fix direction:** Remove redundant `alter` blocks from the migration (keep them in `schema.sql`).

### MEDIUM-15: Redundant `alter` statements inside the migration
- **File:** `supabase/migrations/20260426203657_create_player_snapshots.sql:16-20`
- **Issue:** `add column if not exists season` immediately follows a `create table` that already defines `season integer`. Same for `player_type`, `source`, and default changes.
- **Impact:** Harmless no-ops, but noise that signals the migration was copy-pasted without review.
- **Fix direction:** Clean up the migration to contain only net-new DDL.

### MEDIUM-16: `season` is nullable despite always being populated
- **File:** `supabase/migrations/20260426203657_create_player_snapshots.sql:9`
- **Issue:** `season integer` has no `not null` constraint.
- **Impact:** Accidental nulls could break season-filtering logic later.
- **Fix direction:** Add `not null` if the ingestion always provides it.

### MEDIUM-17: `player_snapshots_team_idx` is useless until team enrichment is fixed
- **File:** `supabase/migrations/20260426203657_create_player_snapshots.sql:22`
- **Issue:** Every row currently has `team = 'MLB'` (see HIGH-3), so the index has cardinality 1.
- **Impact:** Wasted index maintenance; query planner ignores it.
- **Fix direction:** Fix team enrichment first, then keep the index.

### LOW-8: No `created_at` audit column
- **File:** `supabase/migrations/20260426203657_create_player_snapshots.sql:1-14`
- **Issue:** Only `updated_at` exists.
- **Impact:** Cannot distinguish when a player first appeared vs when they were last refreshed.
- **Fix direction:** Add `created_at timestamptz not null default now()`.

### LOW-9: RLS policy allows unauthenticated `select` but table has no write policy
- **File:** `supabase/migrations/20260426203657_create_player_snapshots.sql:30-34`
- **Issue:** Only a `select` policy exists. Writes default to blocked for anon/service-role contexts depending on PostgREST config.
- **Impact:** Confusing if someone tries to debug-write via REST with the service key; the key bypasses RLS anyway, so the policy is only half-documented.
- **Fix direction:** Add a comment or an explicit `insert`/`update` policy for the service role.

---

## 6. CI/CD & Infrastructure

### HIGH-10: GitHub Actions workflow has no failure notification
- **File:** `.github/workflows/nightly-statcast.yml`
- **Issue:** If the cron job fails, there is no Slack/email/Discord step.
- **Impact:** Data goes stale silently. The app falls back to sample data, so users may not report it.
- **Fix direction:** Add a failure-only notification step (even a simple `if: failure()` email via GitHub’s built-in notifications is better than nothing).

### HIGH-11: GitHub Actions workflow runs at 09:15 UTC — likely before Savant updates
- **File:** `.github/workflows/nightly-statcast.yml:5`
- **Issue:** Baseball Savant daily leaderboards typically update early US morning (EST). 09:15 UTC is 05:15 EDT / 02:15 PDT — often before the data is ready.
- **Impact:** The job ingests yesterday’s data again, or an empty frame.
- **Fix direction:** Move to 14:00 UTC (10:00 EDT) or later.

### MEDIUM-18: No pip caching in GitHub Actions
- **File:** `.github/workflows/nightly-statcast.yml:20-21`
- **Issue:** Dependencies are installed from scratch every run.
- **Impact:** Slower runs; higher chance of PyPI availability issues.
- **Fix direction:** Use `actions/setup-python` with `cache: 'pip'`.

### MEDIUM-19: No workflow timeout
- **File:** `.github/workflows/nightly-statcast.yml`
- **Issue:** A hung pybaseball request could run for 6 hours (default).
- **Impact:** Wasted Actions minutes and delayed queue.
- **Fix direction:** Add `timeout-minutes: 10`.

### MEDIUM-20: No artifact upload on failure
- **File:** `.github/workflows/nightly-statcast.yml`
- **Issue:** When pybaseball crashes, there is no stack trace or partial output artifact to inspect.
- **Impact:** Debugging requires re-running locally with the same env vars.
- **Fix direction:** Upload logs or a JSON dump of the failed DataFrame head.

---

## 7. Xcode Project Misconfiguration (project.pbxproj / xcworkspacedata)

### CRITICAL-7: No PrivacyInfo.xcprivacy manifest — App Store rejection risk
- **File:** `StatScout.xcodeproj/project.pbxproj`
- **Issue:** No `PrivacyInfo.xcprivacy` file is referenced in the build. Apple requires privacy manifests for iOS 17+ apps that use networking, disk, or third-party SDKs.
- **Impact:** App Store Connect will reject the binary during upload or ingestion review.
- **Fix direction:** Add a `PrivacyInfo.xcprivacy` file to the project, list `NSPrivacyCollectedDataTypes` (none or minimal), and include it in the Resources build phase.

### HIGH-12: No unit test or UI test targets
- **File:** `StatScout.xcodeproj/project.pbxproj:118-136`
- **Issue:** The project defines only one `PBXNativeTarget` (the app). There are zero `PBXNativeTarget` entries for tests.
- **Impact:** No automated regression coverage. Refactoring `DashboardViewModel` or `StatcastAPI` is high-risk without tests.
- **Fix direction:** Add a Unit Test target (`xcodegen` can generate it) with tests for JSON decoding, filtering logic, and API error handling.

### HIGH-13: `LastUpgradeCheck` is Xcode 14.3 (1430) but target is iOS 17.0 / Swift 6.0
- **File:** `StatScout.xcodeproj/project.pbxproj:144`
- **Issue:** `LastUpgradeCheck = 1430` means the project file format and recommended settings are frozen at Xcode 14.3. Building with Xcode 15/16 triggers upgrade warnings and may miss modern build-system optimizations.
- **Impact:** Build warnings on first open; potential incompatibility with newer Swift 6.0 compiler diagnostics.
- **Fix direction:** Open in Xcode 15+ and let it modernize, or bump `LastUpgradeCheck` to 1500/1600 in `project.yml` and regenerate.

### HIGH-14: No entitlements file referenced
- **File:** `StatScout.xcodeproj/project.pbxproj`
- **Issue:** There is no `CODE_SIGN_ENTITLEMENTS` build setting and no `.entitlements` file reference. The app has no explicit capability configuration.
- **Impact:** Features like Push Notifications, iCloud, App Groups, or Background Modes cannot be enabled without manual entitlements wrangling. App Store Connect may flag missing expected capabilities.
- **Fix direction:** Add a `StatScout.entitlements` file to the project and set `CODE_SIGN_ENTITLEMENTS` in build settings.

### MEDIUM-22: Release build uses `"iPhone Developer"` code sign identity
- **File:** `StatScout.xcodeproj/project.pbxproj:295`
- **Issue:** Both Debug and Release configurations set `CODE_SIGN_IDENTITY = "iPhone Developer"`. Release should use `"iPhone Distribution"` for App Store archives.
- **Impact:** `xcodebuild -exportArchive` for App Store distribution may fail signing validation unless `-allowProvisioningUpdates` auto-corrects it. This is fragile and CI-unfriendly.
- **Fix direction:** Set `CODE_SIGN_IDENTITY[sdk=iphoneos*]` to `"iPhone Distribution"` for Release in `project.yml`.

### MEDIUM-23: No `PROVISIONING_PROFILE_SPECIFIER` in any config
- **File:** `StatScout.xcodeproj/project.pbxproj`
- **Issue:** Neither Debug nor Release specifies a provisioning profile. The build relies entirely on Xcode’s automatic provisioning.
- **Impact:** CI builds (GitHub Actions, testflight.sh) can fail if the developer machine / runner doesn’t have the right certs/profiles pre-installed. This blocks reproducible builds.
- **Fix direction:** Use environment-variable-based profile specifiers for CI, or document the manual profile setup.

### MEDIUM-24: `GENERATE_INFOPLIST_FILE = YES` with no custom Info.plist reference
- **File:** `StatScout.xcodeproj/project.pbxproj:210, 298`
- **Issue:** The build settings enable auto-generated Info.plist, but there is no `Info.plist` file reference in the project. Privacy keys (e.g., `NSPrivacyAccessedAPIReasons`) and custom URL schemes cannot be declared declaratively.
- **Impact:** Harder to audit what the final Info.plist contains; risk of missing required keys for App Store review.
- **Fix direction:** Generate a static `Info.plist`, add it to the project, and set `GENERATE_INFOPLIST_FILE = NO`.

### MEDIUM-25: No build/run script phases (SwiftLint, R.swift, etc.)
- **File:** `StatScout.xcodeproj/project.pbxproj:122-125`
- **Issue:** The target only has `Sources` and `Resources` build phases. No shell-script phases for linting, code generation, or secrets injection.
- **Impact:** Code style drifts; no automated checks before archive; no build-time secret embedding.
- **Fix direction:** Add a "Run Script" phase for SwiftLint or at minimum a pre-build validation script.

### MEDIUM-26: Empty `packageProductDependencies` — no SPM packages tracked
- **File:** `StatScout.xcodeproj/project.pbxproj:131-132`
- **Issue:** `packageProductDependencies = ( );` is empty. Even though the app may not need third-party packages today, the lack of a `Package.resolved` or workspace-level SPM configuration means adding one later requires manual Xcode GUI steps, defeating the XcodeGen workflow.
- **Impact:** Future dependency additions break the "generate from yml" workflow.
- **Fix direction:** Define any dependencies (even if none) in `project.yml` so XcodeGen creates the proper SPM workspace references.

### MEDIUM-27: `contents.xcworkspacedata` has no shared schemes or workspace settings
- **File:** `StatScout.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- **Issue:** The workspace file only contains `location = "self:"`. No `IDEWorkspaceSharedSettings` or shared scheme references.
- **Impact:** Opening the `.xcodeproj` directly instead of a `.xcworkspace` may cause SPM resolution issues later. Team members lose shared breakpoints and workspace-wide settings.
- **Fix direction:** If using SPM, generate a true `.xcworkspace` with `xcodegen` or commit shared scheme data to `xcshareddata/xcschemes`.

### LOW-13: No `IDEWorkspaceChecks.plist` — workspace integrity warning
- **File:** `StatScout.xcodeproj/project.xcworkspace/xcshareddata/`
- **Issue:** No `IDEWorkspaceChecks.plist` exists in `xcshareddata`. Xcode generates this on first open and flags it as a workspace-change diff.
- **Impact:** Annoying git noise when different team members open the project.
- **Fix direction:** Let Xcode create it once and commit it.

### LOW-14: `xcshareddata/swiftpm/configuration/` directory exists but is empty
- **File:** `StatScout.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/`
- **Issue:** Empty SPM configuration directory. This is leftover scaffolding from an aborted SPM setup.
- **Impact:** Clutter; suggests SPM was started but never configured.
- **Fix direction:** Remove the empty directory or populate it with a real `Package.resolved`.

---

## 8. Build / Config

### MEDIUM-21: `testflight.sh` does not regenerate the Xcode project
- **File:** `scripts/testflight.sh:15-18`
- **Issue:** The script assumes `StatScout.xcodeproj` is up to date. If `project.yml` was modified but `xcodegen generate` was not run, the archive uses stale file lists.
- **Impact:** Missing files or compilation errors in release builds.
- **Fix direction:** Add `xcodegen generate` at the top of the script (with a brew-installed check).

### LOW-10: `project.yml` duplicates `Assets.xcassets` source path
- **File:** `project.yml:15-16`
- **Issue:** `StatScout` already recursively includes `Assets.xcassets`; the second explicit path may create a duplicate reference warning in Xcode.
- **Impact:** Build warning / clutter.
- **Fix direction:** Remove the redundant `- path: StatScout/Assets.xcassets` line.

### LOW-11: `project.yml` uses `UIInterfaceOrientationPortrait` as a scalar string
- **File:** `project.yml:29`
- **Issue:** XcodeGen may or may not wrap this in an array for the generated `Info.plist`. If it emits a string instead of an array, the plist is technically malformed for the `UISupportedInterfaceOrientations` key.
- **Impact:** Potential App Store rejection or unexpected rotation behavior.
- **Fix direction:** Verify generated `Info.plist` contents, or switch to XcodeGen’s array syntax if supported.

### LOW-12: `README.md` claims `DashboardViewModel` defaults to preview API, but `StatScoutApp` uses real API
- **File:** `README.md:41`
- **Issue:** The sentence is misleading: production uses real API, preview uses sample data.
- **Impact:** New contributors may be confused about which endpoint is active.
- **Fix direction:** Clarify that `StatScoutApp` injects the real provider, while previews and unit tests use `PreviewStatcastAPI`.

---

## Bug Count Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 7 |
| HIGH     | 14 |
| MEDIUM   | 27 |
| LOW      | 14 |
| **Total**| **62** |

---

## Recommended Fix Order

1. **Security:** Remove hardcoded API key (CRITICAL-1) and Apple ID (HIGH-1).
2. **Data contract:** Fix `value` field to raw stats (CRITICAL-2) and fractional-second dates (CRITICAL-3).
3. **Backend resilience:** Add `try/except` around pybaseball (CRITICAL-5), batch upserts (CRITICAL-6), and fix `percentile_value` (HIGH-8).
4. **Backend enrichment:** Map real team (HIGH-3), position, handedness (HIGH-4).
5. **iOS reliability:** Stop blanket sample-data fallback (CRITICAL-4), fix `allMetrics` key collision (HIGH-6), add pull-to-refresh (MEDIUM-4).
6. **Polish:** Remove dead code (LOW-1), add empty states (MEDIUM-10), enforce dark mode (LOW-3).
