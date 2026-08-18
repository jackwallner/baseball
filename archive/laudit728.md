# StatScout UX Audit, 2026-07-28

## Scope and method

- Built the current `main` checkout with XcodeGen and installed it on the dedicated headless `agent-baseball` simulator.
- Exercised the live app as a free user across the Stats, Trends, Teams, Compare, player profile, Settings, and upgrade surfaces.
- Used `axe` taps and headless screenshots. The app loaded live 2026 data successfully from Supabase.
- Reviewed the current SwiftUI source alongside the runtime behavior to distinguish intentional gating from surfaces that feel wrong to a user.
- No app code was changed.

## Executive assessment

The underlying data presentation is polished and visually distinctive, but the app currently feels like several navigation systems layered on top of one another. The most persistent problem is the floating bottom tab bar: it is translucent, remains present on pushed detail screens and Settings, and sits directly over readable content. The second major problem is the free-user upgrade experience: opening a player can immediately place an opaque trial pitch over the player profile, which interrupts the user's first task before they have established value. The back affordance on detail screens is also visually oversized and reads like a large circular button rather than standard navigation.

## Findings

### P0, blocks or obscures normal use

#### 1. Floating tab bar obscures content on every long screen

**Observed:** The custom capsule tab bar is pinned above the bottom edge while leaderboard rows and Settings content continue underneath it. In the dashboard screenshot, rows around ranks 14-16 are visibly washed out and partially hidden by the tab bar. The same happens on the Trends leaderboard. In Settings, the Contact Support row and the start of Privacy Policy are obscured by the bar.

**Why it feels wrong:** The bar looks translucent, but it is not merely decorative. It sits over names, team labels, and values, making content appear disabled or unreadable. A user cannot tell whether the covered rows are intentionally unavailable, selected, or simply behind chrome. On a detail screen, the bar competes with the page's own navigation and makes the app feel like it never left the root tab.

**Evidence:**
- `audit-evidence/audit-settings.png`
- `audit-evidence/audit-trends-tab.png`
- `audit-evidence/audit-compare-tab.png`
- Initial dashboard capture: `/tmp/agent-baseball.png` (captured before later navigation; not committed because it is overwritten during the run)

**Source context:** `StatScout/Views/RootTabView.swift:119-131`, `168-188`. The tab bar is deliberately placed in the root `ZStack`, so it remains visible for every child navigation stack.

**Recommendation for product review:** Treat the floating bar as a root-only control, or reserve a guaranteed opaque/content-safe bottom inset on every child screen. Do not leave it over live data.

#### 2. The player-open trial pitch interrupts the first player visit

**Observed:** Tapping a player from a board opened the profile, but a large bottom sheet immediately covered the lower half of the profile with “Full Player Scouting” and an “Unlock StatScout+” CTA. The underlying profile is dimmed and the user has not yet had a chance to read the player's basic stats.

**Why it feels wrong:** A first-time player tap has a clear intent: inspect the player. The app instead changes the task into a purchase decision. The sheet advertises multiple paid features, but it is triggered before the free profile has delivered a meaningful moment. This is especially jarring because the profile header and controls remain visible behind a dimmed overlay, suggesting the user did something wrong or that the page is blocked.

**Evidence:**
- `audit-evidence/audit-compare-tab.png` shows the same trial pitch style over an underlying player/detail surface.
- `audit-evidence/audit-teams.png` shows the same sheet treatment after entering an advanced team/player scouting surface.

**Source context:** `StatScout/Views/PaywallView.swift:20-26`, and the `TrialPitchSheet` entry points in `StatScout/Views/RootTabView.swift:387-389` and `StatScout/Views/TeamsView.swift:108-112`.

**Recommendation for product review:** Let a free user see the basic profile first. Move the pitch to a clearly locked module, after the user has encountered Recent Form, historical seasons, or comparison.

### P1, severe visual or navigation friction

