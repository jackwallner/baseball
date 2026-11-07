# Fixes for the 2026-11-06 state machine audit

Fixes for every claim `state-machines-2026-11-06-review.md` marked CONFIRMED or CONFIRMED-MINOR, in the review's ranked order, plus the one product call it called a bug (PC1).

**Summary: 5 in scope. 4 fixed, 1 held for Jack, 0 skipped.**

## Claims

| ID | Outcome | Commit | Regression test (`StatScoutTests/StateMachineRegressionTests.swift`) | What changed |
|---|---|---|---|---|
| B1 | Fixed | `ac6d569e` | `testReturningToOneProfileFromADrillDownIsNotANewProfileOpen` (reused from the repro, which the review called sound UI-level evidence), control `testOpeningTheProfileTwiceCountsTwice` | `PlayerProfileView` counts an open once per pushed profile: a `@State hasCountedOpen` guard in `onAppear`, which fires again on every pop back from a drill-down. The pitch deferral and the review moment both read that count, so both are fixed. |
| B2 | Fixed | `e46e6822` | `testRefreshDropsAPlayerTheServerPruned` (repro), `testColdLaunchFromAnExistingCacheDropsThePrunedRowAndKeepsPastSeasons` (the review's cold-launch check through the real `TwoTierPlayerCache`, now asserting the clean result on the first launch), controls `testRefreshStillReplacesARowThatIsInTheFeed`, `testRefreshKeepsPastSeasonRowsTheCurrentFeedDoesNotCarry` | `DashboardViewModel.load()` treats a successful non-empty current-season feed as authoritative for that season: `mergePlayers(replacing:authoritativeFor:)` drops current-season rows the feed no longer carries and keeps every past season. An empty feed still falls back to the saved rows. |
| B3 | Fixed | `97932208` | `testOfflineResumeKeepsTheSelectedPostseasonBoard` (repro), `testThroughDateTimeoutKeepsTheSelectedPostseasonBoard` (the review's quiet online-timeout variant), control `testThroughDateOfNilStillHidesThePostseason` | A thrown through-date request keeps the last known `postseasonThrough` (a `do`/`catch` instead of `try?`, as the coverage fetch already does). A successful nil still hides the Postseason board. |
| C1 | Fixed | `a979194b` | `testUnapprovedAskToBuyDoesNotArmALaterDismissedOffer` (the review's check, which proved the stale keep), control `testAskToBuyOnTheSecondOfferStillKeepsItsAction`; the existing `PendingUnlockActionTests` moved to the new API | `StoreService.purchasePending` (a flag nothing could clear after a declined Ask to Buy) is replaced by a monotonic `pendingPurchaseCount`. `PendingUnlockAction.set` records the count when its offer opens and `dismiss` keeps the action only if the count moved while that offer was up. All five owners pass the count. |
| PC1 | Held for Jack | none | none | See below. |

Not a claim: the review's note that `PlayerComparisonView.swift:196` records a review moment in `onAppear` (the same pattern as B1). The review judged it not worth a separate claim because only the pending flag changes and the 30-day cooldown paces it; it is left as is.

## Held for Jack

- **PC1, trial wording when intro-offer eligibility is unknown.** The doc comment on `StoreService.isEligibleForIntroOffer` says unknown eligibility shows the trial, but `refreshIntroEligibility` stores RevenueCat's `.unknown` as ineligible, so a failed eligibility lookup hides the trial wording. Fixing it changes which offer the paywall and trial pitch advertise, so it is a trial-offer change. Decision: when RevenueCat cannot tell whether a user is trial-eligible, should the CTA name the free trial (as the comment says) or not (as the code does)?

## Skipped

None.

## Tests

RESULTS_PLACEHOLDER
