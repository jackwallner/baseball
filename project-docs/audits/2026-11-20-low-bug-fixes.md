# Low bug fixes, 2026-11-20

Branch `fleet/20261120-211335-c88e-claude`, base `7d6c0bc`. Catalog: `2026-11-20-bug-ux.html`.

Verified after the run, from the Air: full suite on GitHub's Macs, run `baseball-lows-mbaire203-1120-212251-12170`, 201 passed, 0 failed (194 before), including every new test named below. The fix run itself had no GitHub login on its machine, so it could not test.

| Id | Title | Outcome | Commit | Proof | Change |
|----|-------|---------|--------|-------|--------|
| B3 | Subscribers see a red subscription error in Settings offline | fixed | f6cdb02 | none possible in a test (view-local state, RevenueCat not configurable on a simulator); code read only | Settings shows the error only after Restore Purchases was tapped, kept in a local `@State`; launch refreshes still write `lastError` for the plan picker |
| B4 | Non-Gregorian phone calendars put server dates centuries off | fixed | a9cbea5 | `ClockBoundaryTests.testPostgresDatesStayGregorianOnNonGregorianDeviceCalendars`, `testOpeningSeasonIsTheGregorianYearOnNonGregorianDeviceCalendars`, `testCoverageAgeIsInDaysOnNonGregorianDeviceCalendars`, `testProfileWindowHoldsNDatesOnNonGregorianDeviceCalendars` (the catalog's own gh-sim run `repo-imacf6d6-1120-102114-337` showed the same four failing before) | `Calendar.gregorianInSameZone`; `fromPostgresDate`, `StatScoutSeason.calendarYear` and the profile window's day components use it; the two raw `Calendar.current.component(.year)` season fallbacks in `PlayerProfileView` and `TeamView` now call `calendarYear()` |
| B5 | Cancelled recent-form fetch clears the replacement's loading flag and handle | fixed | b2ab074 | `RecentFormTaskOwnershipTests.testReloadWhileFetchingKeepsTheWindowMarkedLoading`, `testJoiningARunningRecentFormFetchAfterAReloadDoesNotDuplicateIt` | Per-request token per window; the fetch's `defer` clears the loading flag and task entry only if it still owns them |
| B6 | Onboarding says "Still loading... Tap again" forever after a failed load | fixed | 0b645ed | none possible in a test (the failure needs RevenueCat configured, which a simulator never is); code read only | Shows `store.lastError` (existing "Check your connection" string) when the offering failed; the "Tap again" line remains only when no error is recorded. No new strings |
| B7 | Foreground refresh cancels an in-flight Trends window it does not restart | fixed (shared cause with B5) | b2ab074 | `RecentFormTaskOwnershipTests.testRefreshRestartsAWindowThatWasStillLoading` | The refresh restarts held windows plus windows still in flight (cataloger suggested only held ones, which would leave the in-flight one on pre-refresh data); the token guard covers the defer half. Catalog marked it plausible: the test reproduces it with a slow provider, so it is no longer only plausible once the test is run |

## Verification

- Final green full-suite run: `baseball-lows-mbaire203-1120-212251-12170`, 201 passed, 0 failed.
- Tests failing on the base commit too: not checked.
- Held on purpose, untouched: PC1.

## For the reviewer

- All four B4 tests use `Calendar(identifier:)` for buddhist, japanese, islamicUmmAlQura, persian, republicOfChina and hebrew. Hebrew and republicOfChina were not in the catalog's list of tried calendars; if one misbehaves, drop it from `nonGregorian`.
- The new tests build against private `SlowRecentFormProvider` timing (400 ms and 150 ms sleeps, polls up to 3 s). They were added to `SeasonContextRegressionTests.swift` rather than a new file because `xcodegen` is not installed here.
- B5/B7 test 1 and 2 sleep 100 ms after the replacement request starts to let the cancelled task unwind; that is the window where the bug showed.
- No Swift compiler ran: read the diff for typos first.
- Settings no longer shows the failed-offering line to free users either (the catalog calls that line accurate for them); the plan picker and Upgrade paths still show it.