#### 3. Back button is oversized and visually disconnected from the navigation title

**Observed:** Detail screens show a very large pale-blue circular back control at the upper left, while the title is centered separately in the navy header. The control dominates the header and does not match the compact gear, season, or CTA controls used elsewhere.

**Why it feels wrong:** It reads like a floating action button or an active selected control rather than a standard back affordance. It consumes a large amount of header space and makes the detail screens feel like a different product from the root screens. Its light-blue fill is also the strongest color in an otherwise navy/red/yellow design.

**Evidence:**
- `audit-evidence/audit-trends-tab.png`
- `audit-evidence/audit-compare-tab.png`
- `audit-evidence/audit-teams.png`

**Recommendation for product review:** Use a compact, conventional back button aligned with the title bar, or make the custom control visually match the root navigation chrome.

#### 4. Settings is not actually a clean Settings destination

**Observed:** Settings has a native-looking title and back control, but the floating root tab bar remains visible at the bottom and overlays support/privacy rows. The page also uses a large custom content header style, so it looks like an in-app content page mounted inside the root tab rather than a focused settings screen.

**Why it feels wrong:** Settings is a utility destination where users expect stable scrolling and unobstructed rows. Leaving the root navigation visible makes the user wonder whether they are still in Stats. The bottom bar also makes the final links appear clipped or inaccessible.

**Evidence:** `audit-evidence/audit-settings.png`.

**Source context:** `StatScout/Views/RootTabView.swift:350-364` pushes `AboutView` from a child navigation stack, while `RootTabView.swift:119-131` continues drawing the root bar. `StatScout/Views/SettingsView.swift:15-30` uses a scroll view without any dedicated bottom clearance.

#### 5. The app's navigation title is inconsistent after drill-down

**Observed:** The player/detail surfaces use a centered large name in a custom navy hero, while the root tabs use the same navy but title placement and controls change substantially. The metric ranking surface uses `Whiff% · Hitting`, while the player surface uses the player's name twice, once in the toolbar and once in the hero.

**Why it feels wrong:** The repeated player name is visually redundant, and the difference between root and pushed navigation makes it hard to understand where the user is in the hierarchy. The custom header is attractive, but it does not preserve the normal iOS navigation model.

**Evidence:** `audit-evidence/audit-trends-tab.png`, `audit-evidence/audit-compare-tab.png`.

#### 6. The Teams tab's compact five-across grid sacrifices recognition

**Observed:** Source layout defines 30 teams as six rows of five abbreviation disks, with no full team names in the normal grid (`StatScout/Views/TeamsView.swift:256-278`, `284-319`).

**Why it feels wrong:** MLB abbreviations are not equally recognizable to casual fans, and several are ambiguous or visually similar. A user must already know that KC means Kansas City, CWS means Chicago White Sox, and SD means San Diego. The grid optimizes for fitting the league on one screen at the cost of orientation and accessibility.

**Recommendation for product review:** Keep the compact grid as an option, but provide team names in the default tile or use a more readable two- or three-column layout.

### P2, confusing or inconsistent product behavior

#### 7. Upgrade language changes across entry points

**Observed:** The root toolbar uses a yellow “Upgrade” pill, Settings uses a red “Upgrade” button, and trial pitch sheets use “Unlock StatScout+”, “See all plans”, and “Maybe later”. The same free state is therefore represented by several CTAs with different visual weight and implied next steps.

**Why it feels wrong:** Users may interpret “Upgrade” as a generic account setting, “Unlock StatScout+” as a purchase, and “See all plans” as a second step that may be required before purchase. The hierarchy is not obvious.

**Evidence:** `audit-evidence/audit-settings.png`, `audit-evidence/audit-teams.png`, `audit-evidence/audit-compare-tab.png`.

**Source context:** `StatScout/Views/RootTabView.swift:301-328`, `StatScout/Views/SettingsView.swift:79-86`, and the trial sheet/paywall trigger labels in `StatScout/Views/PaywallView.swift:49-95`.

