# Baseball Savvy StatScout audit

Audit date: 2026-08-23
Repository: `/Users/jackwallner/baseball`
App: Baseball Savvy StatScout, bundle `com.jackwallner.baseball`, App Store ID `6763945657`
Audience: implementation agent responsible for growth, conversion, UX, release safety, and repository cleanup

## Scope and evidence boundary

This is a repository audit. It inspected application source, `project.yml`, the generated Xcode project, fastlane metadata and image assets, website files, privacy and terms files, support content, StoreKit and RevenueCat integration, paywall and onboarding code, review prompting, data and event code, backend jobs, tests, CI, release scripts, and agent documentation.

Each finding is labelled as follows:

- **Evidence** means directly observed in a file, measured from a local asset, or reproduced by a read-only repository scan.
- **Inference** means the likely product or operational consequence of that evidence.
- **Recommendation** means the change an implementation agent should validate and then make.

Live App Store Connect downloads, impressions, product page conversion, trial starts, trial-to-paid conversion, proceeds, refunds, ratings, crashes, and RevenueCat charts were not available in this repository. No live metric is fabricated here. Before acting on prioritization, join these recommendations to ASC and RevenueCat exports for the same release and country cohorts.

Per scope, this audit explicitly omits inconsistencies between RevenueCat use and app privacy or tracking disclosures. It does cover purchase-flow correctness, customer attributes, event design, legal link reachability, and operational observability.

## Executive assessment

The product has a credible free-to-value story: current-season player rankings, visual percentile bars, team browsing, standard stats, and nightly updates. The strongest conversion assets are the contextual feature gates and a paywall that leads with yearly, then monthly, then lifetime. The largest risks are not a lack of features. They are measurement gaps and inconsistent operational truth around the features already shipped.

Highest priority:

1. Make iOS CI fail on iOS test failures. `.github/workflows/ci.yml:30-35` ends the test command with `|| true`, so the current release gate can be green while tests fail.
2. Remove the production startup dead end when Supabase configuration is absent. `StatScout/StatScoutApp.swift:9-18,44-59` shows `ConfigMissingView` without a support or diagnostic action and returns before RevenueCat starts.
3. Establish a production release watchdog for crash, hang, data freshness, purchase failures, and first-value regressions. No crash reporting SDK or production event pipeline was found. Existing backend freshness checks also turn missing credentials into a green result at `backend/verify_freshness.py:88-107`.
4. Replace or relabel the stale and misleading App Store screenshot set. `fastlane/screenshots/en-US/05_team.png` is a current-looking team view, while `Screenshots/appstore/05_paywall_pro.png` is a leaderboard image despite its paywall filename. The latter also displays an old May 7, 2026 data date.
5. Treat localization as a conversion project, not only a translated short-field project. All 50 local folders have short fields, but the long descriptions retain a common English product narrative and large English sections. Validate native-language copy and local search demand before spending more effort on every locale.
6. Make trial and plan messaging one coherent system. The onboarding CTA purchases monthly at `StatScout/StatScoutApp.swift:386-414`, contextual surfaces purchase yearly, ASC description copy says monthly and yearly both include a trial, and the design document still says monthly has no trial at `docs/design.md:82-86`.

The implementation agent should instrument the funnel before making broad copy changes. A good first decision is whether the product wants a monthly-first onboarding test or a yearly-first default everywhere. The current code makes that decision differently by surface.

## Product and growth funnel

### Current product promise

**Evidence:** `StatScout/StatScoutApp.swift:419-460` presents three onboarding pages. The first promises qualified-player rankings and daily updates. The second explains Stats, Trends, Teams, and Compare. The third sells Trends, 7/15/30-day form, player matchups, and historical seasons back to 2015. `StatScout/Services/StoreService.swift:22-34` defines 2026 as the current and free season and 2015 as the earliest supported season.

**Inference:** The most valuable free moment is not the paywall. It is seeing a recognizable player, understanding one percentile bar, and discovering that the data is current. The most compelling paid moment is a user who has already asked a specific historical or “who is hot now” question.

**Recommendation:** Optimize the first session around one concrete answer. Make “find a player and understand the ranking” the first-value event. Defer the broad feature tour until after this value is visible, or make the first onboarding screen show a real sample profile with a direct “Explore a player” action.

### Funnel map

| Stage | Current evidence | Main risk | Measurement to add |
|---|---|---|---|
| App Store impression to download | Name, subtitle, keywords, descriptions, screenshots in `fastlane/metadata` and `fastlane/screenshots` | Local metadata may be technically within limits but stale, mixed-language, and visually inconsistent | ASC impressions, product-page views, downloads, custom product-page ID, country, locale, release version |
| First launch | `ReviewPromptTracker.recordAppLaunch()` at `StatScout/StatScoutApp.swift:9-10` | No first-launch or config-failure telemetry; missing config becomes a static dead end | `launch_started`, `launch_ready`, `config_missing`, startup duration, app version/build |
| Data ready | `ContentView` starts `DashboardViewModel.loadIfNeeded()` at `StatScout/StatScoutApp.swift:73-95` | First value depends on Supabase availability and a large player load; errors are generic | `data_request_started`, `data_ready`, row count, coverage date, latency, error class |
| Onboarding completion | `hasCompletedOnboarding` at `StatScout/StatScoutApp.swift:65-87` | Skip and free “Get Started” are not distinguished from a completed tour or a conversion | `onboarding_started`, page viewed, skip, free_exit, completed, completion duration |
| First value | Player/profile and dashboard code, with no general analytics pipeline found | The product cannot identify where users first understand the product | `first_leaderboard_view`, `first_player_open`, `first_metric_detail`, time to first value |
| Feature gate | `PaywallTrigger` cases at `StatScout/Views/PaywallView.swift:4-31` and `TrialPitchSheet` | Repeated gates may feel like interruptions; there is no reliable trigger-to-purchase cohort | trigger, feature, season, player/team context, gate count, dismiss reason |
| Trial start | Direct purchases in `StatScout/StatScoutApp.swift:390-414`, `StoreService.purchase` at `StatScout/Services/StoreService.swift:498-515` | Monthly onboarding and yearly contextual copy differ; eligibility failures are not visible | selected product, offer identifier, eligibility result, purchase outcome, trial start |
| Paid activation | `CustomerInfo.hasProEntitlement` at `StatScout/Services/StoreService.swift:221-239` | Entitlement status is known, but no paid feature activation or time-to-value event exists | entitlement active, first paid feature, restore, renewal, cancellation, refund if available |
| Rating | Local tracker and custom sheet, not a general event pipeline | Prompt exposure and rating outcome cannot be joined to retention or purchase | prompt eligibility, prompt shown, outcome, native review request invoked, app version |

### Download growth opportunities

1. Use App Store Connect custom product pages for distinct intents: “baseball analytics,” “fantasy scouting,” “recent form,” and “player comparison.” Keep the app name stable while testing subtitle, first screenshot, and promotional text independently.
2. Align the first screenshot, page title, and landing page hero around one promise. The current files use “Every player since 2015. Ranked.”, “Who’s hot right now.”, “Scout the league like a pro.”, and other variants. These are all reasonable, but the acquisition system does not state which is the primary promise.
3. Turn the current Trends promotional text into a seasonal test, but gate it by real freshness. `fastlane/metadata/en-US/promotional_text.txt` is a 153-character stretch-run message. It should not promise nightly form if the backend coverage watchdog is red.
4. Add an explicit “free forever” or “no account” proof point only where it increases trust without pushing the paid value below the fold. The current description and website already emphasize this. Repeating it in every screenshot may displace a more differentiating feature.
5. Use the landing page as a measurement surface. `docs/index.html:483-510` has showcase images, but there is no observed campaign attribution or download click event. Add campaign parameters to inbound links and preserve the ASC product-page ID in the landing-page link.

## App Store metadata audit

