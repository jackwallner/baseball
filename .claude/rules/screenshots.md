---
paths:
  - "fastlane/screenshots/**"
  - "artifacts/asc-screenshots/l10n-20261105/**"
---

# Localized store sets

- Recapture with `artifacts/asc-screenshots/l10n-20261105/tools/capture.sh [locales...]`. No arguments captures every target locale and en-US in one GitHub simulator job. `compose.sh [locales...]` renders headers, makes comparison sheets, runs the OCR and frame gates, and replaces root PNGs only in the selected target locales.
- The phone captures launch with DEBUG `-DuoSeed -StoreScreenshotData` and the test-only Pro override. The fixture uses bundled demo players and rolling-form rows. Season boards use 2025 bundled history. Aaron Judge and Bobby Witt Jr. fixture IDs map to the bundled historical IDs so Year Compare has real history.
- `08_teams_index.png` is left out because the current-season sample has only four active clubs, while the English frame claims all 30. `04_compare.png` is captured through the DEBUG `playercompare` route (Judge vs Ohtani). Add the teams frame back to `frames.json` and `headers.json` before recapturing it.
- `frames.json` stores bezel-located phone rectangles. The current app screens differ from the old English UI, so raw screen matching has low scores; bezel detection preserves the shared phone geometry. Header titles keep the reviewed two-line copy; supporting lines use `filename#description` entries in `copy/headers.json` and the `extra_text` layout. Red second lines keep their separate style during composition.
- The Xcode build guard still asks for Supabase settings. `capture.sh` passes nonfunctional `example.invalid` placeholders to xcodebuild. The fixture path returns before app networking starts; never pass actual keys to `gh-sim`.
- `gate.py --catalog` ignores English words that are also real target-language catalog values (Italian "POS." for RANK is not a leak).
- gh-sim queues can sit for hours: submit one job, keep its run id (`~/.gh-sim/runs`), and reattach with `gh-sim get <id>` instead of re-submitting. Do not start `capture.sh` while an earlier job for the repo is still queued; it blocks on the per-repo cap.