#### 8. Crown icons appear inside feature selectors without an explanation at the point of interaction

**Observed:** The player surface shows “Recent” and “Both” controls with yellow crown icons. The user has to infer that these are paid. The actual explanation is only delivered by the later trial sheet.

**Why it feels wrong:** A crown is recognizable as premium branding, but it does not explain whether the control is unavailable, whether tapping it previews a result, or whether it immediately opens a purchase prompt. The control looks like a normal segmented control until tapped.

**Evidence:** `audit-evidence/audit-trends-tab.png` and `audit-evidence/audit-compare-tab.png`.

#### 9. Detail screens retain root-tab affordances that do not apply to the current context

**Observed:** The bottom bar continues to offer Stats, Trends, Teams, and Compare while the user is inside a metric leaderboard or player profile. This is in addition to the large back control.

**Why it feels wrong:** The screen has two competing navigation models: “go back through the stack” and “jump to a root tab.” Both are valid, but the persistent bar reduces the sense of hierarchy and is particularly confusing when it overlays content.

**Evidence:** `audit-evidence/audit-trends-tab.png`, `audit-evidence/audit-compare-tab.png`.

#### 10. Settings copy is dense and the most useful support links are visually pushed below the fold

**Observed:** The first screen of Settings is dominated by explanatory cards for StatScout and StatScout+, data refresh, and support. Contact Support and Privacy Policy begin at the very bottom and are obscured by the floating bar.

**Why it feels wrong:** A user who opens Settings to restore purchases, contact support, or find privacy information must scroll through several large cards before reaching the utility links. The page has good copy but poor task prioritization.

**Evidence:** `audit-evidence/audit-settings.png`.

### P3, polish and trust concerns

#### 11. The app appears to expose a debug-like empty paywall state in simulator conditions

**Observed:** The simulator can show “Couldn't Load Plans” / “Try Again” because the simulator launch path does not activate StoreKit Testing and the app intentionally skips production RevenueCat configuration on simulator.

**Why it matters:** This is not evidence of a production purchase bug, and it should not be “fixed” by configuring the production RevenueCat key on simulator. It is nevertheless a user-visible state that needs a deliberate QA path because it cannot verify the real paywall layout.

**Verification limitation:** Per the project iOS conventions, real paywall layout must be verified under StoreKit Testing through the Xcode scheme/UI test, not plain `simctl launch`. This audit therefore does not sign off on plan cards, pricing, purchase disclosure, or paywall safe-area behavior.

#### 12. The app's strong custom visual language sometimes overwhelms semantics

**Observed:** Large navy hero headers, circular initials, red percentile bars, floating capsule navigation, and large custom back controls all compete for attention. The screens are memorable, but the user has to decode which elements are identity, navigation, status, or action.

**Why it feels wrong:** The design is closer to a branded dashboard than a native iOS information hierarchy. This is most noticeable on detail screens where the player name, back control, star, people/follow icon, tabs, season selector, premium controls, and floating root bar all appear before the data rows.

**Recommendation for product review:** Preserve the baseball/savant visual identity, but reduce the number of simultaneous high-contrast controls on detail screens.

## Persona notes

### Casual fan

- Can understand the leaderboard rows quickly.
- May not understand all team abbreviations in the compact Teams grid.
- Is likely to be surprised by a purchase sheet appearing on first player inspection.
- May interpret crown controls as broken or disabled because the action semantics are not visible before tapping.

### Fantasy/baseball analyst

- Gets useful percentile rankings and dense boards.
- Is likely to notice that the bottom bar obscures rank rows and values during scrolling.
- Needs a predictable path between a metric board, player profile, team, and comparison. The persistent root bar plus oversized back button makes that path feel less coherent.

### Returning StatScout+ subscriber