### en-US exact counts

Counts below are from the local fastlane files, excluding the final newline and counting Unicode code points. Apple’s own field counter remains the final validation authority.

| Field | Local value or file | Count | Apple limit | Assessment |
|---|---|---:|---:|---|
| Name | `Baseball Savvy StatScout` in `fastlane/metadata/en-US/name.txt:1` | 24 | 30 | 6 characters unused, brand-forward |
| Subtitle | `MLB Statcast Percentile Ranks` in `fastlane/metadata/en-US/subtitle.txt:1` | 29 | 30 | 1 character unused, strong intent coverage |
| Keywords | `savant,xwoba,oaa,wrc,wrcplus,stats,exit,velocity,hitting,pitching,fielding,metrics,analytics,fantasy` in `fastlane/metadata/en-US/keywords.txt:1` | 100 | 100 | Full, no spaces after commas |
| Description | `fastlane/metadata/en-US/description.txt:1-41` | 3015 | 4000 | Within limit, long and English-heavy in every locale |
| Promotional text | `The stretch run is on. Track who's heating up into October with nightly Statcast percentiles, 7/15/30-day form, head-to-head matchups, and team scouting.` in `fastlane/metadata/en-US/promotional_text.txt:1` | 153 | 170 | 17 characters unused, seasonal and timely |
| Marketing URL | `https://jackwallner.github.io/baseball/` in `fastlane/metadata/en-US/marketing_url.txt:1` | 39 | no field limit | Reachability and canonical-host check needed |
| Privacy URL | `https://jackwallner.github.io/baseball/privacy-policy.html` in `fastlane/metadata/en-US/privacy_url.txt:1` | 58 | no field limit | Reachability check needed |
| Support URL | `https://jackwallner.github.io/baseball/support.html` in `fastlane/metadata/en-US/support_url.txt:1` | 51 | no field limit | Reachability and contact consistency check needed |

**Evidence:** A local scan found 50 locale folders. Every locale has all five text fields. Name counts range from 24 to 30, subtitles from 24 to 30, keywords from 85 to 100, descriptions from 2692 to 3055, and promotional text from 65 to 170. No local field exceeded the standard limit.

**Inference:** Passing character limits is not evidence of good ASO. The keyword field is full, but it has no `mlb`, `statcast`, `percentile`, or `scout` token. Some of those terms are in the name or subtitle, so deduplication may be intentional, but the strategy is not documented against current search data. The current file and older plans disagree about the intended keyword set.

**Recommendation:** Export current ASC search and product-page cohorts before changing the 100-character field. Run one isolated experiment at a time. Do not change name, subtitle, and keywords together if the goal is to learn causality.

### Localization quality

**Evidence:** `fastlane/metadata` contains 50 folders, including `en-US`, `de-DE`, `fr-FR`, `ja`, `ko`, `zh-Hans`, and regional deprecated locales. A read-only scan found the same English first-line positioning in every description and common English section headings such as `VISUAL PERCENTILES`, `COMPREHENSIVE PLAYER PROFILES`, `A MAJOR STATSCOUT UPDATE`, `STATSCOUT+`, and `PRIVACY-FIRST` in the long copy. Short fields are localized in many folders, while long-form feature and legal copy remains substantially English.

**Inference:** A user can discover the app through a localized title or subtitle and then land on a description that reads as partially untranslated. This can lower trust and weaken conversion in the locales that justified the upload work.

**Recommendation:** Tier locales by downloads and product-page views. For the top tier, native-review the full description, promotional text, subscription paragraph, screenshot text, and support page. For low-volume locales, use a deliberately short, fully translated description rather than a long mixed-language description. Preserve English product and metric names where they are search terms, but translate the surrounding explanation.

### Stale ASO plans and metadata source of truth

**Evidence:** `APP_STORE_SUBMISSION.md:3-6` describes build 1.0 and a next TestFlight submission, despite `project.yml:24-34` declaring marketing version 1.4.4 and build 169. `APP_STORE_SUBMISSION.md:87-93` documents a different keyword string from the live local fastlane keyword file. `docs/astro-asc-metadata-proposal.md:17-35,77-112` proposes older subtitle and keyword variants. `docs/astro-aso-setup.md:5-25` says the last run was 2026-05-26 and records live version 1.0. `docs/localization-aso.md:18-25` also records 1.0 live and 1.1.0 draft.

**Inference:** An implementation agent can make a correct change against the wrong document and overwrite a newer ASC draft or reuse an old strategy.

**Recommendation:** Create one current metadata manifest with `as_of`, ASC version ID, app version, per-locale field hashes, count results, experiment hypothesis, and approval state. Mark every older proposal as historical. Make upload scripts read and validate that manifest, or at minimum fail when a plan’s claimed app version does not match `project.yml`.

### Metadata validation tests

- Count each field using Unicode-aware length, then compare with the Apple limit.
- Reject leading or trailing whitespace, duplicate comma-separated keywords, spaces after commas, empty tokens, trademark claims not approved for use, and accidental prices in description or promotional text.
- Require every localized description to pass a language-quality review flag. A non-AI scanner can flag if more than a configured percentage of section headings exactly match en-US.
- Resolve all marketing, privacy, and support URLs with an HTTP client, follow redirects, require HTTPS, and verify the final host is intentional.
- Compare local metadata hashes with the ASC draft before upload and refuse to upload if the remote draft changed since the last pull.
- Add a release check that the text says “Yearly” and “Monthly” consistently with the actual offer configuration. Do not infer the existence of a trial from copy alone.

## Screenshot, icon, and video audit

### Inventory and technical quality

**Evidence:** Local assets include eight images in `fastlane/screenshots/en-US`, six in `Screenshots/appstore`, eight raw images in `Screenshots/marketing`, and seven rendered images in `docs/images`. The fastlane and App Store image sets are 1320x2868. Marketing captures are 1206x2622. The `docs/images` images are 1320x2868 and were observed as opaque RGB. A read-only image scan found alpha channels on the fastlane, App Store, and marketing PNG sets. A content hash scan found no duplicate image files among the inspected sets. No `.mp4`, `.mov`, or `.m4v` preview video was found under `fastlane`.

**Inference:** Opaque RGB output should be the canonical ASC upload format. Alpha-bearing PNGs may be accepted, but they add avoidable upload and rendering uncertainty. The repository has multiple screenshot truths that are not clearly tied to the current product version.

**Recommendation:** Normalize the final ASC set to 1320x2868, opaque RGB, with one versioned source directory. Keep raw simulator captures separate from upload-ready files. If no preview video is intended, document that decision. If a video is intended, treat it as a separate asset experiment and validate playback, localization, and first-frame quality.

### Content and conversion findings

1. `fastlane/screenshots/en-US/01_stats_hitting.png`, `03_trends.png`, `05_team.png`, and `06_year_compare.png` are polished, captioned marketing compositions. The floating bottom tab bar visibly covers lower rows in several captures. This is a product-layout issue and a screenshot issue.
2. `Screenshots/appstore/01_dashboard_leaderboard.png`, `03_metric_leaders.png`, `04_player_profile.png`, and `06_year_compare_pro.png` are older raw-screen compositions with status-bar time and the text “Updated through games played May 7, 2026.” They do not communicate a distinct benefit as quickly as the captioned fastlane set.
3. `Screenshots/appstore/05_paywall_pro.png` is named and documented as a paywall image, but its visible content is a Leaders screen. It has no plan cards, trial copy, price, or purchase CTA. This is a direct metadata-to-asset consistency defect.
4. `APP_STORE_SUBMISSION.md:33-45` describes six screenshot paths and includes `05_paywall_pro.png` as the paywall frame, so the misleading filename can propagate into an upload review.
5. `docs/images/01_leaderboard.png` and related files use different copy and dates from the fastlane screenshots. `docs/index.html:490-510` references six marketing images, creating another source of truth.
6. The app icon asset inspected in the repository is a red rounded horizontal mark with a baseball on a dark navy field. It is recognizable, but the small-size silhouette and app-name legibility should be tested against nearby baseball analytics results, not judged only at 1024x1024.

