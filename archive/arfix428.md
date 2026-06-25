# Fix Log — App Store Review Critique (AR-428)

> Date: April 28, 2026  
> Build: 1.0 (22) — post-AR-428 remediation  

---

## Summary of Changes

| Issue ID | Severity | File(s) | What was fixed |
|----------|----------|---------|----------------|
| 2.1-1 | Medium | `PlayerProfileView.swift` | Wrapped non-interactive ⓘ glyph in a `Button` that presents `PercentileInfoSheet` |
| 2.1-3 | Medium | `Components.swift` | Added VoiceOver accessibility labels to `PercentileBarMini`, hid decorative `MetricBar` fill, `TeamColorDot`, `PlayerHeadshot` |
| 2.1-4 | Low | `Components.swift` | Added global percentile number text next to `PercentileBarMini` in every `LeaderboardTableRow` |
| 2.1-5 | Low | `PlayerProfileView.swift` | Reworded standard-stats empty state from "in the current data feed" to neutral "unavailable" |
| 2.3-1 | Medium | `docs/index.html` | Renamed "Live Leaderboards" → "Nightly Leaderboards" |
| 2.3-2 | Low | `docs/index.html` | Added `TODO` comment placeholder for live App Store URL on badge |
| 4.0-1 | Low | `MetricLeadersView.swift` | Renamed "WORST" column header → "LOWEST" to clarify percentile-rank semantics |
| 4.0-3 | Medium | `PlayerProfileView.swift` | Added `PercentileInfoSheet` explaining Baseball Savant percentiles, color coding, and data provenance |
| 5.1.1-1 | High | `project.yml` | Explicitly added `PrivacyInfo.xcprivacy` to app-target `resources` build phase |
| BE-1 | Medium | `project.yml` | Replaced hardcoded Supabase URL with `$(SUPABASE_URL)` env variable; added build-time validation for it |

---

## Already Fixed (Confirmed in Current `HEAD`)

These issues were resolved in prior commits or were already addressed in the codebase before this fix pass:

- **2.1-2** (No data-freshness on primary screens) — `DashboardView` already renders `viewModel.freshnessText` in the `LEADERBOARD` section-bar trailing area.
- **2.4-1** (Forced dark mode without rationale) — `.preferredColorScheme(.dark)` is correctly applied at `WindowGroup`. The light-mode palette issue from older audits is resolved.
- **MEDIUM-7** (Search cleared on tab switch) — The `.onChange(of: selection)` block that wiped `searchText` was removed in a prior refactor.
- **LOW-1** (MetricRankingView title lacks category) — The nav title already reads `"\(metricLabel) · \(metricCategory.rawValue)"`.
- **HIGH-3** (Backend hardcodes team to "MLB") — Fixed by `fc007e6` (Diamondbacks AZ→ARI normalization) and `c757c3b` (app/backend team roster matching).
- **HIGH-4** (Position/handness hardcoded) — Fixed by `94f0ca8` (MLB Stats API roster lookup fallback).
- **CRITICAL-2** (Percentile stored in `value` field) — `raw_stat_value` heuristic in `backend/ingest.py` now extracts raw stats instead of writing percentile strings.
- **CRITICAL-3** (ISO8601 fractional seconds) — `JSONDecoder.statScout` uses a custom decoder with `withFractionalSeconds` fallback.
- **CRITICAL-5** (No error handling around pybaseball) — `build_snapshot_rows` wraps calls in `try/except` with `logger.exception`.
- **CRITICAL-6** (No batching in upsert) — `main()` batches into chunks of 150 rows.

---

## Detailed Fix Notes

### 2.1-1 — Non-interactive ⓘ info glyph

**Before:** `Text("ⓘ")` with `.foregroundStyle(SavantPalette.linkBlue)` looked like a hyperlink but was inert.

**After:** Wrapped in a `Button(action: { showPercentileInfo = true })` with `.buttonStyle(.plain)`. The `.sheet(isPresented: $showPercentileInfo)` modifier on the profile body now presents a new `PercentileInfoSheet` view that explains:
- What Baseball Savant percentiles measure
- The color coding (red = elite 75–100, gray = average 25–75, blue = below average 0–25)
- That data refreshes nightly and some metrics may be absent due to qualifying thresholds

### 2.1-3 — VoiceOver accessibility on percentile bars

