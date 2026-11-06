# State machine audit, 2026-11-06

Scope: the StatScout iOS app (one app target; there are no widgets, Watch app, App Intents or notification targets, so no scheduled or pending notifications exist to reconcile), plus the one backend function the monetization stack touches (`supabase/functions/apple-retention-message`, read only) and the nightly pipeline's prune step where it feeds an app state machine. Android is out of scope. Audited from committed code at `f2f509c` (`git stash -u` had nothing to stash). No app code was changed.

**Summary: 3 bugs proved by failing test, 1 code path only (not proved).** Plus 6 product calls (not counted).

Evidence run: `gh-sim test --scheme StatScout --only StatScoutTests/StateMachineAuditRepro`, run `baseball@20261106-142529-be34-claude-imacda0a-1106-150919-8027` (Xcode 27.1, iPhone 17, iOS 27.2). Result: 6 tests, 3 passed (the controls), 3 failed (the claims). The build needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` build settings; the run passed dummy placeholders (`https://audit.invalid`, `audit-dummy`) as `--xcarg`, no real credentials. The repro suite is `state-machines-2026-11-06-repro.swift` beside this file (copy it into `StatScoutTests/` to run it). The test result summary lists the first failing assertion per test; the failure strings below are those recorded values. Assertions after the first in a failing test have no recorded result and are not claimed.