### Screenshot experiments

- Test first-frame promise: “Every player ranked” versus “Who’s hot right now.” Keep the rest of the set constant.
- Test a real paywall frame only after the paywall has a stable, deterministic offer and the screenshot is generated from the same release copy.
- Test current data-date language versus evergreen “Updated nightly.” Current dates build trust when fresh, but stale dates are highly damaging.
- Test one screenshot that shows the free experience before the first paid feature. A user should understand what is available without purchase.
- Use OCR and pixel rules in the scanner to detect the old May 7, 2026 date, placeholder `#` links in website assets, and empty or clipped CTA text.

## Install to first value to trial

### Actual onboarding path

1. `StatScoutApp.init` records a launch and requires `SUPABASE_URL` and `SUPABASE_ANON_KEY` at `StatScout/StatScoutApp.swift:9-18`.
2. If configuration is missing, the app creates no API provider and renders `ConfigMissingView` at `StatScout/StatScoutApp.swift:44-59`. RevenueCat startup is skipped because it occurs after the configuration guard.
3. With configuration present, `ContentView` disables the root app until `hasCompletedOnboarding` is true at `StatScout/StatScoutApp.swift:65-87`.
4. The onboarding task fetches RevenueCat products at `StatScout/StatScoutApp.swift:200-203`.
5. The first two pages have a Continue button. Skip is available until the final page at `StatScout/StatScoutApp.swift:164-193`.
6. The final page shows a monthly direct-purchase CTA at `StatScout/StatScoutApp.swift:268-306`. `buyMonthly` purchases the monthly package, or opens the full paywall if the package is unavailable at `StatScout/StatScoutApp.swift:386-414`.
7. A free user can choose Get Started at `StatScout/StatScoutApp.swift:355-383`, which completes onboarding without a product view.
8. Restore Purchases is available on the final page at `StatScout/StatScoutApp.swift:308-350` and on the paywall at `StatScout/Views/PaywallView.swift:512-523`.
9. A successful entitlement change completes onboarding through `StatScout/StatScoutApp.swift:205-213`.

### Conversion risks

**Evidence:** Onboarding purchases monthly. `StoreService` calls the yearly package the “one-tap conversion target” for contextual surfaces at `StatScout/Services/StoreService.swift:359-365`, and `PaywallView` defaults to yearly at `StatScout/Views/PaywallView.swift:470-486`. The ASC description says both Monthly and Yearly have a 7-day free trial at `fastlane/metadata/en-US/description.txt:35-36`. `docs/design.md:82-86` says monthly has no trial and yearly has a trial. `StoreService.introOfferLabel` has a simulator test-key branch for both monthly and yearly at `StatScout/Services/StoreService.swift:195-218`.

**Inference:** A user can see “Start 7-day free trial” in one place, select a different plan in another place, and encounter different trial eligibility. This makes results hard to interpret and can create post-purchase surprise.

**Recommendation:** Decide and document one of these models:

- **Yearly-first:** onboarding and contextual gates direct to yearly, with monthly and lifetime as visible alternatives in the full picker.
- **Monthly-first:** onboarding directs to monthly, contextual yearly claims are removed, and yearly is the picker default only where savings are the primary value.

Then derive all CTA and disclosure strings from one offer state object. The implementation must distinguish “offer available,” “offer ineligible,” “product unavailable,” and “eligibility unknown.”

### Eligibility edge case

**Evidence:** `StoreService.isYearlyTrialAvailable` is driven by `isEligibleForIntroOffer` at `StatScout/Services/StoreService.swift:316-327`. The eligibility helper treats unknown eligibility as eligible at `StatScout/Services/StoreService.swift:424-430`.

**Inference:** A temporary StoreKit or RevenueCat eligibility failure can show trial language and then produce a purchase result without the trial. This is especially risky on a direct CTA that bypasses the plan picker.

**Recommendation:** Use a three-state eligibility model: eligible, ineligible, unknown. Show trial copy only for eligible. For unknown, show the localized product price and a neutral “Continue” or open the full plan picker. Log the reason and product identifier.

### Every paywall entry point found

`PaywallTrigger` defines the following contexts at `StatScout/Views/PaywallView.swift:4-31`:

- `pastSeason`, `lockedSeason(Int)`, `yearCompare`: historical and comparison intent.
- `playerComparison`: second-player or head-to-head intent.
- `onboarding`: final onboarding conversion.
- `activation`, `upgrade`: generic activation or explicit upgrade.
- `pastSeasonsLoad`: loading an older season.
- `teamView`: team scouting intent.
- `winback`: returning or lapsed customer.
- `playerScouting`: soft first-player pitch through `TrialPitchSheet`.
- `recentForm`: blurred recent-form teaser.
- `bestWorst`: Stats view menu.
- `stretchRun`: seasonal late-summer card.

`PaywallGate` caps each trigger at two presentations per session at `StatScout/Services/StoreService.swift:42-58`. Explicit Settings and toolbar paths are intended to bypass that cap, so the event stream must record whether a presentation was contextual or user initiated.

## Paywall and native-flow audit

The repository contains a custom SwiftUI paywall, not an observed RevenueCat `RevenueCatUI` paywall. RevenueCat supplies products, offerings, purchases, entitlement state, and custom paywall impressions. The visible plan picker is app-owned, so most native-looking knobs are controlled in `PaywallView` and `TrialPitchSheet`.

### Current paywall states

| State | Evidence | Audit |
|---|---|---|
| Product loading | `PaywallView.swift:163-199` shows a spinner and “Loading plans…” | Add a timeout state and a retry count. A spinner with no time bound can feel like a dead end. |
| Product empty or fetch failure | `PaywallView.swift:201-223` shows “Couldn’t Load Plans” and Try Again | Good explicit recovery, but the error is generic and no support or diagnostic path exists. Preserve trigger context on retry. |
| Plan content | `PaywallView.swift:225-242` renders a scroll view with feature list, trust row, cards, and purchase section | Confirm the CTA and terms remain visible at large text sizes and on short-height devices. |
| Default selection | `PaywallView.swift:470-486` selects yearly first | Good for a yearly-first strategy, but it must agree with onboarding and the ASC offer. |
| Trial badge and price | `PaywallView.swift:549-622` shows trial, savings, per-month equivalent, and anchor labels | Test whether savings and monthly-equivalent math remain clear in every currency and locale. |
| Purchase in progress | `PaywallView.swift:488-510` disables the flow and shows a progress state through the purchase section | Add a timeout and app-background recovery state. |
| Pending | `PaywallView.swift:499-503` explains Ask to Buy or deferred approval | Validate that the message remains visible after dismissal and relaunch, or add a way to check status. |
| Cancelled | `PaywallView.swift:503-505` says to tap again | Avoid treating cancellation as an error in analytics. Do not immediately re-present the paywall. |
| Purchase error | `PaywallView.swift:506-508` falls back to a generic message | Classify network, StoreKit, billing retry, parental approval, and configuration errors for the watchdog. |
| Restore | `PaywallView.swift:512-523` shows a success through entitlement or a no-active-purchase message | Add a loading timeout and distinguish “no purchase” from “could not reach App Store.” |
| Dismiss | `PaywallView.swift:525-529` protects against duplicate dismissals | Record dismiss reason and whether the user scrolled or selected a plan. |

### Trial pitch sheet

**Evidence:** `StatScout/Views/TrialPitchSheet.swift:86-123` uses a `ScrollView`, fixed `.height(460)` and `.large` detents, and marks the gate on appearance. The footer at `TrialPitchSheet.swift:191-221` has a direct CTA, Terms, Privacy, and Maybe later.

