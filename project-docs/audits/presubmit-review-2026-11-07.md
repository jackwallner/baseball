# Pre-submit review: StatScout 1.5.6 (2026-11-07, deep pass 2026-11-08)

Scope: app changes from the live 1.5.5 (last 1.5.5 commit `8c88a5e`, bumped to 1.5.6 in `0b46acd`) to
`origin/main` `5e5644d`, plus a deep pass over every user-reachable path on `origin/main`: purchase,
restore, paywalls and pitches, onboarding, the update showcase, persistence (favorites, player cache,
review tracker), iPhone Duo layouts and localization. StatScout has no notifications, widgets, App
Intents or SwiftData/CoreData, so those checks do not apply. No simulator or local xcodebuild was used.

Diff since 1.5.5: pending-purchase counter for `PendingUnlockAction`, authoritative current-season
merge, kept postseason date on a failed fetch, single count per profile open, Settings Language row
plus `UIPrefersShowingLanguageSettings`, accessibility hiding of blurred gates, Compare gate moved to
the top, DEBUG-only `playercompare` Duo tour route. All read correct.

| Severity | Location | What happens | Status |
|---|---|---|---|
| P1 | `StatScout/Views/SavantDesign.swift:274` | `ReadableColumn` (wraps every tab root and pushed screen) branched on horizontal size class with `if/else`. On an iPhone Duo each fold or unfold gave the content a new identity and reset its `@State`: Compare's chosen players and seasons cleared, an open player or team comparison popped back to the root, a player profile counted a second open (and could raise the trial pitch again), and Teams re-pushed the favorite team after the user had backed out. | Fixed: one view tree, size-class-driven frame widths and background opacity. Regression test `StatScoutTests/ReadableColumnTests.swift` hosts the modifier and flips size class. |
| P2 | `StatScout/ViewModels/DashboardViewModel.swift:560` | When a recent-form fetch is cancelled and replaced for the same window, the cancelled task's `defer` removes the new task's loading flag and task entry. The spinner can drop early and a second caller can start a duplicate fetch. Data is still correct once the new fetch lands. | Not fixed: cosmetic, no wrong data. |
| P2 | `StatScout/ViewModels/DashboardViewModel.swift:985` | `rawNumeric` (and `PostseasonQualifier.number`) accept "inf"/"nan" from the feed. No path converts such a value to `Int` today, so nothing crashes. | Not fixed: hardening only. |

Checked and clean: RevenueCat offering lookup with retry, yearly/monthly/lifetime package mapping,
trial eligibility copy (unknown eligibility defaults to eligible, as intended), purchase pending,
cancelled and already-owned paths, restore on the paywall, onboarding and Settings, `isPro` from any
active entitlement plus product fallback, every paywall and pitch dismissible with Terms and Privacy
links, prices only from StoreKit, no other-platform links, no health claims, DEBUG hooks
(`FORCE_PRO`, screenshot modes, Duo tour, RevenueCat probe) compiled out of Release, onboarding and
update showcase flags persisted in `@AppStorage`, review prompt gating, and localization
(`Tools/Localization/check.py`: 604 keys, 9 languages, 0 problems).
