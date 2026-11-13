---
paths:
  - "StatScout/Views/SavantDesign.swift"
  - "StatScout/Views/SavantModules.swift"
  - "StatScout/Views/RootTabView.swift"
  - "StatScout/Views/TrialPitchSheet.swift"
  - "StatScout/Views/PaywallView.swift"
  - "StatScout/StatScoutApp.swift"
  - "StatScout/Info.plist"
  - "project.yml"
---

# StatScout: iPad layout

iPad is supported (`TARGETED_DEVICE_FAMILY "1,2"`, all four orientations in
`UISupportedInterfaceOrientations~ipad`). It cannot be removed once shipped, so
every new screen has to hold up at 13-inch portrait, landscape and Split View.

- `ReadableColumn` (SavantDesign.swift, 720pt) caps every pushed screen when the
  horizontal size class is regular. It is applied by `SavantNavBar` and
  `SavantNavBarPublic`, so a screen gets it by using those. Compact width is untouched.
- A full-bleed navy band (`PlayerIdentityStrip`, `TeamIdentityStrip`) takes
  `BandInset`, which turns it into a card at the column margin on regular width.
  A band inside the column that runs edge to edge looks like a bar that stops short.
- Bottom gate cards over blurred content use `GateOverlayInset` so they sit inside
  the margin and clear the floating tab bar.
- Onboarding is capped by `OnboardingMetrics.maxContentWidth` (460).
- Sheets are form sheets on iPad: `.presentationDetents` is ignored there, so a sheet's
  content must size itself (scroll view plus pinned footer), not rely on a detent.
- iPhone layouts must not change: gate every iPad adjustment on
  `horizontalSizeClass == .regular`.

## Proof

`gh-sim launch --device "iPad Pro 13-inch (M5)" --detach --wait 12 --xcarg SUPABASE_URL=https://example.invalid --xcarg SUPABASE_ANON_KEY=dummy --screen "<args>"`.
The GitHub step times out at 10 minutes and the install alone can take 8, so keep
a run to about 6 to 9 `--screen`s and split bigger sets across runs.

DEBUG capture args (`-DuoSeed -DuoTour -DuoTourStep 600 -DuoTourFirst 600 -DuoRoutes <route>`):
`stats trends teams team compare player playercompare`. Add `-ShowTrialPitch` to the
`player` route for the trial sheet, `-ForceLandscape` for landscape (a headless
simulator launches portrait and has no rotate gesture). `-SettingsSnapshot`,
`-PaywallSnapshot yearly` (without `-DuoSeed`, which wins over it), and
`-hasCompletedOnboarding NO -OnboardingPage 0|3` (earlier seeded launches persist
`hasCompletedOnboarding`).