**Inference:** The compact sheet is less intrusive than the former full paywall, but a fixed 460-point detent plus a legal disclosure and four benefit rows is vulnerable to Dynamic Type clipping, small devices, and translated text expansion.

**Recommendation:** Add a layout test at every supported Dynamic Type category, landscape where applicable, and the smallest supported iPhone. Ensure the CTA, price-after-trial disclosure, legal links, close or Maybe later action, and loading state are all reachable without relying on a precise detent.

### Native paywall A/B test matrix

Run one primary experiment at a time. Use a stable assignment key and keep a holdout. The event contract must include app version, locale, product-page source, trigger, and whether the user had reached first value.

| Test | Control | Variant | Primary metric | Guardrails |
|---|---|---|---|---|
| Default plan | Yearly selected, yearly CTA | Monthly selected on onboarding only | Trial start per first-value user | Refund, cancellation, trial-to-paid, revenue per install |
| Trial framing | “Start 7-day free trial” | “Explore StatScout+ free for 7 days” with price-after-trial directly below | CTA tap to completed trial | Support contacts, cancellation within 24 hours |
| Context copy | Generic StatScout+ hero | Feature-specific hero using `PaywallTrigger` | Paywall-to-purchase conversion by trigger | Dismiss, repeat-gate rate, session length |
| Feature order | Trends, recent form, matchups, history | Start with the feature that caused the gate | Conversion after feature lock | Feature comprehension survey or next-session use |
| Price detail | Yearly price plus per-month equivalent | Annual total first, savings second | Completed purchase | Mis-taps, refunds, billing complaints |
| Free exit | “Get Started” link above trial CTA | “Continue with free version” with free feature bullets | Onboarding completion without churn | First-value rate and next-day return |
| Restore placement | Restore under CTA | Restore near the plan cards and in Settings | Restore success | Accidental taps and support volume |
| Sheet shape | 460-point plus large detents | Large-first sheet with content sized to fit | Trial start and dismiss | Accessibility failures, scroll abandonment |
| Seasonal urgency | “Stretch run” copy | Evergreen “recent form” copy | Downloads and trial starts during season | Retention after October and stale-copy incidents |

Native or platform constraints to validate in each test:

- Use localized StoreKit price strings, never hardcode a price in test copy.
- Show the offer duration, post-trial price, auto-renewal, and cancellation timing at the purchase decision.
- Keep Terms and Privacy links reachable before purchase.
- Keep one-tap direct purchase only when product and eligibility state are known.
- Ensure restore is available without forcing a user through a new purchase path.
- Do not use a screenshot harness state as a production experiment assignment.

## RevenueCat audit and instrumentation plan

### Current integration

**Evidence:** Product IDs are defined at `StatScout/Services/StoreService.swift:5-9`. Debug uses a `test_` key and Release uses an `appl_` key at `StoreService.swift:12-20`. The primary entitlement is `StatScout Pro`, with a fallback entitlement `pro` at lines 18-19. `CustomerInfo.hasProEntitlement` checks both entitlements and product ownership at `StoreService.swift:221-239`. Offerings prefer identifier `default` and otherwise use current at lines 256-260. Packages sort yearly, monthly, lifetime, then other at lines 242-253.

Paywall impressions call `Purchases.shared.trackCustomPaywallImpression` through `StoreService.trackPaywallImpression` at `StatScout/Services/StoreService.swift:432-445`. This is the only observed custom RevenueCat analytics call. No general analytics SDK or event transport was found in the repository.

`configureIfNeeded` is at `StoreService.swift:596-609`. The simulator path allows only the test key. No local `.storekit` or `.storekitconfiguration` file was found. The screenshot harness can force product display modes, but a deterministic local StoreKit catalog is not present.

### Customer attributes to add

These are proposed attributes, not current live RevenueCat data. Use low-cardinality values, do not put names, email addresses, or free-form user content into attributes, and confirm the 5.72 SDK API and dashboard limits before implementation.

| Attribute | Values | Exact insertion point | Why |
|---|---|---|---|
| `app_version` | `1.4.4` | After successful RevenueCat configuration at `StoreService.swift:596-609` | Segment conversion and support reports by release |
| `app_build` | `169` | Same configuration point | Separate TestFlight and production regressions |
| `os_major` | `17`, `18`, `26`, etc. | Same configuration point | Detect OS-specific paywall and crash patterns |
| `app_locale` | BCP-47 locale | Same configuration point | Join localization and conversion outcomes |
| `current_season` | `2026` | Same configuration point and on season change | Explain historical-gate intent |
| `onboarding_state` | `not_started`, `in_progress`, `completed_free`, `completed_pro` | At `ContentView` state transitions in `StatScout/StatScoutApp.swift:103-105` and onboarding actions at lines 170-172, 355-362 | Separate education failure from offer failure |
| `first_value_state` | `none`, `leaderboard`, `player_profile`, `metric_detail` | At the first successful screen or data action in the relevant view model | Build a trial cohort around actual value |
| `last_paywall_trigger` | Enum raw value | Before `trackPaywallImpression` at `StoreService.swift:432-445` | Attribute purchase to the gate that caused it |
| `last_paywall_surface` | `paywall`, `trial_sheet`, `inline_blur`, `onboarding`, `settings` | Same impression point | Compare full and soft flows |
| `last_selected_product` | Product identifier | Immediately before `purchase` at `StoreService.swift:498-515` and `purchaseYearlyDirect` at lines 517-542 | Explain plan choice and trial outcomes |
| `last_offer_eligibility` | `eligible`, `ineligible`, `unknown` | When `refreshIntroEligibility` completes at `StoreService.swift:572-582` | Detect misleading trial copy |
| `last_purchase_outcome` | `purchased`, `pending`, `cancelled`, categorized error | After each purchase result in `StoreService.swift:498-542` | Separate user choice from technical failure |
| `last_restore_outcome` | `unlocked`, `no_purchase`, `unavailable`, `error` | After `restorePurchases` at `StoreService.swift:556-569` and the two UI call sites | Find restore friction |

Do not update attributes on every render. Update on meaningful state transitions and use a debounce or change check. Keep the source event ledger in the app or backend if RevenueCat attributes are insufficient for time series analysis.

### Event contract and insertion points

The repository currently lacks a general analytics service. Define these events first, then choose whether they go to a first-party endpoint, a privacy-reviewed analytics product, RevenueCat-supported custom events, or local diagnostic logs. Do not assume arbitrary event names are accepted by the installed RevenueCat SDK.

| Event | Fields | Insertion point |
|---|---|---|
| `app_launch` | version, build, cold/warm, config state | `StatScoutApp.swift:9-18` |
| `startup_ready` | duration, data state, coverage date | after the first successful `DashboardViewModel` load |
| `config_missing` | missing key names, build, environment | `StatScoutApp.swift:11-15` |
| `onboarding_page_viewed` | page index, duration | `OnboardingCards` page change at `StatScoutApp.swift:181-193` |
| `onboarding_exit` | `skip`, `free_get_started`, `purchase`, `restore` | actions at `StatScoutApp.swift:170-172,273-291,325-345,355-383` |
| `first_value` | surface, player or feature category, duration | first successful leaderboard, profile, or metric render |
| `feature_gate_shown` | trigger, feature, season, first-value state | wherever `paywallTrigger` is assigned, plus `TrialPitchSheet` presentation |
| `paywall_impression` | trigger, surface, product count, offering identifier | existing `StoreService.trackPaywallImpression` at `StoreService.swift:432-445` |
| `paywall_cta_tapped` | trigger, selected product, eligibility | `PaywallView.startPurchase` and `OnboardingCards.buyMonthly` |
| `purchase_result` | product, outcome, error class, pending flag | `StoreService.purchase` and `purchaseYearlyDirect` |
| `restore_result` | outcome, duration, product ownership | `StoreService.restorePurchases` |
| `data_freshness_state` | coverage date, expected date, state | when `DashboardViewModel` receives `dataThrough` and when refresh fails |
| `review_prompt_result` | prompt step, outcome, native request invoked | `ReviewPromptSheet` and `RootTabView` review callbacks |

