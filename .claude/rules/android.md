---
paths:
  - "android/**"
  - "scripts/*android*"
  - "scripts/play*"
  - "docs/android-*.html"
---

# StatScout Android

- Kotlin and Compose port in `android/`, package `com.jackwallner.baseball`.
  Play name: Baseball Savvy StatScout. Version 1.5.3, versionCode 3.
- Follow `android-dev`. Football's Android port supplied the Gradle, billing,
  navigation, and paywall foundation; baseball's iOS models and feeds are the
  source of truth. Do not reintroduce football data, teams, or product IDs.
- Four tabs: Stats, Trends, Teams, Compare. Current season is free, older years
  and full Trends, recent form, teams and comparisons require StatScout+.
- Statcast history starts in 2015; current season is `StatScoutSeason.CURRENT`.
  Run `python3 scripts/sync-android-historical.py` after exporting iOS history.
  The gzip asset is `.bin`, since Android silently inflates `.gz` assets.
- Postseason snapshots are `player_postseason_stats`. Postseason game logs are
  `player_postseason_game_logs`, never `player_game_logs`. Qualify with 3.1 PA
  (rounded) or 1 real inning per team game. Display the regular-season curve
  reference with October percentiles.
- RevenueCat project `proje8aeddd9`, Play app `app94f43f7fc0`, Test Store
  `appa4e1500cde`, entitlement `Baseball Savvy StatScout Pro`.
  Android offering `android`. Product IDs mirror iOS:
  `com.jackwallner.baseball.pro.monthly:monthly`,
  `com.jackwallner.baseball.pro.yearly:yearly`,
  `com.jackwallner.baseball.pro` (lifetime).
- `android/local.properties` is ignored and contains SDK/feed public settings,
  Test Store and production Play SDK keys, review code SHA-256, and signing
  settings. Release fails without them. Never copy release keys or signing
  material to Pro. External upload keystore:
  `~/.android/keystores/baseball-upload.p12`. Credential names are prefixed
  `BASEBALL_PLAY_` in `~/.baseball_credentials`.
- Review access: long-press Settings > App Version, then enter the private code
  held in `BASEBALL_PLAY_REVIEW_CODE`. Put the instructions in Play App access.
  Do not commit the code. Debug unlocks are absent from Release and QA.
- Google review card is requested directly after eligible positive moments.
  Settings Rate and Feedback are separate. No iOS sentiment gate on Android.

## Emulator, Pro only

SSH: `jackwallner@192.168.4.25`, strict host key checking. SDK:
`/Users/jackwallner/Library/Android/sdk`. Temporary test workspace:
`/private/tmp/baseball-android-agent/source`. Verified temporary Java 17 runtime:
`/private/tmp/baseball-android-agent/runtime/jdk-17.0.20.1+1/Contents/Home`.

Use temporary AVD `baseball_agent_test`, Google Play API 36 x86_64, port 5560,
serial `emulator-5560`. Preserve the existing `small_phone` AVD and accounts.
No local emulator, no forwarded ADB. Boot headless with:

```sh
ssh jackwallner@192.168.4.25 '/Users/jackwallner/Library/Android/sdk/emulator/emulator -avd baseball_agent_test -port 5560 -no-window -no-audio -no-boot-anim -no-metrics -no-snapshot -gpu host'
```

Confirm `adb -s emulator-5560 shell getprop sys.boot_completed` returns 1.
Run connected Gradle tests on Pro with `ANDROID_SERIAL=emulator-5560`,
`JAVA_HOME` set to that runtime and `--no-daemon`. Check nonzero test counts,
not only Gradle's exit code. Stop only this AVD:

```sh
ssh jackwallner@192.168.4.25 '/Users/jackwallner/Library/Android/sdk/platform-tools/adb -s emulator-5560 emu kill'
```

Confirm it is gone before removing its temporary AVD and workspace. Never
uninstall a Play-installed app to resolve a debug signing conflict. This test
AVD is temporary and holds only our debug app.

## Store preparation

- Raw real-app captures go under `android/play-assets/raw/`.
  `python3 scripts/play_screenshot_compositor.py` builds 1080x1920 listing
  frames and the 1024x500 feature graphic. Icon comes from the iOS asset via
  `python3 scripts/make_android_icon.py`.
- Android-specific policy pages: `docs/android-privacy.html` and
  `docs/android-terms.html`. Listing copy lives in
  `android/play-assets/metadata/android/en-US/`.
- Play state, verified 2026-10-13: versionCode 3 (1.5.3) active on internal
  testing (tester list "IM Iron Splits internal testers"). App content, Data
  safety, target audience (13+), listing, six screenshots and feature graphic
  are saved. Play products are active: monthly and yearly subscriptions
  (base plans `monthly`/`yearly`, offer `free-trial-7d`, new customers who
  never had any subscription) and one-time `com.jackwallner.baseball.pro`
  (purchase option `lifetime`, backwards compatible). Nothing sent for review.
- RevenueCat's Play app has no service account credentials yet, so Play
  purchases cannot validate. Jack must upload the RevenueCat service account
  JSON in the RevenueCat app settings before any billing test.
- Screenshot captures use the QA build on Pro (`--ez onboarded true --ez
  forcePro true --ei tab <n>`) with System UI demo mode. The emulator is slow;
  wait for content before capturing.
