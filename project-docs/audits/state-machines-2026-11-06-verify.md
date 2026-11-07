VERDICT: PASS

# Verification of the 2026-11-06 state machine fixes

Independent check of `state-machines-2026-11-06-fixes.md` against the review (`state-machines-2026-11-06-review.md`) and the audit (`state-machines-2026-11-06.md`). Change checked: `git diff dd9dd1c269d8b17d3256b1bd510f97ab198d4e6f..HEAD` at HEAD `0acd579d` (commits `f0c1666c` B1, `e19aa2ec` B2, `55ca081e` B3, `db189c0f` C1, plus two docs commits and an empty working-tree snapshot). Every claim was re-read from code; the fixes doc's statements were not reused. No app code or tests were changed.

## Fixes

| ID | Works | Regression check | Evidence |
|---|---|---|---|
| B1 | Yes | Clean | `PlayerProfileView.swift:82` adds `@State hasCountedOpen`; `:347-348` returns early from the counting `onAppear` after the first run. The only work in that `onAppear` is the open counter, the `.playerScouting` pitch and the review moment (`:349-363`); the separate `onAppear { rebuildRecentCurves() }` at `:849` is not guarded, so recent-form curves still rebuild on pop-back. Review route: profile, metric row (`NavigationLink(value: MetricRoute)`), Back. Back no longer re-fires the count, so the first-profile deferral (`opens >= 2`) and the 3rd-open review moment hold. Each pushed `PlayerRoute` (`RootTabView.swift:470`) is a new view identity with fresh `@State`, so a genuinely new profile (including one pushed from a drill-down, `MetricLeadersView.swift:151`) still counts; control test proves it. No `NavigationSplitView` exists, so no detail-column identity reuse. `profileOpenCount` key and format are unchanged, so upgraded users keep their count. |
| B2 | Yes | Clean | `DashboardViewModel.swift:1219-1221` passes `authoritativeFor: StatScoutSeason.current` only when the feed is non-empty and the fetch succeeded; `mergePlayers` (`:1381-1388`) drops only rows whose `season == current`, keeps past seasons and nil-season rows. Empty feed still falls back (`:1218`); the throw paths (`:1240-1251`) never merge. `fetchCurrentPlayers` (`StatcastAPI.swift:77-79`) is filtered `season=eq.current` and pages until a short page, throwing on any HTTP or decode failure (`:339-353`), so a partial page cannot masquerade as authoritative. `loadHistoricalIfNeeded` still calls `mergePlayers` without the season (`:1316`), unchanged. Disk format is untouched: `savePlayers(current)` (`:1239`) is the same call; the cold-launch test loads a file written through `TwoTierPlayerCache` exactly as the old build did. Season rollover: old-season rows in `players-current.json` are not the new season, so they are kept, as before. |
| B3 | Yes | Clean | `DashboardViewModel.swift:1274-1278`: `do { postseasonThrough = try await ... } catch {}` keeps the last value on any throw (timeout, offline, cancellation); a successful `nil` still clears it, and `:1279` still resets the phase when no choice is offered. Readers of `postseasonThrough` (`:393` window anchor, `PostseasonCard.swift:50`, `SettingsView.swift:183,216`, `RootTabView.swift:264-300,528`) only gain stability: a failed request no longer hides the postseason card or the Settings coverage row. The value is not persisted, so no stored data is involved. |
| C1 | Yes | Clean | `StoreService.swift:360` replaces the never-clearable `purchasePending` flag with `pendingPurchaseCount`, incremented at each place the flag used to be set true (`:671`, `:687`, `:693`). At `dd9dd1c2` the flag had no reader except `PendingUnlockAction.dismiss` (checked with `git grep`), so dropping `@Published` and the clear in `apply` (old `:801`) changes nothing else. `TrialPitchSheet.swift:14-31`: `set` records the count, `dismiss` keeps the action only if the count moved while that offer was up. All five owners pass the count at every `set` and every `onDismiss` (Stats `:105,163`, Teams `:119,184`, TeamView `:418,423,472,492,620,965`, PlayerProfile `:328,422,708,743,1322`, StandardStatsLeaders `:587,633`). Neighbouring transitions: retry on the same offer that goes pending again keeps the action (count moves); cancel drops it (as before, since the old flag was reset at purchase start); a sheet shown without `set` (the automatic `.playerScouting` pitch) compares against the last `set`, which keeps an action armed by its own pending purchase, matching the old behaviour; once Pro, `resume` fires before the keep/drop test, as before. `PendingUnlockAction` is in-memory only. |
| PC1 | Held for Jack (correct) | n/a | Confirmed: `StoreService.swift:514-519` documents "Unknown eligibility resolves to true" while `:795` stores `status == .eligible`, so RevenueCat `.unknown` reads as ineligible. Fixing it changes which offer the CTA advertises, a trial-offer change the rules forbid, so holding it is right. No code changed. |

### Disputed

The fixes doc has no "Disputed" section and lists no disputed items, so there is nothing to rule on. The one note it declines (`PlayerComparisonView.swift:196`, review moment in `onAppear`) is a review note, not a claim, and the review itself judged it not worth fixing; leaving it is within the rules.

