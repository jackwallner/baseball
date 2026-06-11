# Baseball — Project Guide

## Scripts

- `scripts/testflight.sh` — push to TestFlight / ship a build
- `scripts/pull-appstore-metadata.sh` — snapshots `fastlane/metadata/` to `metadata.bak.<timestamp>/`, then runs `fastlane deliver download_metadata`. ALWAYS run before editing `fastlane/metadata/*.txt` so ASC web-UI edits aren't clobbered. After pulling, diff against the snapshot to confirm what changed remotely.
- `scripts/upload-appstore-metadata.sh` — `fastlane upload_metadata` (screenshots + listing copy, no binary, no submit-for-review).

ASC API key (shared across apps): `~/.baseball_credentials` (`ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).

This project is the fastlane template for other iOS projects — keep `Appfile`, `metadata/en-US/`, `screenshots/en-US/`, and `Fastfile` review info canonical here.

**App Store reviews:** StatScout uses the enjoyment funnel in `StatScout/Services/ReviewPromptTracker.swift` (passive triggers: 3rd+ player profile open, Pro player comparison). App Store ID `6743780853`; feedback `jackwallner+bb@gmail.com`.

## Simulator — dedicated, headless (required)

This project owns the simulator device `agent-baseball`. Multiple agents work in
parallel on this machine: NEVER build/test against a shared named destination
(e.g. `name=iPhone 17 Pro`) and NEVER open Simulator.app — it steals Jack's
mouse/keyboard. Everything runs headless. Full guide: `~/docs/ios-agent-simulators.md`

```bash
UDID=$(agent-sim boot baseball)        # create if needed + boot headless; prints UDID
xcodebuild -project StatScout.xcodeproj -scheme StatScout -destination "id=$UDID" build
xcodebuild test -project StatScout.xcodeproj -scheme StatScout -destination "id=$UDID"
APP=$(find ~/Library/Developer/Xcode/DerivedData/StatScout-*/Build/Products -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
xcrun simctl install "$UDID" "$APP" && xcrun simctl launch "$UDID" "$(defaults read "$APP/Info" CFBundleIdentifier)"
axe describe-ui --udid "$UDID"        # inspect UI via accessibility tree
axe tap --label "Continue" --udid "$UDID"   # interact without mouse/keyboard
agent-sim screenshot baseball          # PNG at /tmp/agent-baseball.png
agent-sim shutdown baseball            # free resources when done
```

## TestFlight on every update

After finishing a change and pushing to git, ALWAYS upload a new TestFlight build by
running `./scripts/testflight.sh` — do this unprompted on every push that changes app
code. Jack tests every update on his device and shouldn't have to ask.
