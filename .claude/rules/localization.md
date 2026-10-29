---
paths:
  - "StatScout/**/*.swift"
  - "StatScoutTests/LocalizationTests.swift"
  - "StatScout/Info.plist"
  - "StatScout/Resources/Localizable.xcstrings"
  - "Tools/Localization/check.py"
  - "project.yml"
---

# Localization

Languages: en (source), es, fr, it, ja, pt-BR, zh-Hant, ko, zh-Hans, de. Chosen from regions with
2+ new customers (2026-10). `project.yml` lists them in `options.knownRegions`, and
`StatScout/Info.plist` lists them in `CFBundleLocalizations`. Rerun `xcodegen generate` after edits.

- One catalog: `StatScout/Resources/Localizable.xcstrings` (sourceLanguage en, every entry
  `extractionState: manual`, every language `translated`). Keys are the English sentence. It is in
  the `StatScout` target's sources, so Xcode compiles the catalog into each language's `.lproj`.
  The team count uses catalog plural variations. Some count-dependent copy is still branched in
  code (see `IntroTrial` and `Package.priceLabel` in `StoreService.swift`).
- `Text("literal")`, `Button`, `Label`, `Section`, `navigationTitle`, `accessibilityLabel` literals localize
  themselves. Copy held in a `String` (view params, enums, view models, errors) must be
  `String(localized: "...")`. A ternary of literals in `Text(...)` does not localize: wrap each branch.
- `Tools/Localization/check.py` checks SwiftUI and `String(localized:)` literals against all nine
  non-English catalog localizations, including placeholder types and counts. Run it after source or
  catalog edits. `StatScoutTests/LocalizationTests.swift` checks that each localization compiles into
  the app bundle and samples new language values.
- StatScout currently has one iOS app target, with no widgets, Watch app, App Intents, or notification
  target. If another target is added, include the shared catalog in its sources and add the target's
  Info.plist `CFBundleLocalizations` list.
- Whole sentences only. Interpolations: `String(year)` for years (an `Int` gets grouped to "2,026" in a
  `Text`), `%@` for strings, `%lld` for counts. Reordered args use `%1$@` in the translation only.
- Never `.capitalized`/`.lowercased()` on translated text. Use `.localizedUppercase` or `.textCase(.uppercase)`.
- Metric labels from the Supabase feed are English data keys. Compare against the raw label, display with
  `MetricName.localized(label)` (`Utilities/Localization.swift`). New feed labels need a case there plus
  catalog entries. Category names use `MetricCategory.title`, not `rawValue`. Enums used as picker
  segments carry a `title` for display and keep `rawValue` as the id.
- `Int.ordinal` uses `NumberFormatter` (locale aware). Dates use `.formatted(.dateTime...)`.
  Prices come only from StoreKit via `priceLabel`/`localizedPriceString`.
- Left in English on purpose: StatScout/StatScout+ names, MLB team and city names, Statcast stat codes
  (PA, IP, BF, BBE, G, AVG, ERA, xwOBA...), units (mph, rpm, ft), blurred teaser placeholder names.

## Adding copy

1. Write the string in code as above.
2. Add the key with all nine translations to `Localizable.xcstrings` (native phrasing, as short as the
   English; labels sit in fixed-width columns).
3. Check coverage: every key has `es fr it ja pt-BR zh-Hant ko zh-Hans de` with matching specifiers,
   no em dashes.
4. Proof with `gh-sim all --screen "-AppleLanguages (ja) -AppleLocale ja_JP -OnboardingPage 2"`.
   DEBUG launch args: `-OnboardingPage 0|1|2`, `-PaywallSnapshot trial|monthly|yearly|lifetime`,
   `-hasCompletedOnboarding YES`. The paywall is SwiftUI (`PaywallView`), not a RevenueCat dashboard
   paywall, so its copy lives in this catalog. Simulators never configure RevenueCat, so the plan cards
   and prices cannot be screenshotted there.