The implementation agent should add a schema version to this event contract and write a local validation test that every event has app version, build, session ID, and timestamp. Do not send player names, email addresses, or raw free-form feedback in these events.

## Ratings and review funnel

### Current flow

**Evidence:** `ReviewPromptTracker.swift:29-41` requires at least five launches, seven days since first open, three positive moments, three distinct use days, and a 120-second cooldown. Eligibility is checked at `ReviewPromptTracker.swift:162-186`. `RootTabView.swift:76-91` waits 3.5 seconds after a positive moment before presenting the custom sheet. `ReviewPromptSheet.swift:39-86` has enjoyment, review pitch, and feedback steps. The review pitch at `ReviewPromptSheet.swift:136-172` opens `AppStoreReviewLinks.writeReviewURL`; a later path in `RootTabView.swift:43-59` invokes the native `requestReview` request after a soft defer. Settings also has a direct review link at `SettingsView.swift:209-273`.

**Inference:** The funnel is thoughtfully throttled, but it has two rating actions: a direct App Store URL and a native review request. The app can count local prompt state, yet cannot tell whether the native sheet appeared, whether the App Store URL opened, or whether a user rated. A user who gives negative feedback is routed to mail, which is good for support but needs outcome measurement.

**Recommendation:**

- Keep the positive-moment gate, but test thresholds against first-session retention and prompt conversion. Five launches and seven days may be too late for a high-satisfaction user and too early for a casual user.
- Treat native review request and direct App Store link as separate experiments. Do not call both in one user journey.
- Record `review_prompt_shown`, `review_positive`, `review_negative`, `review_maybe_later`, `native_request_invoked`, `write_review_opened`, and `feedback_mail_opened`.
- Tie the prompt to a successful value moment, such as a player profile opened after data loaded, not merely a navigation action.
- Add a quiet settings path for users who deferred, without repeatedly interrupting the main flow.

## UX state and accessibility audit

### States that are handled

- Pending purchases are explained at `StatScout/StatScoutApp.swift:400-412` and `PaywallView.swift:496-508`.
- Cancelled purchases are not treated as successful and can be retried.
- Restore with no active entitlement is surfaced in onboarding and paywall.
- Paywall product loading and empty states have visible UI and retry.
- Legal links appear in onboarding at `StatScout/StatScoutApp.swift:254-262`, TrialPitchSheet at `TrialPitchSheet.swift:191-221`, and the paywall purchase section.
- Paywall cards expose selected state and plan details at `PaywallView.swift:562-622`.
- `DashboardViewModel` has explicit loading and error state, and its recent-form task code avoids stale empty-cache behavior at `DashboardViewModel.swift:226-374`.

### Gaps and likely poor flows

1. **Configuration failure:** `ConfigMissingView` is a dead-end screen with no visible support link or copy showing how to recover. Add a support action, a copyable diagnostic identifier, and a release-only assertion or watchdog event. Do not expose secrets.
2. **Network failure:** `StatcastAPI` uses `URLSession.shared.data(for:)` and generic `URLError(.badServerResponse)` paths at `StatcastAPI.swift:53-75,103-115,142-154,217-237`. There is no explicit request timeout policy, retry/backoff, status-class UI, or offline cached snapshot path in these calls.
3. **Lenient decoding:** `StatcastAPI.swift:240-247` drops malformed rows. Player fetch detects an all-zero decode page at lines 223-231, but other endpoints can return partial data without a quality warning.
4. **Recent-form failure:** `DashboardViewModel.swift:351-368` does not cache an empty result and reports a generic error. Add a clearly actionable empty-season state distinct from network failure.
5. **Bottom-bar obstruction:** `RootTabView` keeps tab views mounted and overlays a custom floating tab bar at `RootTabView.swift:107-197`. Screenshot inspection showed the bar covering lower list content. Add bottom content insets and UI tests that tap or read the last row.
6. **Light mode only:** `StatScoutApp.swift:37-40,49-52` forces a light color scheme. `docs/design.md:159-165` calls this intentional. Validate contrast, Increase Contrast, Larger Text, Reduce Motion, VoiceOver labels, and color-independent percentile meaning. If dark mode remains unsupported, make that choice explicit in the support documentation.
7. **Fixed sheet height:** `TrialPitchSheet.swift:86-123` uses a 460-point detent. Test large accessibility sizes and translations. A fixed height is particularly risky for the legal and price-after-trial block.
8. **Loading without expiry:** `StoreService` exposes `isLoadingProducts` and `lastError`, but the UI has no stated maximum wait. Add timeout copy, a retry, and a route back to the free feature where the trigger is contextual.
9. **App background during purchase:** Purchase and restore tasks do not document behavior if the app backgrounds or the StoreKit sheet is interrupted. Add tests for background, foreground, lock, and relaunch while pending.
10. **No local StoreKit catalog:** No `.storekit` file exists. The current debug test-key behavior is useful for simulator screenshot states, but it does not provide offline deterministic purchase testing.

### Accessibility validation matrix

For each onboarding page, trial sheet, paywall package card, restore path, error state, and review prompt, test:

- Dynamic Type from the smallest accessibility size through the largest supported size.
- VoiceOver order, labels, selected traits, and whether hidden reserved layout slots are actually hidden.
- Tap targets at least 44 by 44 points, including close, Maybe later, Restore, Terms, Privacy, and plan cards.
- Bold Text, Increase Contrast, Reduce Motion, and color filters.
- English, German, French, Japanese, and one right-to-left locale.
- Short height, long localized strings, no network, slow network, StoreKit pending, and product-empty states.

## Website, legal, support, and data consistency

### Canonical links and copy

| Surface | Evidence | Risk and action |
|---|---|---|
| App legal URLs | `StoreService.swift:36-40` points to Apple Standard EULA and `docs/privacy-policy.html` | Keep these as the only in-app purchase links. Test HTTP 200 and mobile layout. |
| Terms page | `docs/terms.html:98-149` | Contains subscription, renewal, cancellation, and Apple EULA language. Revalidate product periods and trial text against the actual offering before release. |
| Privacy page | `docs/privacy-policy.html:98-149` and `PRIVACY.md:3-31` | Both are dated Aug 17, 2026, but contact and supporting documentation differ. |
| Support page | `docs/support.html:90-160` | Describes nightly refresh and iOS 17 support. Add release status, data freshness status, and purchase troubleshooting. |
| Support email | `PRIVACY.md:19,31` uses `support@statscout.app`; source feedback uses `jackwallner+bb@gmail.com` at `ReviewPromptSheet.swift:232-254` and Settings uses the same source contact | Pick one monitored address and use it in privacy, terms, support, feedback, and ASC review information. |
| Main landing page | `docs/index.html:483-622` | Has the real App Store link and legal footer, but hardcoded offer prices and version need a single-source review. |
| Alternate landing page | `docs/baseball-savvy.html:545-552,562-568` | App Store button uses `href="#"`; footer lacks Terms. Treat as noncanonical, redirect it, or archive it after confirming no external traffic. |
| Structured data | `docs/index.html:28-60` | Offers are hardcoded at $5.99 monthly, $14.99 yearly, and $39.99 lifetime, while softwareVersion is 1.4.3. Current app config is 1.4.4/build 169. Prices and version are unverified against live ASC/RevenueCat and should not drift silently. |
| Data-source wording | `docs/index.html:570-603`, `README.md:8-11`, `backend` jobs | The website says MLB Stats API or public data in places while the app reads Supabase tables populated by scheduled jobs. State the user-facing source and refresh semantics consistently. |

