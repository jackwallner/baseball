# StatScout for Android

Native Kotlin and Jetpack Compose port of StatScout. Football's Android app
supplied the shared Gradle, RevenueCat, navigation, and paywall foundation.
Baseball's iOS models, live feeds, and historical export supply the content.

## Build

Use JDK 17 and the checked-in wrapper. Copy `local.properties.example` to
ignored `local.properties`, then configure the Android SDK, public Supabase
connection, and RevenueCat Test Store key. Release additionally requires the
Play public SDK key, reviewer-code digest, and external upload-key settings.
Keep all credentials and signing material outside Git.

```sh
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
  ./gradlew testDebugUnitTest lintRelease assembleRelease bundleRelease
```

Run Android emulators, ADB, and connected tests only on the MacBook Pro. See
the exact host, AVD, and cleanup instructions in
[`../.claude/rules/android.md`](../.claude/rules/android.md).

```sh
ANDROID_SERIAL=emulator-5560 ./gradlew connectedDebugAndroidTest --no-daemon --max-workers=1
```

`qa` uses the optimized app renderer, debug signing, local test controls, and
no RevenueCat connection. `release` has no test launch controls and uses the
Google Play public SDK key. QA instrumentation uses
`-PinstrumentedBuildType=qa connectedQaAndroidTest`.

## Data and assets

```sh
python3 ../scripts/sync-android-historical.py
python3 ../scripts/make_android_icon.py
python3 ../scripts/play_screenshot_compositor.py
```

History is gzip JSON in `players-historical.bin`. Decode it as a stream of
individual rows, never one in-memory JSON tree. Keep regular-season and
postseason game-log tables separate. Unit tests verify iOS row counts,
qualifiers, two-way players, rolling windows, and traditional-stat aggregation.

Store assets and copy are in `play-assets/`. Screenshots must come from the
real app on the remote emulator. Release evidence and Console state belong in
[`../project-docs/android/`](../project-docs/android/).
