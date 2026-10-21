---
paths:
  - "StatScout/Views/RootTabView.swift"
  - "StatScout/Views/DetailPaneLink.swift"
  - "StatScout/Utilities/UnfoldedSplit.swift"
  - "StatScout/Utilities/PaywallScreenshotMode.swift"
---

# StatScout: iPhone Duo (2026-10-21)

- Unfolded (regular width, at least 720 pt), `RootTabView` puts the four tabs
  and the tab bar left of the fold and the player or team they open in a pane
  on the right. Pane edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split (`UnfoldedSplit`, unit
  tested). Portrait unfolded (669 pt) and every compact width keep one column.
- Player and team links are `DetailPaneLink`: a `NavigationLink` on a phone, a
  button that fills the right pane while split (`openInDetailPane`). Use it for
  any new player or team row; leaderboard rows pass `marksSelection: true`.
  Metric and comparison links stay `NavigationLink` and push in their pane.
- Folding only moves frames: the tabs and the detail pane stay mounted. Never
  swap layouts with an `if` on size class (the old `ReadableColumn` did).
- Onboarding and the update showcase use `UnfoldedPrimaryPane` so their column
  sits left of the fold.
- Capture: gh-sim relaunches the app after unfolding. `-DuoSeed -DuoTour` with
  `-DuoRoutes`/`-DuoAt` (unfolded) and `-DuoOuterRoutes`/`-DuoOuterAt`
  (folded) shows each route at an offset in seconds from launch; routes are in
  `openDuoRoute`. Pass `--env STATSCOUT_FORCE_PRO=1` and seed Supabase xcargs.