Per scope, no finding is made about whether the RevenueCat customer data declaration matches the privacy copy. The actionable consistency issue here is link, contact, product-term, version, price, and operational-status drift.

### Website conversion recommendations

- Make `docs/index.html` the only canonical product page. Give it a stable App Store link, terms link, privacy link, support link, release version, and a visible price-disclaimer string that is generated or reviewed with the offering.
- Replace the alternate page’s `#` download href before any campaign points to it. Until then, a non-AI scanner should fail on any App Store button with `href="#"`.
- Add a short “What is free” and “What StatScout+ unlocks” comparison near the first download CTA. The current page states that core features are free at `docs/index.html:570-582`, but it is below the primary showcase and not structured as a decision aid.
- Add a support status block for data freshness, purchase restoration, and known outages. It should be manually controlled or generated from the watchdog, not claim real-time health when the app is not real-time.

## Data pipeline and degraded experience

### Backend freshness

**Evidence:** `backend/refresh_guard.py:64-82` returns `-1` when MLB schedule lookup fails and logs that it is assuming a slate. Missing Supabase credentials at `refresh_guard.py:85-90` logs an error and lets the run proceed. `backend/verify_freshness.py:47-63` also returns `-1` for schedule failure, and `verify_freshness.py:88-107` returns fresh when credentials are missing. The final-attempt failure behavior is at `verify_freshness.py:110-127`. The nightly workflow creates a GitHub issue after final failure at `.github/workflows/nightly-statcast.yml:143-155`.

**Inference:** A missing secret or an upstream schedule outage can produce a green or continuing workflow without proving that the app data is current. The code has good freshness intent and a prior stale-data incident is documented, but unknown is currently too close to healthy.

**Recommendation:** Change freshness checks to tri-state: fresh, stale, unknown. Unknown must fail the final attempt and page the owner separately from a data-stale issue. Include last successful coverage date, expected date, job run ID, row counts, and upstream response status in the artifact and issue.

### Data quality checks

Add non-AI assertions to the ingestion and release watchdog:

- Current season exists and is the expected year.
- `player_snapshots` row count stays within a configurable range and does not drop to zero.
- `player_game_logs` and `player_recent_form` coverage dates agree with the expected completed-game date.
- Recent-form row counts for 7, 15, and 30-day windows are nonzero when games exist.
- Duplicate `(player_id, season, window_days)` rows are zero.
- `TBD`, empty team, empty position, malformed player ID, and null metric rates stay below thresholds.
- Percentiles stay within 0 to 100, and metric arrays are not empty for an abnormal fraction of rows.
- A sample of known players has stable name, team, and metric keys across a refresh.
- API response status, latency, bytes, and decoded row counts are recorded.
- A current database schema check includes `player_game_logs` and `player_recent_form`, not only `player_snapshots`.

`supabase/schema.sql:1-34` describes `player_snapshots`, while those additional tables are created in migrations `supabase/migrations/20260519000000_create_player_game_logs.sql` and `supabase/migrations/20260725000000_create_player_recent_form.sql`. Add a schema drift check so a new environment cannot look healthy while the canonical schema file is incomplete.

## Release regression and deprecated-API signals

### Current release risks

1. **CI does not gate:** `.github/workflows/ci.yml:30-35` uses a named simulator destination and `|| true`. It can hide compile, test, simulator, and runtime failures.
2. **Project drift:** `project.yml:24-34` declares build 169, while the existing generated `StatScout.xcodeproj/project.pbxproj` has observed app build setting 168. The generated project is already modified in the working tree and was not changed by this audit. Reconcile through the normal XcodeGen workflow before implementation.
3. **Test harness drift:** `StatScoutTests/UpgradeCTATests.swift:4-31` comments that the simulator cannot configure RevenueCat and that a StoreKit configuration cannot change that. `StoreService.swift:596-609` now permits a test key on simulator builds, so the comment and test strategy are stale.
4. **No production crash or hang channel:** No crash-reporting SDK, crash dashboard integration, hang monitor, or production diagnostic upload was found. The website even states no crash reporting at `docs/index.html:590-603`, so a separate operational watchdog is required if the owner wants release oversight.
5. **External dependency fragility:** `StatcastAPI.swift` makes repeated Supabase requests without an explicit timeout, retry budget, backoff, circuit breaker, or request-level telemetry. The backend depends on MLB schedule, Savant data, pybaseball, GitHub Actions, and Supabase.
6. **Fastlane version evidence:** `fastlane/Deliverfile:1-54` and release documentation expect fastlane 2.234+, while the existing generated `fastlane/report.xml` records a failed run using an older 2.230-era path. Treat reports as historical evidence, but make the release script fail if the binary is below the supported version.
7. **Deprecated API scan:** No obvious `NavigationView` or other known deprecated SwiftUI navigation pattern was found in the inspected source. Current source uses `NavigationStack`, `@Observable`, `requestReview`, and availability checks. This is not a substitute for compiler warnings and SDK matrix builds.
8. **Known prior UX regressions:** `DashboardViewModel.swift:236-250` documents a Trends empty-state task race, and lines 273-304 document stale recent-form cache across an overnight refresh. Keep regression tests for these paths and add release-watchdog checks around the resulting coverage labels.

### Release-watchdog signals

The separate MacBook scaffold requested by the owner should be configurable and notification-only until deployed. It should poll or ingest these signals without sending user data:

| Signal | Source | Trigger | Urgency |
|---|---|---|---|
| Crash-free users and sessions | ASC crash reports or chosen crash provider | New release below baseline by an absolute and relative threshold | Immediate |
| Crash signature count | Crash provider export | Same signature affects multiple users or grows across two checks | Immediate |
| Hang or watchdog termination | ASC or device diagnostics | New release exceeds baseline, especially on launch, onboarding, paywall | Immediate |
| Launch-to-ready p50/p95 | App event stream or local synthetic test | p95 exceeds budget or regresses after build change | High |
| Data freshness | `verify_freshness.py` artifact and Supabase query | Unknown or stale at final attempt, or coverage date regresses | Immediate |
| App empty-state rate | Event stream | Player or recent-form empty state above baseline | High |
| Purchase failure rate | StoreKit or RevenueCat export | Error rate or pending rate rises after release | Immediate |
| Restore failure rate | Event stream and support mailbox | Multiple no-purchase or unavailable outcomes in a cohort | High |
| Paywall load time | Event stream | p95 exceeds a configured budget or timeout rate rises | High |
| Rating prompt health | Local event stream and ASC rating trend | Prompt shown but native request path drops, or rating trend falls after a build | Medium |
| Website checks | HTTP and content scanner | Broken App Store, legal, privacy, support, or placeholder links | High |
| CI health | GitHub Actions API or artifacts | Any iOS test failure, skipped test, or stale artifact | High |

Minimum watchdog configuration should include app ID, bundle ID, release version source, baseline window, polling interval, thresholds, email recipient, SMTP or local mail transport, and a cooldown. Notification scaffolding should be dry-run by default, write JSON reports, and never include credentials or raw customer identifiers in an email.

## Prioritized implementation findings

