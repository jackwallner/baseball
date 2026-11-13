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
`player` route for the trial sheet. `-SettingsSnapshot`,
`-PaywallSnapshot yearly` (without `-DuoSeed`, which wins over it), and
`-hasCompletedOnboarding NO -OnboardingPage 0|3` (earlier seeded launches persist
`hasCompletedOnboarding`).

The paywall content is capped at 560pt and centered. If `gh-sim get` reports no
result artifact, run `gh run download <runid> -R jackwallner/gh-sim -n result -D ~/.gh-sim/results/<id>`.
Landscape rotation never worked on a headless gh-sim run here (frames stay
portrait), so landscape is covered by the width caps only. Verify it on a device.

## iPad store screenshots (13-inch, 2064x2752)

- Capture with the same UI test as the iPhone set: `CAPTURE_DEVICE="iPad Pro 13-inch (M5)" CAPTURE_KIND=ipad SCREENSHOT_SCENES=1,2,3,4 artifacts/asc-screenshots/l10n-20261105/tools/capture.sh [locales]`. It writes `raw/<locale>/ipad/NN.png`. Plain `gh-sim launch` frames show the 2026 season with three players, so use the test (it selects 2025).
- `capture.sh` only knows the `app.json` targets (de-DE, fr-FR, it, pt-BR, zh-Hans) plus en-US. For ja, es-MX, zh-Hant and ko pass `CAPTURE_APP_JSON` pointing at a copy of `app.json` whose `targets` lists them (`lang`, `apple_languages`, `apple_locale`).
- A failed job leaves the raws deleted. Recover from the result dir with `tools/ipad_sort.py <result_id>`.
- `tools/ipad_compose.py [locales]` composes `out/ipad/<locale>/01..04` with the iPhone headlines. Upload to the draft with `asc screenshots upload --app 6763945657 --version <v> --path <dir of locale folders> --device-type IPAD_PRO_3GEN_129`.
- Profile, Trends and Compare leave empty space under the 720pt column on iPad. Replace them with fuller scenes (5, 6 or 7) if App Review or conversion data asks for it.
