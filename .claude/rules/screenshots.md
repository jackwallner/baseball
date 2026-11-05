---
paths:
  - "fastlane/screenshots/**"
  - "artifacts/asc-screenshots/l10n-20261105/**"
---

# Localized store sets

- Recapture with `artifacts/asc-screenshots/l10n-20261105/tools/capture.sh [locales...]`. No arguments captures every target locale and en-US in one GitHub simulator job. `compose.sh [locales...]` renders headers, makes comparison sheets, runs the OCR and frame gates, and replaces root PNGs only in the selected target locales.
- The phone captures launch with DEBUG `-DuoSeed -StoreScreenshotData` and the test-only Pro override. The fixture uses bundled demo players and rolling-form rows. Season boards use 2025 bundled history. Aaron Judge and Bobby Witt Jr. fixture IDs map to the bundled historical IDs so Year Compare has real history.
- `08_teams_index.png` is left out because the current-season sample has only four active clubs, while the English frame claims all 30. `04_compare.png` is left out because its capture predates the localized comparison separator; the catalog now translates it. Add either frame back to `frames.json` and `headers.json` before recapturing it.
- `frames.json` stores bezel-located phone rectangles. The current app screens differ from the old English UI, so raw screen matching has low scores; bezel detection preserves the shared phone geometry. Header titles keep the reviewed two-line copy; supporting lines use `filename#description` entries in `copy/headers.json` and the `extra_text` layout. Red second lines keep their separate style during composition.
- The Xcode build guard still asks for Supabase settings. `capture.sh` passes nonfunctional `example.invalid` placeholders to xcodebuild. The fixture path returns before app networking starts; never pass actual keys to `gh-sim`.
