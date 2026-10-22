# StatScout: "interrupted, tired, busy user" persona audit

Persona: someone pulled away mid-task (phone call, app switch, system kill) who returns later and expects state and context to survive.
Scope: source review of onboarding, Stats/Profile, Compare, Trends, Teams, foreground refresh and purchase paths. Runtime proof: `StatScoutUITests/InterruptedAuditUITests` (4 flows, seeded `-DuoSeed` data, no SDK keys). Runtime status is in the "Evidence status" section at the end. Every finding below is **source-only** unless it says "runtime observed". No frame rate was measured.

## What already works (do not regress)
- Tabs stay mounted in a ZStack (`RootTabView.swift` `tabs`), so each tab's push stack, scroll position and Compare slots survive tab switching and a quick background trip (same process).
- Followed players and favorite team persist in UserDefaults (`FavoritesStore`).
- Foreground refresh keeps existing players on screen and only swaps data in place (`DashboardViewModel.load`, `players.isEmpty` gating for the spinner).
- Onboarding "Skip", `hasCompletedOnboarding` persisted; Pro purchase completion finishes onboarding via `onChange(of: store.isPro)`.

## Findings

### 1. Postseason view silently snaps to Regular Season after a flaky foreground refresh (High, source-only)
Repro: in October, Stats board on Postseason (`selectedPhase == .postseason`). Switch to another app, return on a weak connection (elevator, subway). `ContentView` fires `viewModel.load()` on every `willEnterForeground` (`StatScoutApp.swift:139`). `load()` ends with `postseasonThrough = try? await provider.fetchPostseasonThroughDate(...)` (`DashboardViewModel.swift:1068`). A failed request returns nil, `offersPhaseChoice` becomes false, and the next line `if !offersPhaseChoice { selectedPhase = .regular }` (`:1071`) resets the user to regular season. The season pill also loses its Postseason option until the next successful refresh.
Impact: the exact thing the user was looking at (playoff leaders) changes to a different board with no message. Right now (Oct 22) this is the core use case.
Fix: keep the last known `postseasonThrough` when the fetch throws (`if let v = try? ... { postseasonThrough = v }`), only demote the phase on a successful nil answer.

### 2. Failed refresh leaves stale data with no visible hint (Medium, source-only)
Repro: return to the app offline. `load()` sets `errorMessage = "Showing saved data. Pull to refresh..."` (`:1044`) but the Stats board only renders `errorMessage` when `viewModel.leaderboard.isEmpty` (`DashboardView.swift:431`). With data present, nothing tells the user the numbers are from before the interruption.
Impact: a returning user trusts yesterday's (or last week's) board as current.
Fix: a small "Showing saved data from <date>. Tap to retry" row under the toolbar when `lastFetchFailed && !players.isEmpty`.

### 3. Nothing survives a system kill: tab, category, season, search, open profile, Compare slots (Medium, source-only; runtime flows attached when available)
Repro: open Pitching, a 2024 season, a player profile (or fill Compare slot A), background the app long enough for iOS to evict it, return. `selection`, `statsPath`/`teamsPath` (`RootTabView.swift:48-53`), `viewModel.selectedCategory/selectedSeason/searchText`, StatsView `board/standardStat`, CompareView `playerA/B/team*/season*` (`CompareView.swift:37-57`) and Trends `side/metric/qualifier` (`HotColdView.swift:28-32`) are plain `@State` or view-model fields. The grep for `SceneStorage` returns zero hits in `StatScout/`. The user lands on Stats, Hitting, current season, empty search.
Impact: the busiest users (this persona) redo 3 to 6 taps every return, and Compare (a Pro feature) loses the pair they built, which reads as a Pro feature that "forgets".
Fix: `@SceneStorage` for `selection`, `selectedCategory`, `selectedSeason`, Trends `side/metric`, and Compare `playerA/B` ids + seasons. Optional: restore the last open profile id. Keep a 30 minute age limit so a next-day launch starts fresh.

### 4. Every foreground triggers a full 3-request reload, unthrottled (Low/Medium, source-only)
Repro: flip between StatScout and Messages 10 times in a minute. Each return runs `load()` (cache read from disk on a detached task, `fetchCurrentPlayers`, coverage date, postseason date, and a re-save of the full player cache `try? cache?.savePlayers(current)`) and, in postseason, `reloadPostseason()` which sets `hasLoadedPostseason = false` so `postseasonLoadPending` flips true and boards can flash their loading state.
Impact: battery/data on a heavy payload, plus loading flicker while the user is mid-read.
Fix: skip foreground reload if the last successful load was under ~5 minutes ago; in `reloadPostseason` keep showing the existing rows while refreshing.

### 5. Onboarding restarts from page 1 after a kill (Low, source-only)
`currentPage` is `@State` (`StatScoutApp.swift:235`). Three pages, so cheap, but a user interrupted on the purchase page (page 3) returns to page 1 and must tap Continue twice again or find Skip. Runtime flow `testOnboardingInterrupted` checks the background (same process) path and the kill path.
Fix: `@SceneStorage("onboardingPage")`.

### 6. Pro state is not cached across launches (Medium for paying users, source-only)
`StoreService.isPro` starts `false` on every cold start (`StoreService.swift:291-293`) and flips only after RevenueCat answers (`apply(customerInfo:)`, `:729`). `ContentView.onAppear` calls `applyProState(store.isPro)` with false, and `clampSelectedSeason()` (`DashboardViewModel.swift:204-213`) moves any locked season back to the free one. Compare is blurred and gated (`CompareView.swift` `blur(radius: store.isPro ? 0 : 5)`) and a profile opened in the first seconds can show the trial pitch to a paying subscriber. On a slow network this window is long.
Impact: returning subscriber briefly sees upsell and locked UI; trust damage for exactly the users who already paid.
Fix: persist the last entitlement result (with expiry date) and seed `isPro` from it; RevenueCat then confirms or corrects.

### 7. Profile sub-state resets whenever a profile is reopened (Low, source-only)
`PlayerProfileView` keeps `selectedTab`, `formDisplayMode`, `recentWindowDays` (15), `standardMode/Window` as `@State` (`PlayerProfileView.swift:59-75`). Pop back and reopen (or return after an interruption that drops the view) and the user's chosen Recent Form 30-day view is back to Season/15. Fix: store form mode and window in the view model (or `@AppStorage`) as a user preference.

### 8. Pending purchase after interruption (Low, source-only, needs sandbox to verify)
`buyMonthly()` clears `isStartingTrial` in `defer` and relies on `onChange(of: store.isPro)` to finish onboarding. If the app is killed during Apple's sheet and the purchase completes, the next launch flips `isPro` false to true after RevenueCat responds, which should dismiss onboarding, but only if `OnboardingCards` is on screen at that moment. Not verified at runtime here (no purchases allowed). Worth a sandbox check.

## Not found
- No lost typed input on a quick background trip: search text is in the view model, Compare slots are `@State` in a mounted tab.
- Foreground observer is registered in `StatScoutApp` (non-seeded path) and again in `ContentView`; the first only refreshes entitlements, so the double registration is harmless.

## Motion
No motion problem seen in source for these flows. Frame rate: not measured here.

## Suggested priority
1 (postseason snap), 6 (Pro cache), 3 (SceneStorage for tab/category/season/Compare), 2 (stale banner), then 4, 5, 7.