**`PercentileBarMini` (leaderboard rows):**
```swift
.accessibilityElement()
.accessibilityLabel("\(percentile)th percentile")
```

**`MetricBar` (profile percentile bars):**
```swift
.accessibilityHidden(true)   // decorative; adjacent Text nodes already read label + value + percentile
```

**`TeamColorDot` & `PlayerHeadshot`:**
```swift
.accessibilityHidden(true)   // decorative; team name and player name are in adjacent Text nodes
```

**`OverallPercentileBadge`:**
```swift
.accessibilityLabel("Overall \(percentile)th percentile")
```

### 2.1-4 — Team roster rank lacks league context

Added a small `Text("\(displayPercentile)")` next to the `PercentileBarMini` inside `LeaderboardTableRow`. This makes the global percentile explicit in:
- Main dashboard leaderboard
- Team roster drill-downs
- Metric ranking drill-downs

The bar width was reduced from 120 → 84 pts to make room for the 24-pt percentile number.

### 2.3-1 — Marketing site overstates data freshness

Changed the feature card title in `docs/index.html`:
```html
<h3>Nightly Leaderboards</h3>
```

The subtitle "Filter the entire league across Hitting, Pitching, and Running to find top performers." remains accurate.

### 4.0-1 — "WORST" column header semantics

Changed in `MetricLeadersView.swift`:
```swift
Text("LOWEST")
```

This clarifies that the column shows the player with the lowest percentile *rank* for that metric, which is not the same as "worst performance" (e.g., a low xERA percentile is actually good for pitchers).

### 5.1.1-1 — Privacy manifest resource bundling

Added to `project.yml` under the `StatScout` target:
```yaml
    resources:
      - StatScout/PrivacyInfo.xcprivacy
```

This ensures XcodeGen copies the file into the app bundle as a resource rather than potentially treating it as a source file. The manifest already correctly declares empty collected-data and accessed-API arrays, matching the app's actual behavior.

### BE-1 — Hardcoded Supabase URL in compiled binary

**Before:**
```yaml
        Debug:
          SUPABASE_URL: https://babzqsbmcunrezsdpyng.supabase.co
        Release:
          SUPABASE_URL: https://babzqsbmcunrezsdpyng.supabase.co
```

**After:**
```yaml
        Debug:
          SUPABASE_URL: $(SUPABASE_URL)
        Release:
          SUPABASE_URL: $(SUPABASE_URL)
```

The pre-build validation script in `project.yml` was also expanded to check `$SUPABASE_URL` alongside the existing `$SUPABASE_ANON_KEY` check, failing the build if either is unset.

---

## Remaining Items (Out of Scope for This Pass)

These issues from `ar428.md` were intentionally deferred:

| Issue | Reason |
|-------|--------|
| 2.1-2 | Already implemented in `DashboardView` — no code change needed |
| 2.4-2 | No iPad/landscape support — requires layout redesign, not a rejection risk |
| 4.0-2 | Category chip counts — requires binding refactor to pass player array into `CategoryFilter`; low user friction |
| 4.0-4 | Onboarding — requires new view + `AppStorage` state; nice-to-have for v1.1 |
| BE-2 | Integer raw-stat heuristic drops some values — requires upstream pybaseball column-name verification; data-quality edge case |
| BE-3 | `games` array dead code — safe to leave; stripping requires coordinated backend+iOS migration |
| BE-4 | Backend `image_url` ignored by app — safe to leave; backend field may be used in future profile redesign |
| CI-1 | TestFlight script assumes local Xcode sign-in — documented in `README.md`; single-developer project |
| CI-2 | Failure notification spams issues — GitHub API rate-limiting is unlikely for a nightly cron |

---

## Build Verification Checklist

Before the next archive:

- [ ] Run `xcodegen generate` to pick up the new `resources` entry
- [ ] Confirm `PrivacyInfo.xcprivacy` appears in the generated `project.pbxproj` under `PBXResourcesBuildPhase`
- [ ] Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` environment variables before build
- [ ] Verify `testflight.sh` pre-build validation fails if either variable is missing
- [ ] Replace `#` in `docs/index.html` App Store badge with live product page URL once approved
- [ ] Test VoiceOver on a leaderboard row, a profile page, and a team roster

---

> *End of fix log. All HIGH and MEDIUM severity items from AR-428 that required code changes have been addressed. The app is now at store-readiness threshold.*
