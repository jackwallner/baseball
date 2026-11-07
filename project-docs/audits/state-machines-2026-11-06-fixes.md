# Fixes for the 2026-11-06 state machine audit

Fixes for every claim `state-machines-2026-11-06-review.md` marked CONFIRMED or CONFIRMED-MINOR, in the review's ranked order, plus the one product call it called a bug (PC1).

**Summary: 5 in scope. 4 fixed, 1 held for Jack, 0 skipped.**

## Claims

| ID | Outcome | Commit | Regression test (`StatScoutTests/StateMachineRegressionTests.swift`) | What changed |
|---|---|---|---|---|
| B1 | Fixed | `f0c1666c` | `testReturningToOneProfileFromADrillDownIsNotANewProfileOpen` (reused from the repro, which the review called sound UI-level evidence), control `testOpeningTheProfileTwiceCountsTwice` | `PlayerProfileView` counts an open once per pushed profile: a `@State hasCountedOpen` guard in `onAppear`, which fires again on every pop back from a drill-down. The pitch deferral and the review moment both read that count, so both are fixed. |
| B2 | Fixed | `e19aa2ec` | `testRefreshDropsAPlayerTheServerPruned` (repro), `testColdLaunchFromAnExistingCacheDropsThePrunedRowAndKeepsPastSeasons` (the review's cold-launch check through the real `TwoTierPlayerCache`, now asserting the clean result on the first launch), controls `testRefreshStillReplacesARowThatIsInTheFeed`, `testRefreshKeepsPastSeasonRowsTheCurrentFeedDoesNotCarry` | `DashboardViewModel.load()` treats a successful non-empty current-season feed as authoritative for that season: `mergePlayers(replacing:authoritativeFor:)` drops current-season rows the feed no longer carries and keeps every past season. An empty feed still falls back to the saved rows. |
| B3 | Fixed | `55ca081e` | `testOfflineResumeKeepsTheSelectedPostseasonBoard` (repro), `testThroughDateTimeoutKeepsTheSelectedPostseasonBoard` (the review's quiet online-timeout variant), control `testThroughDateOfNilStillHidesThePostseason` | A thrown through-date request keeps the last known `postseasonThrough` (a `do`/`catch` instead of `try?`, as the coverage fetch already does). A successful nil still hides the Postseason board. |
| C1 | Fixed | `db189c0f` | `testUnapprovedAskToBuyDoesNotArmALaterDismissedOffer` (the review's check, which proved the stale keep), control `testAskToBuyOnTheSecondOfferStillKeepsItsAction`; the existing `PendingUnlockActionTests` moved to the new API | `StoreService.purchasePending` (a flag nothing could clear after a declined Ask to Buy) is replaced by a monotonic `pendingPurchaseCount`. `PendingUnlockAction.set` records the count when its offer opens and `dismiss` keeps the action only if the count moved while that offer was up. All five owners pass the count. |
| PC1 | Held for Jack | none | none | See below. |

Not a claim: the review's note that `PlayerComparisonView.swift:196` records a review moment in `onAppear` (the same pattern as B1). The review judged it not worth a separate claim because only the pending flag changes and the 30-day cooldown paces it; it is left as is.

## Held for Jack

- **PC1, trial wording when intro-offer eligibility is unknown.** The doc comment on `StoreService.isEligibleForIntroOffer` says unknown eligibility shows the trial, but `refreshIntroEligibility` stores RevenueCat's `.unknown` as ineligible, so a failed eligibility lookup hides the trial wording. Fixing it changes which offer the paywall and trial pitch advertise, so it is a trial-offer change. Decision: when RevenueCat cannot tell whether a user is trial-eligible, should the CTA name the free trial (as the comment says) or not (as the code does)? The review left it unverified headless (it needs the SDK's failure output); what would settle the runtime half is a RevenueCat seam in `StoreService` that feeds `refreshIntroEligibility` an `.unknown` status, or a device log of `checkTrialOrIntroDiscountEligibility` returning `.unknown`. Either answer is a one-line change at `StoreService.swift:795` (map `.unknown` to eligible) or at the doc comment.

## Skipped

None.

## Tests

- **Full suite, fixed branch:** `gh-sim test --scheme StatScout` (dummy `SUPABASE_URL`/`SUPABASE_ANON_KEY` xcargs), run `baseball@20261106-195302-2025-claude-mbpro385cb-1106-202519-18409`, GitHub run `42338390662` (Xcode 27.1, iPhone 17, iOS 27.2): **189 passed, 0 failed, 0 skipped**, including all 11 `StateMachineRegressionTests`. No test failed, so none needed a check on `dd9dd1c2`, and none already failed there.
- **Regression tests without the fixes:** the same 11 tests on a throwaway copy with the B1, B2 and B3 app changes reverted to `dd9dd1c2` and C1's `dismiss` reverted to the old rule (keep the action whenever any purchase has ever gone pending, which is what the stale `purchasePending` flag did). Run `bb-revert-mbpro385cb-1106-225547-32711`, GitHub run `42349107138`: 6 failed, 5 passed. Every claim test failed with the audit's strings (B1 counter `3` not `1` and review moments `1` not `0`; B2 `[1, 2]` not `[1]` on both refresh and cold launch; B3 `regular` not `postseason` offline and on the quiet timeout; C1 fired `["B"]` not `[]`), and every control passed.
- The audit's repro suite (`state-machines-2026-11-06-repro.swift`) was never added to the test target; its sound tests live on in `StateMachineRegressionTests`.