Existing test seams used: an injected `StatcastProviding` (the suite defines `ReproProvider`, modelled on `MockProvider` in `DashboardViewModelTests.swift:342`), `DashboardViewModel(provider:cache:)` with a nil cache, `UserDefaults.standard` plus `ReviewPromptTracker` static accessors (saved and restored per test), `PaywallGate.shared`, and a `UIHostingController` in a `UIWindow` on the app host. Seams that do not exist: a constructible `CustomerInfo` fixture (no test builds one; RevenueCat is not injected into `StoreService`), a clock for `StoreService`, and a notification service (there is none). That is why entitlement and purchase claims stay code path or product calls.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Impact | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | Returning to a profile from a drill-down counts as another "profile open" | A free user on their first profile taps one metric row and goes back: the Full Player Scouting sheet pops up over the profile they were reading. After two such round trips on one profile the system rating ask becomes due. | `PlayerProfileView.swift:343-346`: "Defer the first-impression pitch: a user verifying one stat from a group chat shouldn't hit a subscription story before scrolling a single row. Show it from the *second* profile open onward". `AGENTS.md`: the review ask follows the "3rd+ player profile open". | Stats tab, tap any player row (`PlayerProfileView`, free user, Advanced tab, Season mode). Tap the "xwOBA" (or any) percentile row, a `NavigationLink(value: MetricRoute)` (`PlayerProfileView.swift:973`), to open the metric leaders board. Tap Back. The sheet appears on this return if `PaywallGate` still allows `.playerScouting` (cap 2 per session). Repeat once more and `opens` reaches 3. | Every free user, any device or locale, from their first profile. The metric rows are the main thing on a profile, so the common path hits it. Cost to the user: one unwanted dismissible sheet per session (cap 2) and an early rating ask. Cost to Jack: the pitch the code deliberately delays is shown on first view. Highest reach of the three, lowest cost each. | Test: `testReturningToOneProfileFromADrillDownIsNotANewProfileOpen` failed with `("3") is not equal to ("1") - one profile opened once, but the counter says more`. Preconditions asserted first (free user; counter 1 after the first open; nav path depth 1 after two round trips). Control `testControlOpeningTheProfileTwiceCountsTwice` passed (count 1 then 2), so the harness sees genuine opens. | `PlayerProfileView.swift:342-357` (`onAppear` increments `profileOpenCount`); push site `:973` |
| B2 | A refresh keeps current-season rows the server has pruned | A player who fell below the qualifier overnight stays on the Stats board, Teams and Compare pickers with last night's percentiles, for the whole session. | Backend `backend/ingest.py:1795-1799`: "Prune rows that are no longer in the qualified set... Without this, an upsert-only refresh leaves their old (now stale) row behind forever." App copy `StatScoutApp.swift:607,609`: "Every qualified player ranked", "Updated daily, always fresh". | Open the app on day N (disk cache written, valid 48 h, `PlayerCache.swift:40-47`). The pipeline prunes a player overnight. Open the app on day N+1 (cache shows him first), or leave it resident and foreground it (`StatScoutApp.swift:149-151` calls `load()`). Stats tab leaderboard still lists him. Pull to refresh (`DashboardView.swift:41`) does not remove him either. | Any user who launches within 48 h of their last session, or keeps the app resident across the nightly refresh, in season. Players cross the qualifier boundary routinely, so a few rows per day. Cost: one stale or wrongly ranked row per prune, not data loss. Cleared by killing the app after the cache has been rewritten. | Test: `testRefreshDropsAPlayerTheServerPruned` failed with `("[1, 2]") is not equal to ("[1]") - player 2 was pruned from the feed but is still on the board`. Preconditions: first load shows [1, 2], second `fetchCurrentPlayers` call made, `errorMessage` nil, `lastFetchFailed` false. Control `testControlRefreshReplacesARowThatIsStillInTheFeed` passed (team NYY to BOS), so merge-by-id does update live rows. | `DashboardViewModel.swift:1219` (`mergePlayers(replacing: current)` merges over `playerHistories`), `:1372` |
| B3 | A failed refresh resets the Postseason board to Regular Season | A user reading the Postseason board backgrounds the app, comes back with no signal (or a timeout on the one-row request): the board silently changes to the regular season and the Postseason choice disappears from the season menu until a later load succeeds. | `DashboardViewModel.swift:74-75`: `postseasonThrough` is "The newest postseason game the backend holds, or nil when the playoffs haven't started". A failed request is neither. The sibling coverage fetch keeps its last value on failure (`:1258`, `if let coverage = try?`). | Stats tab, season pill, choose Postseason (offered on the live season once a playoff game exists, `offersPhaseChoice` `:145`). Background the app, enable airplane mode, reopen. `ContentView` reloads on foreground (`StatScoutApp.swift:149-151`). | Users who chose Postseason and resume on a flaky or absent connection. Postseason data exists from October through the end of the 2026 season constants, so the exposure is real but only for the subset that picked Postseason and lost connectivity. Cost: lost board selection, recoverable in two taps once online. Lowest cost of the three. Caveat: the comment at `:1268` ("a failure just leaves the postseason out rather than failing the load") documents the first-load case; whether it was meant to also clear a known value on refresh is arguable. | Test: `testOfflineResumeKeepsTheSelectedPostseasonBoard` failed with `("regular") is not equal to ("postseason") - an offline resume must not change the board the user picked`. Preconditions: Postseason offered and selected, refresh did fail (`lastFetchFailed`). Control `testControlOnlineResumeKeepsTheSelectedPostseasonBoard` passed. The second assertion (`offersPhaseChoice` stays true) has no recorded result. | `DashboardViewModel.swift:1270-1273` (`postseasonThrough = try? await ...` then `if !offersPhaseChoice { selectedPhase = .regular }`) |
| C1 | (Code path, not proved) A pending Ask-to-Buy flag outlives the decision, so an unrelated dismissed sheet keeps a stale unlock action that a later purchase fires | After one Ask-to-Buy purchase that is never approved, a different locked tap (for example season 2023) followed by "Maybe later" leaves that action armed; when the user later buys from Settings, the Stats board jumps to 2023 on its own. | `TrialPitchSheet.swift:3`: "Keeps an explicit locked action until entitlement activation or dismissal." | Stats tab, locked season, Try Free, Apple sheet, choose Ask to Buy (child account), dismiss. Locked season 2023, "Maybe later". Later Settings, Upgrade, buy. | Child or family accounts only, same session, rare. Low cost (board jumps to a year they asked for earlier). | Not run. `purchasePending` is set at `StoreService.swift:684` and only cleared on a later purchase attempt (`:641`) or an active entitlement (`:801`); a declined Ask to Buy sends the app no event. `PendingUnlockAction.dismiss` (`TrialPitchSheet.swift:20-24`) keeps the action when `purchasePending` is true. Settling it needs a `StoreService` with an injected purchases client or a `CustomerInfo` fixture; neither exists. | `TrialPitchSheet.swift:20-24`, `StoreService.swift:356,641,684,801` |