| ID | Severity | Finding and evidence | Impact | Effort | Confidence | Validation |
|---|---|---|---|---|---|---|
| F-01 | P0 | iOS CI masks all test failures at `.github/workflows/ci.yml:30-35` | Regressions can ship unnoticed | S | High | Inject a failing test and confirm CI fails; run headless leased simulator tests |
| F-02 | P0 | Missing Supabase config creates a dead-end `ConfigMissingView` and skips StoreService startup at `StatScoutApp.swift:9-18,44-59` | A misconfigured build cannot recover or report the cause | S | High | Launch with each key absent; verify support path, diagnostic ID, and watchdog event |
| F-03 | P0 | No production crash, hang, or general event observability found | Multi-user release regressions may remain invisible | M | High | Install a staging build, generate a controlled fault, verify redacted alert and release cohort |
| F-04 | P0 | Freshness checks treat missing credentials and schedule uncertainty as healthy or runnable at `backend/refresh_guard.py:64-90` and `verify_freshness.py:47-107` | Stale data can be presented as current | S | High | Mock schedule and credentials failures; final attempt must become unknown and fail |
| F-05 | P1 | App Store screenshot named as paywall is a leaderboard and old date at `Screenshots/appstore/05_paywall_pro.png` | Lower download trust and inaccurate review submission | S | High | OCR/image review confirms plan cards, price, legal copy, and release date in final asset |
| F-06 | P1 | Fastlane/App Store/marketing screenshot sets differ, and several PNGs have alpha | ASC may receive stale or technically noncanonical assets | S | High | Asset scanner enforces one manifest, opaque RGB, dimensions, hashes, and release version |
| F-07 | P1 | 50 locale descriptions contain common English sections despite localized short fields | Weak conversion and trust outside English locales | M | High | Native review top locales, then compare product-page conversion by locale |
| F-08 | P1 | Trial model is inconsistent across onboarding, contextual yearly surfaces, ASC description, and `docs/design.md:82-86` | Confusing CTA and unreliable experiment interpretation | M | High | Automated copy-to-offer check plus StoreKit and sandbox tests for each product |
| F-09 | P1 | Unknown intro eligibility can produce trial copy at `StoreService.swift:424-430` | Users may see a trial promise they cannot receive | S | High | Mock eligible, ineligible, and unknown states; assert copy and purchase behavior |
| F-10 | P1 | Website structured data hardcodes prices and version 1.4.3 at `docs/index.html:28-60`; alternate page uses `href="#"` at `docs/baseball-savvy.html:545-552` | Paid acquisition and search snippets can show stale or broken information | S | High | Scanner fails on stale version, unapproved price, placeholder href, or missing terms link |
| F-11 | P1 | Support contacts differ between `PRIVACY.md:19,31` and source mail links | Users and review teams may reach an unmonitored address | S | High | One canonical contact fixture must match all app, web, metadata, and review files |
| F-12 | P1 | Paywall and trial sheet have generic errors, no timeout, and fixed compact detent at `PaywallView.swift:191-223` and `TrialPitchSheet.swift:86-123` | Users can abandon or repeatedly tap a dead purchase flow | M | High | Network, StoreKit pending, offline, Dynamic Type, background, and timeout UI tests |
| F-13 | P1 | Bottom tab bar overlays visible rows in `RootTabView.swift:107-197` and screenshot captures | Users cannot see or tap the last data row; screenshots look unfinished | S | High | Automated last-row visibility and tap test on every tab and device size |
| F-14 | P1 | Backend/API has no broad quality contract, request telemetry, timeout budget, or retry policy at `StatcastAPI.swift:53-247` | Partial or slow data can look like a normal empty state | M | Medium | Fault-injection tests for 401, 429, 500, timeout, malformed row, zero row, and slow page |
| F-15 | P2 | Review flow tracks local eligibility but not native sheet or App Store URL outcomes at `ReviewPromptTracker.swift:162-203`, `RootTabView.swift:43-91` | Rating experiments cannot be optimized against product outcomes | S | High | Event contract test and manual native/direct-link path audit |
| F-16 | P2 | `project.yml` build 169 differs from generated project build 168 | Upload and debugging may target different build identifiers | S | High | Generate project, compare settings, archive, and assert one version/build source |
| F-17 | P2 | No local StoreKit configuration, and a stale simulator test comment exists at `UpgradeCTATests.swift:4-31` | Purchase UI tests are less deterministic and agents may follow obsolete guidance | M | High | Add a test catalog or explicit test-key harness, then update the comment and tests |
| F-18 | P2 | Agent and release docs describe old versions and old UI at `APP_STORE_SUBMISSION.md`, `docs/design.md`, `docs/astro-*`, and `handoff/*` | Cursor, Claude, and Codex agents may implement obsolete decisions | M | High | Documentation scanner reports version, date, status, and duplicate canonical instructions |

## Non-AI scanner specification

The implementation agent can build most of the following as a deterministic Python or shell program. Each rule should emit JSON with rule ID, severity, path, line, observed value, expected value, and remediation text.

| Rule | Deterministic check | Failure example |
|---|---|---|
| `ASC-001` | Count name, subtitle, keywords, description, promotional text for every locale | Keyword count over 100 or empty locale file |
| `ASC-002` | Split keywords, trim tokens, reject duplicates, whitespace after commas, and empty tokens | `foo, foo` or `foo, bar` |
| `ASC-003` | Compare metadata file hashes with the checked-in manifest and report missing or extra locales | A locale exists in ASC manifest but not in fastlane |
| `ASC-004` | Flag descriptions whose section headings and first paragraph exactly match en-US above a configured ratio | Mixed-language long description |
| `ASC-005` | Detect hardcoded prices, stale version strings, and dated “updated through” phrases outside approved release files | Website still says 1.4.3 while project is 1.4.4 |
| `URL-001` | Resolve all URLs in metadata, Markdown, HTML, and Swift legal constants | 404, HTTP, redirect loop, or unexpected host |
| `URL-002` | Reject App Store CTA links with `#`, empty href, or non-App-Store target | `docs/baseball-savvy.html:550` |
| `URL-003` | Compare support and feedback email addresses across source, Markdown, HTML, fastlane review info, and metadata | `support@statscout.app` versus Gmail contact |
| `ASSET-001` | Check screenshot dimensions, color mode, alpha, file size, and supported file extension | Alpha-bearing upload asset or wrong dimensions |
| `ASSET-002` | Hash all screenshots and report duplicate content under different names | Same image in two claimed variants |
| `ASSET-003` | OCR for placeholder, old data date, missing CTA, and known wrong screenshot labels | `05_paywall_pro.png` has no paywall words |
| `BUILD-001` | Parse `project.yml`, generated pbxproj, Info.plist, Fastfile, and scripts for marketing version and build | Project says 169, generated project says 168 |
| `BUILD-002` | Reject CI destinations by device name and test commands ending in `|| true` | `.github/workflows/ci.yml:34-35` |
| `BUILD-003` | Check fastlane binary version against the documented minimum | Older binary than 2.234 |
| `IOS-001` | Run Swift source pattern checks for known deprecated APIs and compiler warnings with warnings-as-errors in CI | `NavigationView` or unavailable API without guard |
| `IOS-002` | Ensure all public paywall and onboarding CTA paths have loading, cancel, pending, error, and restore handling | New direct purchase path without `PurchaseState.pending` |
| `RC-001` | Compare product IDs, entitlement names, offering identifier, and docs | Product identifier appears in source but not test fixture or docs |
| `RC-002` | Require every paywall trigger assignment to emit the same trigger identifier before presentation | Gate can be shown without attribution |
| `RC-003` | Ensure trial copy is conditional on eligible, not unknown | Trial label shown when eligibility is unresolved |
| `DATA-001` | Query expected tables, max coverage dates, row counts, null rates, ranges, and duplicate keys | Zero recent-form rows after a game day |
| `DATA-002` | Treat missing credentials or upstream schedule failure as unknown, not fresh | Final freshness check passes without credentials |
| `DATA-003` | Compare `supabase/schema.sql` table/index/policy declarations with every migration | Canonical schema omits recent-form table |
| `DOC-001` | Find version claims and compare to `project.yml` and release manifest | Docs say live 1.0, project says 1.4.4 |
| `DOC-002` | Detect dated plans without status labels and duplicate agent instructions | Old handoff reads like current direction |
| `DOC-003` | Detect forbidden em dash characters in new generated docs | Unicode U+2014 in audit or scanner output |
| `WATCH-001` | Read release and health JSON, compare current window to baseline, and emit dry-run alert | Crash or freshness threshold exceeded |
| `WATCH-002` | Enforce alert cooldown and include version/build, rule, observed value, threshold, and dashboard link | Repeated duplicate email without context |

