# iOS 27 compatibility audit: Baseball StatScout

- Audit date: 2026-08-05
- Runtime: iOS 27.0 (24A5390f)
- Xcode: 26.6 (17F113)
- Scheme: `StatScout`
- Unit target: `StatScoutTests`
- Overall: Pass with test-harness findings

## Checks

- Debug build: Pass after loading `/Users/jackwallner/.baseball_credentials`.
- Unit tests: Pass.
- Normal rebuild after tests: Pass.
- Install and launch smoke test: Pass.
- Runtime UI snapshot: Pass. Onboarding and dashboard/player controls rendered.

## Findings

1. A build without the local Supabase environment failed with `SUPABASE_URL not set.` The app build and unit tests pass when the existing local credentials file is loaded. CI or release validation needs equivalent injected configuration.
2. The full scheme UI test attempt stalled after the build with `IDELaunchParametersSnapshot: ... no debugger version` on Xcode 26.6/iOS 27. The test runner was stopped after it made no progress. This is a UI-test harness finding, not an app launch failure.
3. Launching the app artifact left by `xcodebuild test` produced a missing `lib_TestingInterop.dylib` error. A normal rebuild produced a launchable app. Use a post-test normal build before smoke testing.

## Recommended follow-up

- Make the required Supabase environment explicit in CI and local audit scripts.
- Revisit the UI-test debugger-version issue before treating the UI suite as iOS 27 green.
- No app source update is required for the normal iOS 27 build or launch path.