### What the tests leave open (device checks)

- **B1:** the test asserts the persisted counter and `ReviewPromptTracker.positiveMomentCount` through a real `NavigationStack` with the real `PlayerProfileView`. It suppresses the pitch by exhausting `PaywallGate` for `.playerScouting`, so it does not observe the sheet itself. Device check: fresh install, free user, first profile, tap a metric row, Back: no Full Player Scouting sheet. Interactive swipe-back is not covered either (same `onAppear`, same guard).
- **B2:** behaviour is proved through `DashboardViewModel` with a fake provider and the real `TwoTierPlayerCache`. The Stats board, Teams and Compare all read `players`/`playerHistories` set by `ingestPlayers` (`:1343-1344`), so no extra UI check is needed beyond an in-season smoke test.
- **B3:** proved at the view-model level; the season pill reads `offersPhaseChoice`/`selectedPhase` directly.
- **C1:** both tests drive the `PendingUnlockAction` struct with a hand-held counter. Nothing proves `StoreService` increments `pendingPurchaseCount` on a real Ask to Buy (no RevenueCat seam exists). Device check: child account, locked season, Try Free, Ask to Buy, close; then a different locked season, "Maybe later"; approve or buy later: the board must not jump to the second season. The increment sites were read by hand and mirror the old flag's set sites exactly.

## Scope (check 4)

No failures found.

- No change beyond B1, B2, B3, C1. The `0acd579d` snapshot commit is empty; `b551c9ce` and `d21274cb` touch only the fixes doc and its README line.
- No trial, onboarding, price, paywall-offer, membership or paywall-timing change. B1 restores the documented pitch deferral rather than changing when the pitch is designed to appear; C1 decides only whether an in-memory unlock action survives a dismissal, not whether an offer is shown.
- No backend, App Store Connect or RevenueCat change.
- No UNVERIFIED claim fixed: B1 is CONFIRMED, B2/B3/C1 CONFIRMED-MINOR, and each has a test that fails without the fix (below).
- Nothing stored is cleared on an inferred state. B2 drops rows only on a successful, non-empty, fully paged feed (a fresh network answer); B3 stops clearing on a failure; C1 touches no stored data.
- No stored data format change. `profileOpenCount`, `players-current.json` and the historical cache are read and written exactly as before.
- PC1 held, not changed. All five in-scope items are in the fixes table; none skipped.

## Tests

| Run | GitHub run | Result |
|---|---|---|
| Full suite on HEAD plus launch screenshot: `gh-sim all --scheme StatScout` (dummy `SUPABASE_URL=https://example.invalid`, `SUPABASE_ANON_KEY=verify-dummy`), id `baseball@20261106-233406-d156-claude-mbpro388cb-1106-233617-18895` | `42351982613` | Build ok. **189 passed, 0 failed, 0 skipped.** Matches the fixes doc (189/0/0, run `42338390662`). All 11 `StateMachineRegressionTests` and all 7 edited `PendingUnlockActionTests` passed. |
| Fail-without-fix: throwaway `scratch-revert` branch with `DashboardViewModel.swift` restored to `dd9dd1c2` (B2, B3), the two B1 guard lines removed, and C1's `dismiss` rule set to the old stale-flag behaviour (`if pendingPurchases == 0 { action = nil }`, i.e. keep whenever any purchase ever went pending); tests unchanged. Id `baseball@20261106-233406-d156-claude-mbpro388cb-1107-001614-511` | `42354760682` | **6 of 6 failed as expected:** B1 counter `3` not `1` and review moments `1` not `0`; B2 `[1, 2]` not `[1]` on refresh and on cold launch; B3 `regular` not `postseason` offline and on the quiet timeout, choice hidden; C1 fired `["B"]` not `[]`. The branch was deleted; this branch carries only the verify doc on top of `0acd579d`. |

No new failures, so no flaky or pre-existing comparison was needed. C1's tests cannot compile on `dd9dd1c2` (they use the new `set(pendingPurchases:)` API), so its fail-without-fix proof is the simulated old rule above, not a literal checkout.

## Screens

`gh-sim all` launched the app with `-DuoSeed -DuoTour -DuoRoutes player` and screenshotted the Aaron Judge profile (`shots/launch.png` in the full-suite run): header, tabs, Advanced percentile rows and the tab bar render normally. The view changes are non-visual (an `onAppear` guard and an extra argument to `PendingUnlockAction`); the seeded run is Pro, so the free-user pitch path and the C1 offer sheets were not reachable on screen. That path is listed under device checks.

## Must change

Nothing.

## Notes

- B2 side effect, not a regression: a current-season row that fails lenient decoding (`StatcastAPI.swift:345-346`) now leaves the board in the same session instead of the next cold launch. The old build already dropped it from disk via `savePlayers(current)`, so this only makes the first session match the second.
- The B1 tests mark `.playerScouting` presented twice on the shared `PaywallGate` and never reset it. It did not affect the 189-test run, but a future test of that trigger's gate in the same process would start exhausted.
- Localized text: the diff adds no user-facing strings. Widgets, watch, notifications, undo/edit paths: none exist in this app (audit "Not found"), so none are affected. Day and time zone changes do not touch any changed code.