- The upgrade UI should disappear, but the persistent floating bar and custom detail navigation remain usability concerns.
- Historical/compare verification was not fully signed off in this run because the audit was performed as a free simulator user and the real StoreKit paywall path is intentionally separate.

### Accessibility / large text user

- The dense five-across team layout is a poor fit for larger text and name recognition.
- The floating bar's translucent overlay reduces contrast against content beneath it.
- The oversized back button is easy to target but consumes space and is not semantically conventional.
- A full Dynamic Type and VoiceOver sweep should be a separate pass with accessibility settings enabled, not inferred from this visual run.

## What worked well

- Live data loaded successfully and the dashboard presents a clear rank, player, team, metric, and value relationship.
- The red/blue percentile treatment is consistent and readable in the main leaderboard.
- Player identity surfaces are visually strong and make it easy to recognize the current player.
- Settings contains the expected restore, support, privacy, version, and disclaimer information.
- Upgrade sheets consistently explain the paid feature bundle and include Terms, Privacy, and a dismiss action.

## Evidence inventory

- `audit-evidence/audit-settings.png`, Settings screen with bottom navigation overlap.
- `audit-evidence/audit-trends-tab.png`, player/detail screen with oversized back control, premium controls, and bottom navigation overlap.
- `audit-evidence/audit-teams.png`, trial pitch sheet over an underlying detail surface.
- `audit-evidence/audit-compare-tab.png`, trial pitch sheet and persistent bottom navigation over detail content.

## Exhaustive route and feature coverage matrix

Legend: **Observed** means driven in the live simulator and visually inspected. **Source-reviewed** means the route and states were inspected in the implementation, but the exact state was not reached reliably in this run. **Unverified** means it needs a StoreKit/TestFlight/device or dedicated fault-injection pass.

