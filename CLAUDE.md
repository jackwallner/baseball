# Baseball — Project Guide

## Scripts

- `scripts/testflight.sh` — push to TestFlight / ship a build
- `scripts/pull-appstore-metadata.sh` — snapshots `fastlane/metadata/` to `metadata.bak.<timestamp>/`, then runs `fastlane deliver download_metadata`. ALWAYS run before editing `fastlane/metadata/*.txt` so ASC web-UI edits aren't clobbered. After pulling, diff against the snapshot to confirm what changed remotely.
- `scripts/upload-appstore-metadata.sh` — `fastlane upload_metadata` (screenshots + listing copy, no binary, no submit-for-review).

ASC API key (shared across apps): `~/.baseball_credentials` (`ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).

This project is the fastlane template for other iOS projects — keep `Appfile`, `metadata/en-US/`, `screenshots/en-US/`, and `Fastfile` review info canonical here.

**App Store reviews:** StatScout uses the enjoyment funnel in `StatScout/Services/ReviewPromptTracker.swift` (passive triggers: 3rd+ player profile open, Pro player comparison). Playbook: `~/Desktop/app-store-5-star-review-strategy.md`. App Store ID `6743780853`; feedback `support@statscout.app`.