## Product calls (not counted: documented, or no cited promise)

1. Unknown intro-offer eligibility resolves to eligible (`StoreService.swift:510-516`, documented). A failed `checkTrialOrIntroDiscountEligibility` lookup is stored as ineligible for every product (`:792`), but a missing key reads as eligible, so the copy depends on which failure happens.
2. Intro eligibility is read once per offering load (`:783-793`) and not refreshed after a purchase, so trial wording can be stale until relaunch if a subscription lapses in the same process.
3. `ReviewPromptTracker.markShown()` runs before `requestReview()` (`RootTabView.swift:159-160`) and starts the 30-day cooldown even when iOS shows nothing. Documented as pacing ("Apple decides", `:141`).
4. The first-conversion record (`ConversionDiagnostics.recordConversion`, `StoreService.swift:653`) is written only on a direct in-app purchase result. A restore, or an Ask-to-Buy approved later through `apply(customerInfo:)`, never writes `converted_*` attributes. Affects Jack's attribution only; also `startedTrial` is taken from pre-purchase eligibility, which defaults to true on unknown.
5. `StatScoutSeason.current` is a compile-time constant (`StoreService.swift:38`), documented as a one-line change at rollover. Until shipped, the free season, the postseason card id and the API filters stay on 2026 after New Year (`ClockBoundaryTests` covers the board landing).
6. `isPro` starts false and is not persisted (`StoreService.swift:354`). A paying user cold-launching offline depends on RevenueCat delivering cached customer info to the delegate when it is set (`:848`). The SDK behaviour was not verified here; the app has no offline entitlement cache of its own.

## Related fixes, in order