| Area | Coverage | What was checked | Result / limitation |
|---|---|---|---|
| Cold launch | Observed | Existing-user launch, data loading, live 2026 leaderboard | Loads live data. Dashboard is usable, but bottom glass covers lower rows. |
| Fresh install onboarding | Observed + source-reviewed | First page, Skip, Continue layout, final-page upsell behavior | First page is polished. Source confirms 3 pages, final StatScout+ CTA, Get Started, restore, legal links. Page 2/3 content was source-reviewed, not fully screenshot-driven because simulator coordinate mapping was inconsistent. |
| Onboarding Skip | Observed | Tap Skip from fresh state | Correct logical coordinate exits onboarding. No confirmation is shown, which is appropriate. |
| Onboarding Continue | Source-reviewed | Three-page progression and final CTA | The implementation has fixed-height slots to prevent layout jumping. Needs a dedicated UI-test capture of all three pages to verify the actual runtime transition. |
| Stats / Advanced | Observed | Hitting leaderboard, rank/player/team/value columns, scroll-under behavior | Clear and dense. Bottom bar obscures row content. |
| Stats categories | Source-reviewed | Hitting, Pitching, Fielding, Running | Four categories exist and share the board. Full tap-through of each category was not completed in this run. |
| Stats sort | Source-reviewed | Sort chip and header direction toggle | Direction is explicit in source. Needs runtime capture for each category and lower-is-better metric. |
| Stats season picker | Source-reviewed | Current season, locked seasons, crown/checkmark menu states | Native Menu implementation is consistent. Locked-year pitch behavior not fully driven. |
| Stats View menu | Source-reviewed + partially observed | Advanced, Standard, Best & Worst board switching | Menu route is implemented. Opening the first locked surface repeatedly surfaced the pitch before menu content could be captured. |
| Standard Stats | Source-reviewed | AVG and category-specific standard stat catalogs, sort direction, fielding/running | Implementation supports all four categories. Full live traversal was not completed. |
| Best & Worst | Source-reviewed | Pro board and free blur gate | Free board intentionally blurs the metric leaders and presents an unlock gate. Real data/pro state unverified. |
| Metric ranking | Source-reviewed | Metric-specific route, percentile-only values, season indicator, sort | Handles blank raw values by ranking percentile. Full live route not completed after simulator state became stuck in a pitch. |
| Player search | Source-reviewed | Search field, filtering, empty result state | Existing UI tests cover normal and empty search. Runtime capture not repeated in this pass. |
| Player profile | Observed | Player identity, Advanced/Standard/Year Compare tabs, premium controls | Strong identity surface. Duplicate name/header treatment, oversized back control, persistent root bar, and premium interruption are user-facing concerns. |
| Player favorite/follow | Source-reviewed | Star toggle, accessibility labels, persisted favorites | Free and implemented. Runtime persistence across relaunch was not fully captured. |
| Player share | Source-reviewed | Share route in existing UI tests/source | Existing UI test covers share sheet. Not re-driven in this pass. |
| Player Recent / Both | Observed | Crown-marked controls behind free user | Crown communicates premium weakly; trial pitch covers the underlying profile. Pro rendering unverified. |
| Player percentile info | Source-reviewed | Info sheet route and explanatory content | Route exists. Runtime capture not completed. |
| Player game logs / Recent Form | Source-reviewed | Loading, error, windows, small sample messaging | Source includes loading/error and window handling. Network-fault rendering not injected. |
| Year Compare | Source-reviewed | From/To menus, swap, overall delta, category comparison, no-data states | Source handles reversed direction and no-overlap messaging. Full live history route not completed. |
| Compare tab | Observed + source-reviewed | Your Players card, player-vs-player card, Year-over-Year card, free blur gate | Compare surface is implemented and free following is visible. Premium gate/pitch behavior observed. Full picker flow not completed. |
| Compare player picker | Source-reviewed | Search, side/season roster, no-player/loading states | Native sheet/list and explicit empty states exist. Runtime picker capture not completed. |
| Player-vs-player | Source-reviewed | Two slots, cross-season resolution, duplicate-player exclusion, compare button | Logic is present. Pro-only result unverified in simulator. |
| Teams list | Source-reviewed | Search, favorite card, divisions, 30-team grid, empty states | Five-across abbreviation grid is compact but weak for casual recognition. Full live Teams list capture was interrupted by detail pitch. |
| Team favorite | Source-reviewed | Set, remove, pinned favorite, context menu | Logic and labels exist. Persistence and remove animation not fully captured. |
| Team detail Advanced | Observed + source-reviewed | Team identity, advanced season controls, Recent/Both crown controls | Team/player scouting pitch observed. Underlying recent/both Pro states unverified. |
| Team detail Standard | Source-reviewed | Rate/volume groups, team-vs-league percentile mapping, recent gate | Route and copy exist. Live traversal not completed. |
| Team roster | Source-reviewed | Hitters/Pitchers, Season/Recent, window, category, search, filters, qualifier states | Broad implementation coverage. Full combinatorial matrix was not runtime-driven. |
| Team switcher | Source-reviewed | Native menu to jump among all 30 teams | Implemented with alphabetical full names. Runtime capture not completed. |
| Trends board | Observed | Hot/cold leaderboard, player rows, persistent bar, detail pitch | Board is readable, but bottom bar overlays rows. Metric/side/window combinations were not all driven. |
| Trends metric menu | Source-reviewed | Statcast/Standard sections, side-dependent options | Native menu route exists. Runtime menu capture not completed. |
| Trends heating/cooling | Source-reviewed | Direction control, lower-is-better inversion | Logic is explicit. Needs visual verification for pitching and lower-is-better metrics. |
| Trends windows | Source-reviewed | 7/15/30 calendar-day semantics and G annotation | Copy clarifies days vs games. Error/no-movement states exist but were not fault-injected. |
| Follow Players sheet | Source-reviewed | Search, batting/pitching switch, follow/unfollow, empty state, Done | Broad source coverage. Runtime sheet capture not completed. |
| Settings | Observed | StatScout info, StatScout+, restore, refresh timestamp, support/privacy/version/disclaimer | Content is present, but bottom bar covers lower links and utility content is dense. |
| Support/legal links | Source-reviewed | App Store review, support, privacy, terms | Links exist. External browser handoff was not fully captured. |
| Restore purchases | Source-reviewed + empty-paywall observed | Restore on Settings/onboarding/paywall | Copy handles no-purchase and pending outcomes. Real StoreKit restore unverified. |
| Paywall | Observed empty state | Loading/empty state from plain simulator launch | “Couldn't Load Plans” is expected in this launch mode, not a production purchase verdict. Real plans unverified. |
| Offline/network failure | Source-reviewed only | API errors, recent form errors, retry labels | Error paths exist. No network blocking/fault injection was performed. |
| Loading states | Source-reviewed | Dashboard, teams, recent form, historical data | Skeleton/progress states exist. Timing and transition polish not exhaustively captured. |
| Dynamic Type | Source-reviewed only | Text sizing and fixed layouts | No large-content-size simulator pass was completed. |
| VoiceOver/accessibility | Source-reviewed only | Labels/hints/hidden inactive tabs | Accessibility labels are present in many controls. No full rotor/focus-order audit was completed. |
| Rotation/landscape | Unverified | Layout behavior | Not tested. |
| Dark mode | Unverified | Color and contrast behavior | Not tested. |
| Pro subscriber persona | Unverified | Unlocked recent/history/compare/team states | Requires StoreKit Testing or TestFlight entitlement. |

