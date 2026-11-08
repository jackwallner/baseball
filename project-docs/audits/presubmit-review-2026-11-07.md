# Pre-submit review: StatScout 1.5.6 (2026-11-07)

Scope: app sources changed since the live version 1.5.5 (`0b46acdd^`, last commit before the 1.5.6 bump) to `origin/main` `5e5644d2` (MARKETING_VERSION 1.5.6, build 202). Files: StoreService, DashboardViewModel, TrialPitchSheet (`PendingUnlockAction`), PlayerProfileView, StatsView, TeamView, TeamsView, StandardStatsLeadersView, CompareView, RecentFormCard, RootTabView, SettingsView, StatScoutApp, Info.plist, Localizable.xcstrings.

Checked: force unwraps and indexing in the diff (none added), the pending-purchase counter that replaced `purchasePending` (every call site passes the count on `set` and `dismiss`; no stale reference left), the authoritative current-season merge (paged fetch reads every page, nil-season and past-season rows are kept, empty fetch falls back to cache), the postseason-through failure path (keeps the last value), the once-per-open profile counter (only the pitch and review counting sit behind the guard), the `playercompare` route (inside `#if DEBUG`), the Language row (opens the app's own iOS Settings page, strings translated in all 10 locales), and the trial sheet's Terms and Privacy links. No hard-coded prices, other-platform links or health claims in the diff. Every catalog key has all 9 non-English localizations.

No P0 or P1 findings.

| Severity | File:line | What happens | Status |
|---|---|---|---|
| P2 | StatScout/ViewModels/DashboardViewModel.swift:1387 | The current-season fetch is now authoritative, so a current row that fails `Lenient` decoding drops off the board instead of showing its cached copy. A wholly failed page still throws, so this only hits individual malformed rows. | Not fixed: intended behavior of the prune, not a defect. |
| P2 | StatScout/Views/TrialPitchSheet.swift:30 | After a purchase goes pending (Ask to Buy), the tapped locked action stays armed for the life of the view and runs when Pro activates later, even if that purchase came from another screen. | Not fixed: designed to complete the original tap; harmless. |

Tests: the gate ran 189 unit tests green on this commit, and `StateMachineRegressionTests` covers the pending counter, the merge prune, the postseason failure path and the profile counter. gh-sim not run (per instructions, GitHub's queue is hours deep). No code changed in this review.