1. B2 and B3 are both in `DashboardViewModel.load()`: treat the current-season feed as authoritative for its own season (drop `season == current` rows absent from a successful non-empty feed, keep past seasons), and keep the previous `postseasonThrough` when its request throws. One change, one test file.
2. B1: count profile opens by navigation identity (for example once per pushed `PlayerRoute`, held in the profile's `@State`), not in `onAppear`. The same counter feeds the review moment (`opens >= 3`), so it also fixes the early rating ask.
3. C1: clear `purchasePending` when the offer sheet that raised it is dismissed without a purchase in flight, or key it to the specific purchase. Needs a seam in `StoreService` first.

## State machines

### SM1. Entitlement and purchase (`StoreService`)

State is spread across `isConfigured`, `customerInfo: CustomerInfo?`, `isPro`, `purchasePending`, `purchaseInFlight`, `isLoadingProducts`, `products`, `currentOffering`, `introEligibility`, `lastError`.

States: Unconfigured (`isConfigured` false, simulator without a test key) / Configured, customer unknown (`customerInfo` nil) / Free (known, `isPro` false) / Lapsed (`isLapsed`: Free with an expired entitlement in `all`) / Pro (`hasProEntitlement`) / PendingApproval (`purchasePending` true while Free).

Invariants:
- I1. `isPro == customerInfo.hasProEntitlement` after every `apply` (`:795-806`).
- I2. `purchasePending` implies not Pro.
- I3. `lastError` is one shared line that a purchase must not inherit (`:635-640`).
- I4. A CTA naming a trial is eligible for it (`:510-516`).
- I5. Only the first conversion is recorded.

| From | Event | To | Invariant touched |
|---|---|---|---|
| Unconfigured | `start()` / any `configureIfNeeded()` on device | Configured, unknown | none |
| Configured, unknown | `customerInfo(.fetchCurrent)` ok | Free or Pro | I1 |
| Configured, unknown | fetch fails offline | stays unknown, `isPro` false, `lastError` set | cached entitlement relied on from the SDK delegate (product call 6) |
| Free | purchase ok with entitlement | Pro, `recordConversion` | I5 |
| Free | purchase result without entitlement, refetch still not Pro | PendingApproval | I2 |
| Free | `paymentPendingError` | PendingApproval | none |
| PendingApproval | RevenueCat delegate delivers entitlement | Pro, `purchasePending` false | I2 |
| PendingApproval | Ask to Buy declined | stays PendingApproval (no event reaches the app) | breaks I2's intent, feeds C1 |
| Free | restore ok, entitlement present | Pro, no `recordConversion` | product call 4 |
| Pro | foreground `updateCustomerProductStatus()` finds expiry | Lapsed | I1 |
| Pro or Lapsed | refresh throws | unchanged, `lastError` shows a refresh error | shared status line, no reconcile until next success |

### SM2. Locked-action resume (`PendingUnlockAction` plus `PaywallGate`)

State: `action: (() -> Void)?`, `offerIsPresented`. Held in `@State` by StatsView, TeamsView, TeamView, PlayerProfileView, StandardStatsLeadersView, each with its own copy. `PaywallGate` is a process-wide counter, max 2 presentations per trigger.

Invariants: P1 the action runs at most once and only after Pro; P2 it is dropped on dismissal unless a purchase is pending; P3 it never runs while the offer is on screen.

| From | Event | To | Invariant |
|---|---|---|---|
| idle | locked tap: `set(action)` | armed, offer shown | P3 |
| armed, offer shown | purchase ok, sheet dismisses, `dismiss(isPro: true)` | idle, action ran | P1 |
| armed, offer shown | Maybe later, `purchasePending` false | idle, action dropped | P2 |
| armed, offer shown | Maybe later, `purchasePending` true (may be stale) | armed, offer hidden | P2 broken by stale flag (C1) |
| armed, offer hidden | `isPro` becomes true | idle, action ran | P1 |
| armed, offer hidden | another `set` | armed with the newer action, older dropped | none |

All five owners wire `onDismiss` to every sheet that follows a `set` (checked: Stats, Teams, TeamView both sheets, PlayerProfile `trialPitchTrigger`, StandardStatsLeaders); no path leaves `offerIsPresented` stuck true.

### SM3. First-run gate (`hasCompletedOnboarding`, update showcase)

States: Onboarding page 0-2 / Showcase / Main. Storage: `@AppStorage hasCompletedOnboarding`, `lastSeenUpdateShowcase`.

Invariants: O1 the tabs are disabled and not hit-testable until onboarding and showcase are done (`StatScoutApp.swift:126-127`); O2 a fresh install never sees the update showcase (`UpdateShowcaseCampaign.decision`); O3 a Pro user skips the upsell.

| From | Event | To | Invariant |
|---|---|---|---|
| Onboarding | Skip (pages 0-1), Get Started, or `isPro` flips true | Main | O1, O3 |
| Onboarding page 2 | monthly purchase ok | Main via `onChange(isPro)` | O3 |
| Onboarding page 2 | pending approval | stays, message shown | none |
| Main (existing user, unseen campaign) | `onAppear` | Showcase | O2 |
| Showcase | finish | Main, campaign marked seen | none. Killed mid-showcase, it shows again next launch (intended) |

No invalid transition found. The showcase decision runs only in `onAppear` of `ContentView`; a day or time zone change does not matter to it.

### SM4. Review ask (`ReviewPromptTracker`, `RootTabView`)

State: `appLaunchCount`, `lastShownDate`, `outcome`, `positiveMomentCount`, `hasPendingPositiveMoment`, `reviewPromptShownThisSession`, plus `profileOpenCount` (B1).

Invariants: R1 never in the first session (`launch >= 2`); R2 30 days between asks, measured in elapsed seconds (immune to time zone and DST); R3 `openedWriteReview` ends the asks; R4 a moment blocked by a sheet stays pending.

| From | Event | To | Invariant |
|---|---|---|---|
| idle | positive moment (3rd profile `onAppear`, Pro comparison `onAppear`) | pending | R1 checked at ask time |
| pending | 3 s later, screen clear | shown (`markShown`, `requestReview`) | R2, R4 |
| pending | 3 s later, sheet up | pending | R4 |
| any | Settings "Rate StatScout" | `outcome = openedWriteReview` | R3 |
| any | Settings "Send Feedback" | `submittedFeedback`, asks continue | R3 kept (tested) |
| idle | pop back to a profile (B1) | pending after 2 drill-downs | "3rd+ profile open" broken by B1 |

Covered by `ReviewPromptTrackerTests`; the tracker itself holds up.

### SM5. Season, phase and data load (`DashboardViewModel`)

State: `selectedSeason`, `selectedPhase`, `postseasonThrough`, `postseasonPlayers` plus `hasLoadedPostseason`, `players`/`playerHistories`, `isLoading`, `lastFetchFailed`, `hasLoadedHistorical`, `isPro`.

Invariants: D1 a free user is never left on a locked season (`clampSelectedSeason`); D2 `selectedPhase == .postseason` only on the live season while a postseason exists (`:1273`); D3 the board shows the server's current-season rows; D4 a failed refresh does not change what the user selected.

| From | Event | To | Invariant |
|---|---|---|---|
| any | `applyProState(false)` | season clamped to free season | D1 |
| any | `selectSeason(past)` | phase reset to Regular | D2 |
| Postseason | refresh where the through-date request throws | Regular, choice hidden | D2 holds, D4 broken (B3) |
| loaded | refresh where a row left the feed | row kept | D3 broken (B2) |
| loaded | refresh where the feed is empty | prior rows kept (fallback, `:1218`) | by design |
| Postseason | `reloadPostseason` fails | old players kept, error message | none |
| any | New Year, `calendarYear` ahead of `current` | first load jumps to newest unlocked season | D1, tested in `ClockBoundaryTests` |

Concurrency: `load()` has no in-flight guard (`:1193`); the launch `.task` and a foreground notification can overlap. Each run writes the same fields from the same provider, so the last writer wins with equivalent data; no corrupt state was found, and none is claimed. Recent-form windows are protected by owned tasks (`recentFormTasks`, `:508-610`) and refreshed when coverage moves.

### SM6. Postseason card (`PostseasonCampaign`)

Shown iff `postseasonThrough != nil`, onboarding done, customer state resolved (`customerInfo != nil`), and campaign id `postseason-2026` not seen. Dismiss or open marks it seen for good. Because `customerStateResolved` needs `customerInfo`, a user whose RevenueCat fetch never succeeds never sees the card (hidden, not wrong). B3's reset of `postseasonThrough` also hides the card until the next successful load.

### SM7. Favorites (`FavoritesStore`)

Single shared `@Observable` singleton writing `UserDefaults` on every change, read by the Compare, Hot/Cold, Teams, profile and follow sheets. Invariant: the in-memory list equals the stored list. Holds. A followed player absent from the current feed is skipped in lists rather than removed, which is consistent with B2's inverse (the id survives, the row may not).

### SM8. Conversion record (`ConversionDiagnostics`)

Counters in `UserDefaults`: pitch views, first-seen, converted-* written once. Invariant: first conversion frozen (tested in `PaywallFunnelTests`). Day counts use `Calendar.current` day components, so a time zone change can shift `days_since_*` by one; analytics only.

### SM9. Backend function `apple-retention-message` (read only)

Stateless HTTP handler. GET returns health. POST verifies the signed Apple payload against bundled Apple roots, checks `appAppleId`, picks a message id by product (yearly, monthly, else default, else any configured), and fails closed with HTTP 500 when none is configured. It does not read or grant entitlements, so it cannot affect `isPro`. No invalid transition found; unknown `environment` values fall to the sandbox verifier, which rejects production-signed payloads rather than accepting them.

## Not found

Notifications: none exist in the app (`grep` for `UNUserNotification`, `UNNotificationRequest`, `requestAuthorization` finds nothing; `.claude/rules/localization.md` confirms no notification target). Undo and edit paths: the app has no edit or undo flows for user data; favorites are a toggle. Derived totals: B2 is the only row that outlives its source. Mounted-together screens: all five tabs share one `DashboardViewModel`; per-screen `@State` that mirrors it (`PendingUnlockAction`, `rosterMode`, `formDisplayMode`) is reconciled against `store.isPro` in each view; the profile's recent-form row rendering reads `effectiveFormDisplayMode` without `isPro` (`PlayerProfileView.swift:971`), but the data load and metrics are gated on `isPro` (`:841,903`), so no claim is made.