## Additional findings from the exhaustive pass

### 13. Fresh-install onboarding is visually strong but needs a real three-page capture

A fresh reset showed a well-composed first page with clear value proposition, three bullets, page dots, Skip, and Continue. The source confirms the second page (“Find Insights Fast”) and third page (“Go Deeper with StatScout+”) are materially different, not duplicate placeholders. However, plain coordinate-driven automation did not reliably advance the `TabView` on this simulator, so the second and third pages are not visually signed off. This is a QA coverage gap, not a confirmed product defect.

**Evidence:** `audit-evidence/exhaustive/onboarding-1.png`, `audit-evidence/exhaustive/onboarding-skip-logical.png`, `audit-evidence/exhaustive/onboarding-skip-correct.png`.

### 14. The simulator can become stuck in the empty paywall state after a failed close attempt

During the audit, the empty StoreKit/RevenueCat state displayed a close glyph, but accessibility inspection exposed only the application root and coordinate taps did not consistently dismiss it. A clean rebuild and fresh launch restored normal operation. This may be an automation/runtime artifact, but it is worth testing manually because a user should always have a reliable escape from a failed plan load.

**Evidence:** `audit-evidence/exhaustive/closed-paywall.png`, `audit-evidence/exhaustive/after-paywall-close.png`, `audit-evidence/exhaustive/dashboard-after-clean-build.png`.

### 15. UI-test builds are not safe to install as ordinary app builds

Running the full Xcode test scheme timed out after 10 minutes. The test-installed app then failed to launch through plain `simctl` because its embedded XCTest/Testing framework expected `lib_TestingInterop.dylib`. A normal Debug app build installed afterward and launched correctly. This is not a shipped-app defect, but it is an important audit/release workflow trap: do not use the test runner's app bundle for manual simulator UX review.

**Evidence:** `/tmp/StatScoutAuditTests.log`, `/tmp/audit-rebuild.log`, `audit-evidence/exhaustive/dashboard-after-clean-build.png`.

## Verification boundary

This is a UX audit only. No fixes were attempted. The screenshots document the states that were actually observed. Real subscription plan-card layout and purchase behavior remain unverified in plain headless `simctl` launch because the project intentionally avoids production RevenueCat configuration on simulators and StoreKit Testing requires the Xcode scheme path. The matrix above is intentionally explicit about what was source-reviewed versus visually driven, so the remaining coverage is not presented as completed when it was not.