The scanner should have `--repo`, `--json`, `--markdown`, `--fail-on`, `--baseline`, `--dry-run`, and `--changed-only` options. It should never mutate the repository by default. A separate `--fix` mode can be added later for mechanical whitespace or generated manifests, but it should require an explicit output directory.

## Agent workspace and documentation hygiene

### Current state

`AGENTS.md` is a symlink to `CLAUDE.md`, which is the right direction for one shared source of agent guidance. `.claude/` exists but is empty. No project-local `.cursor` or `.codex` instruction directory was found. `archive/README.md:1-10` correctly describes archive content as historical. The problem is that several current-looking documents contain old versions, obsolete UI, or old experiment decisions.

### Keep, update, archive, and move classification

| Classification | Files or directories | Action for implementation agent |
|---|---|---|
| Keep as source | `AGENTS.md` symlink, `CLAUDE.md`, `project.yml`, `StatScout/`, tests, `scripts/`, `fastlane/metadata/`, `fastlane/Fastfile`, `docs/index.html`, `docs/privacy-policy.html`, `docs/terms.html`, `docs/support.html` | Keep paths stable. Update content only after verifying the source of truth. |
| Update in place | `README.md`, `APP_STORE_SUBMISSION.md`, `docs/design.md`, `docs/astro-asc-metadata-proposal.md`, `docs/astro-aso-setup.md`, `docs/localization-aso.md`, `aso-plan.md`, `ios27StatScout.md` | Add an explicit “as of” date, app version, status, owner, and links to current manifests. Remove claims contradicted by source. |
| Archive as history | `archive/*`, dated metadata backup directories, completed campaign plans, old screenshot exports | Preserve for recovery, but add a visible historical marker and do not link from the agent start path as current guidance. |
| Move or redirect | `docs/baseball-savvy.html` | First confirm external traffic. Redirect to `index.html` or move to an archive folder after replacing the `#` App Store link. |
| Move or rewrite | `handoff/STATSCOUT_SAVANT_HANDOFF.md`, `handoff/SAVANT_PLAYER_PAGE_REFERENCE.html`, `handoff/APP_STORE_PREVIEW_HANDOFF.md` | Put active handoffs in a single current runbook with owner, date, status, and next action. Move completed handoffs under archive. |
| Quarantine generated evidence | `fastlane/report.xml`, screenshots, simulator mirrors | Keep generated output out of canonical agent instructions. Record only the conclusion and source path. |

### Canonical Cursor, Claude, and Codex layout

Use one policy source and tool-specific pointers, not three competing copies:

```text
baseball/
  AGENTS.md -> CLAUDE.md
  CLAUDE.md                    current app and agent contract
  README.md                    current developer and release overview
  project.yml                  XcodeGen source of truth
  StatScout/
  StatScoutTests/
  StatScoutUITests/
  scripts/
  fastlane/
  docs/
    index.html                 canonical landing page
    privacy-policy.html
    terms.html
    support.html
    agent/                     current runbooks and test matrices
    marketing/                 current ASO and campaign decisions
    archive/                   historical web drafts
  handoff/
    CURRENT.md                 one active handoff, if needed
    archive/                   completed handoffs
  .cursor/
    rules/README.md             pointer to CLAUDE.md, no duplicated policy
  .claude/
    README.md                   pointer to CLAUDE.md, no duplicated policy
  .codex/
    README.md                   pointer to CLAUDE.md, no duplicated policy
```

If tool-specific files are unnecessary, do not create them. The important rule is that a Cursor, Claude, or Codex agent opening the repo sees the same canonical instructions and a clearly marked current-doc area. Every runbook should state `status: current|historical|blocked`, `as_of`, owner, and the source files it was checked against.

### Documentation acceptance rules

- Any document that names an app version must match `project.yml` or state why it is historical.
- Any document that describes a paywall must list the current product IDs, entitlement, trial policy, and source symbols.
- Any document that describes screenshots must include the asset manifest and generation date.
- Any document that says “live,” “current,” “shipped,” or “next” must include an `as_of` date.
- Dated plans remain useful only if their decision outcome is recorded.
- Do not make an agent infer whether a document is a plan, handoff, archive, or current runbook from its filename alone.

## Recommended implementation order

### Release safety first

1. Fix CI failure masking and named simulator destination.
2. Reconcile `project.yml` and generated project build settings through the normal XcodeGen process.
3. Add tri-state backend freshness and data-quality assertions.
4. Add a dry-run release watchdog with crash, hang, freshness, purchase, CI, URL, and asset inputs.
5. Add startup configuration diagnostics and a support path.

### Conversion and UX second

6. Decide yearly-first versus monthly-first trial policy.
7. Make eligibility unknown distinct from eligible.
8. Add the event contract and customer attributes at the exact transition points above.
9. Fix paywall and trial-sheet timeout, Dynamic Type, restore, background, and error states.
10. Add first-value measurement before running paywall experiments.

### Acquisition and documentation third

11. Select one screenshot source, replace the misleading paywall frame, normalize alpha, and regenerate release assets.
12. Tier and review long-form localization.
13. Make the main landing page canonical and repair or redirect the alternate page.
14. Reconcile support email, legal copy, prices, versions, and data-source wording.
15. Classify and update stale agent docs, then add the deterministic scanner to CI in report-only mode before enabling failure thresholds.

## Validation checklist for the implementation agent

### Repository and release

- [ ] Only intended files changed after each focused change.
- [ ] `xcodegen generate` was run after project or Swift source changes.
- [ ] Generated project version and build equal the release manifest.
- [ ] iOS tests run against a leased headless simulator, not a named destination.
- [ ] CI fails on a deliberately failing test.
- [ ] Fastlane version meets the documented minimum.
- [ ] TestFlight archive uses the expected bundle, version, build, and configuration.

### Store and acquisition

- [ ] All five ASC fields pass counts in every locale.
- [ ] Localized long descriptions have native review status.
- [ ] URLs resolve and point to canonical pages.
- [ ] Screenshot manifest lists current version, dimensions, alpha mode, and hashes.
- [ ] No App Store button has a placeholder href.
- [ ] Screenshot OCR has no old date or mislabeled paywall.
- [ ] Live ASC metrics are captured before and after each isolated experiment.

### Trial, paywall, and restore

- [ ] Onboarding and contextual surfaces use the same trial policy.
- [ ] Eligible, ineligible, and unknown states have separate copy and behavior.
- [ ] Monthly, yearly, and lifetime products are shown with localized prices.
- [ ] Purchase, cancel, pending, failure, background, timeout, and restore are tested.
- [ ] Terms and Privacy are reachable before purchase.
- [ ] Large text, VoiceOver, RTL, short height, and poor network are tested.
- [ ] Paywall trigger, selected product, offer eligibility, and outcome are captured.

### Production watch

- [ ] A controlled staging crash produces a redacted dry-run notification.
- [ ] A repeated crash signature triggers once per cooldown window.
- [ ] A fresh data check is green, stale is red, and unknown is a distinct alert.
- [ ] A missing Supabase credential cannot create a green freshness result.
- [ ] Purchase and restore error rates are compared with a prior release baseline.
- [ ] App startup, first value, paywall load, and data coverage are visible by build.

## Final conclusion

The codebase already contains several thoughtful fixes: session-scoped paywall gating, pending purchase copy, a fixed onboarding layout, recent-form task joining, coverage-date alignment, and a throttled review prompt. The next gains come from making those decisions measurable and consistent across surfaces. Fix release safety and unknown-data handling before optimizing copy. Then unify trial policy, instrument first value and purchase context, and clean the asset and documentation sources of truth. This sequence gives the implementation agent a safer basis for improving downloads, trial starts, revenue, ratings, and day-to-day user experience without guessing from unavailable live metrics.
