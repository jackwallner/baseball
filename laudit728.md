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

## Verification boundary

This is a UX audit only. No fixes were attempted. The screenshots document the states that were actually observed. Real subscription plan-card layout and purchase behavior remain unverified in plain headless `simctl` launch because the project intentionally avoids production RevenueCat configuration on simulators and StoreKit Testing requires the Xcode scheme path.
