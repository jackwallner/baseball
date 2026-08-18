# StatScout 2026 Stretch Run Campaign

## Decision

Ship a seasonal **Stretch Run** campaign for the 2026 playoff chase, with a
real but controlled discount on the existing yearly StatScout+ subscription.
Use an Apple custom offer code for the first annual term, keep the normal
monthly, yearly, lifetime, and 7-day introductory-offer paths intact, and sell
the campaign through the features that already exist in the app: Trends, recent
form, team scouting, player comparison, and historical context.

Do not add a postseason data product, a new seasonal SKU, or a lifetime sale in
the first version. Do not make team-specific playoff claims until the app has a
fresh, authoritative standings feed.

This is the best balance of urgency, real customer value, reversible economics,
App Store safety, and implementation scope.

## Review convergence log

Two independent five-agent reviews agreed with the central strategy but found
implementation details that needed tightening. Revision 7fa5377 incorporated
their material findings:

- Apple cohorts are new and expired only for V1. Active, grace-period,
  billing-retry, lifetime, and unknown customer states are suppressed.
- The seasonal code does not stack with the existing introductory offer. The
  normal 7-day offer remains available through See all plans.
- The initial $19.99 US price is a hypothesis pending live App Store Connect
  verification, not a proven optimum.
- The App Store redemption URL is primary. The native code-entry sheet is
  secondary, followed by syncPurchases() and RevenueCat customer refresh.
- Apple expiration, UTC dates, a hardcoded cutoff, reviewed creative IDs,
  recent-form freshness, holdout measurement, and Apple revenue reporting are
  explicit in the plan.

For the next review, a 100/100 means no material factual, commercial,
implementation, compliance, or measurement blocker remains. Do not reopen a
resolved point as a stylistic preference. Raise it only with new repository,
Apple, RevenueCat, or current-season evidence.

### Review protocol

Each subsequent verifier reviews this current working-tree revision, not an
earlier commit. A score below 100 must name only a material blocker and give the
smallest exact edit needed. A score of 100 means no edit is requested. Do not
reopen the resolved eligibility, no-stacking, localized-price, redemption
fallback, creative allowlist, privacy, stale-data, or expiry decisions without
new evidence. Append the verifier's score and evidence here so the same issue
does not loop across reviews.

Final RevenueCat and StoreKit verifier: 100/100. The repository's project.yml
targets iOS 17.0 and pins RevenueCat from 5.72.0. That SDK exposes
presentCodeRedemptionSheet() on iOS 14 and later, syncPurchases() as an async
throwing API returning CustomerInfo, and the receivedUpdated customer-info
delegate used by StoreService. The App Store URL path, native sheet fallback,
entitlement refresh, Apple Sales and Trends revenue source, RevenueCat initial
offer-revenue limitation, and exhaustive PaywallTrigger scope all match the
repository and current vendor guidance. The implementation wording below
explicitly requires handling the async sync result and failure fallback.

### Final verifier gate, August 17, 2026

Five final verification lenses reviewed the current working-tree decision:

| Lens | Score | Decision check |
|---|---:|---|
| Seasonal timing and playoff framing | 100/100 | August 20 to 24 target, August 31 hard launch cutoff, generic stretch-run copy, September 30 in-app end date |
| Offer economics and Apple mechanics | 100/100 | Existing yearly SKU, provisional $19.99 US test, new and expired cohorts, no trial stacking, Apple localized terms |
| Audience, trial separation, and UX | 100/100 | High-intent free and eligible expired users, known-customer-state suppression, redemption URL primary, standard plans retained |
| Measurement and post-launch criteria | 100/100 | Stable 80/20 holdout when instrumentation is available, Apple Sales and Trends for initial revenue, explicit keep, revise, and stop rules |
| Implementation, privacy, and compliance | 100/100 | Allowlisted reviewed creative, hard cutoff, no remote entitlement grants, MLB non-affiliation disclosure, TestFlight redemption validation |

Final disposition: 5/5 verification lenses at 100/100. No material blocker or
undecided launch choice remains in this strategy. The $19.99 amount remains a
deliberate hypothesis, not a claim of optimal pricing, and cannot be activated
until App Store Connect confirms the live annual baseline, offer price,
eligibility, no-stacking choice, renewal behavior, and storefronts. Future
review should add new evidence only, not reopen these settled decisions.

Current revision hardening: the campaign cutoff is recorded as the exact UTC
instant 2026-10-01T06:59:59Z, activation fails closed without trusted time, and
cached config is used only for transient fetch failures. Explicit disable,
malformed, stale, or expired responses invalidate the cache immediately.

## Executive recommendation

### Campaign concept

**Name:** StatScout+ Stretch Run

**Positioning:** The playoff picture is tightening. StatScout helps fans find
the players shaping the race before the postseason.

**Recommended merchandising window:** Launch as soon as the approved binary and
Apple offer are ready, ideally August 20 to August 24, 2026, and no later than
August 31. Keep in-app merchandising active through September 30, covering the
final regular-season push and the opening Wild Card games. Set the Apple code's
expiration date to October 1 because Apple expires codes at 12:00 a.m. Pacific
on the selected date. The hardcoded in-app cutoff is
2026-10-01T06:59:59Z, which is September 30 at 11:59 p.m. Pacific. If the build
is not ready by August 31, move the start and end dates together. Never ship
copy that says an offer is active when its Apple offer is not active.

**Offer code:** STRETCH26

**Product:** Existing yearly subscription,
com.jackwallner.baseball.pro.yearly

**US price hypothesis:** $19.99 for the first annual term, then the standard
yearly price, if App Store Connect confirms that the live US yearly price is
$29.99 after the August 12 price raise. Treat $19.99 as the initial test price,
not a validated optimum. The exact price must be configured and confirmed in
App Store Connect, then shown through Apple's localized purchase and redemption
surfaces. Never hardcode $19.99 into the app for every storefront.

**Discount model:** If the live US annual price is $29.99, the initial test is
approximately 33% off. This is a modeling assumption, not proof that $19.99 is
the optimal price. Compare net revenue per eligible user against the post-raise
baseline before extending or changing it.

**Renewal:** The customer sees the standard localized yearly renewal price after
the discounted term. The final terms shown by Apple are authoritative.

**Audience:** High-intent free users who have never purchased, plus eligible
expired subscribers. Configure only Apple's new and expired cohorts for V1.
Exclude active subscribers, including billing-retry and grace-period states,
because the public code can be redeemed outside the app. Hide the campaign from
lifetime users and from any customer whose RevenueCat state is not yet known.

**Primary CTA:** Claim the Stretch Run offer

The primary CTA opens the prefilled App Store redemption URL. A secondary
in-app redemption path can call Apple's native sheet and tell the customer to
enter STRETCH26 manually. The normal See all plans path remains available and
continues to use the existing RevenueCat purchase flow.

### Why this fits the moment

As of August 17, 2026, the regular season has 41 calendar days remaining. MLB's
official schedule puts the final regular-season day on Sunday, September 27,
and Wild Card games begin Tuesday, September 29. The official Wild Card table
shows a genuine race rather than a generic seasonal excuse: the Yankees and Red
Sox lead the American League field, while Baltimore, Texas, Detroit, Toronto,
Minnesota, Cleveland, and Seattle are clustered around the final position. In
the National League, Chicago leads the Wild Card field, Philadelphia and San
Diego are close behind, and Arizona is within one game of the third position.

The campaign should use that urgency without freezing today's standings into
the binary. Standings change every day, and the app currently has no standings
or playoff-odds data source. The truthful product message is therefore about
the stretch run and the players shaping the picture, not about a specific team
being in or out.

Sources checked on August 17, 2026:

- [MLB 2026 Wild Card standings](https://www.mlb.com/standings/wild-card)
- [MLB 2026 regular-season schedule announcement](https://www.mlb.com/press-release/press-release-mlb-announces-2026-regular-season-schedule)
- [MLB 2026 postseason schedule](https://www.mlb.com/postseason)

## What the repository says today

### Purchase architecture

The app has one centralized RevenueCat purchase layer. It does not have a
second native StoreKit purchase manager, a seasonal offering selector, or
offer-code redemption plumbing.

- RevenueCat is the SPM dependency in [project.yml](project.yml#L2-L5).
- Startup calls StoreService.shared.start() in
  [StatScoutApp.swift](StatScout/StatScoutApp.swift#L1-L24).
- Product identifiers are centralized in
  [StoreService.swift](StatScout/Services/StoreService.swift#L5-L9).
- The existing products are monthly, yearly, and lifetime. All unlock the
  existing StatScout+ entitlement.
- The normal purchase path is Purchases.shared.purchase(package:) in
  [StoreService.swift](StatScout/Services/StoreService.swift#L498-L516).
- RevenueCat customer updates arrive through the existing delegate in
  [StoreService.swift](StatScout/Services/StoreService.swift#L612-L618).
- The app already refreshes customer information when returning to the
  foreground in [StatScoutApp.swift](StatScout/StatScoutApp.swift#L39-L55).

This means the seasonal campaign should extend the existing store layer. It
should not introduce StoreKit purchase code that can race RevenueCat or create
a second entitlement path.

### Prices and the important source conflict

The active app does not hardcode the current price. It reads localized prices
from RevenueCat's StoreProduct and calculates annual monthly equivalents and
savings in [StoreService.swift](StatScout/Services/StoreService.swift#L136-L184)
and [StoreService.swift](StatScout/Services/StoreService.swift#L398-L420).
That is the correct foundation for a promotion.

The repository has conflicting historical price references:

| Source | Values | Interpretation |
|---|---:|---|
| Commit 1fa94ba, staged August 10 | $5.99 / $29.99 / $59.99 | Planned post-raise monthly, yearly, lifetime values effective August 12 |
| docs/index.html | $5.99 / $14.99 / $39.99 | Stale landing-page values; not safe for offer math |
| Untracked postseasonplan.md | $1.99 / $4.99 / $9.99 | Older pre-raise values; not authoritative |
| Runtime paywall | Localized StoreKit values | Source of truth for the customer |

Before creating the offer, verify the current US and target-storefront prices
directly in App Store Connect and RevenueCat. Use the actual yearly product
price returned by Apple when calculating the discount. Do not use any of the
stale web or planning values as a runtime fallback.

Using the planned post-raise US values only for economic modeling:

- Monthly annualized: $5.99 × 12 = $71.88.
- Standard yearly: $29.99, already about 58% below twelve monthly payments.
- Modeled Stretch Run test: $19.99, about 33% below the standard yearly price.
- Modeled Stretch Run monthly equivalent: about $1.67.
- Lifetime: $59.99, unchanged. It is already only 2x standard annual, so
  discounting it would make one-time access too attractive and damage recurring
  revenue.

The app's localized price strings and existing plan-card savings calculation
should remain the authority. The seasonal campaign should never draw a fake
strikethrough price from a hardcoded US string.

### Existing upgrade surfaces

The app already has enough useful surfaces to make a seasonal campaign feel
native:

| Surface | Existing location | Recommended campaign use |
|---|---|---|
| Full plan picker | [PaywallView.swift](StatScout/Views/PaywallView.swift#L134-L176) | Add a seasonal banner and offer-code CTA while retaining all normal plans |
| Direct yearly CTA | PlusDirectCTA in Components.swift | Keep for standard price and trial purchases; do not pretend it applies the code |
| Feature-gated teaser | BlurGateUnlock in Components.swift | Add seasonal copy to Trends, recent form, compare, and team scouting entry points |
| One-time update sheet | [UpdateShowcaseView.swift](StatScout/Views/UpdateShowcaseView.swift#L8-L36) | Keep the existing product-update campaign separate, or add a dedicated seasonal campaign mode |
| Toolbar upgrade | RootTabView.swift | Open the normal seasonal paywall entry point without repeated automatic prompts |
| Settings upgrade | SettingsView.swift | Provide a persistent, explicit route to the offer and standard plans |
| RevenueCat impressions | PaywallTrigger in [PaywallView.swift](StatScout/Views/PaywallView.swift#L4-L115) | Add stretchRun with a stable impression ID |

The current PaywallGate limits contextual paywalls to two presentations per
trigger per session. The campaign should use a one-time update/card decision
and explicit user action, not a new paywall on every player profile.

### Current data limitations

The app has current player snapshots, game logs, recent form, and data coverage
dates. It does not have standings, games-back, playoff probability, postseason
rosters, or a playoff data model. StatScoutSeason.current is also hardcoded to
2026 in [StoreService.swift](StatScout/Services/StoreService.swift#L21-L34).

That is not a blocker for a generic Stretch Run campaign. It is a blocker for
claims such as:

- The Orioles are 0.5 games out.
- These are the players most likely to reach October.
- Your team is still alive.
- Live playoff odds.
- Postseason stats are now available.

Do not build a standings feature as part of this promotion unless it is a
separate, fully verified product project.

## Offer mechanics

### Recommended: Apple custom offer code on the existing yearly product

Create a paid offer code in App Store Connect for the current yearly
subscription. A custom code is the only Apple mechanism in this situation that
can reach both new customers and previously purchased customers without
changing the base price for every subscriber.

Apple's current documentation says offer codes can provide a free or discounted
period for auto-renewable subscriptions, can be configured for new, existing,
and expired subscribers, and can be redeemed through the App Store, a redemption
URL, or an in-app StoreKit sheet. See [Apple's
offer-code setup guide](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes)
and [Apple's StoreKit offer-code support](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).

Configure:

| Field | Recommendation |
|---|---|
| Product | Existing yearly StatScout+ SKU |
| Reference name | stretch-run-2026-yearly |
| Custom code | STRETCH26 |
| Offer type | Pay up front, one year |
| US price hypothesis | $19.99, only after ASC confirms the live annual baseline and a valid price point |
| Eligibility | New and expired subscribers only for V1; exclude active subscribers, including grace-period and billing-retry states |
| Introductory offer interaction | No stacking for V1. Keep the existing 7-day introductory offer on the See all plans path |
| Redemption limit | Start conservatively, for example 10,000; increase only if demand justifies it |
| Expiration | Apple expiration October 1, 2026 at 12:00 a.m. Pacific Time; hardcoded in-app cutoff 2026-10-01T06:59:59Z |
| Local prices | Use Apple's comparable price calculation, then review high-volume storefronts manually |

The code is not a secret. It is a campaign identifier and discount key. A
redemption limit and expiration date make leakage bounded. A unique reference
name also makes offer-code sales attributable in App Store Connect and
RevenueCat.

App Store Connect offer configurations cannot be edited after creation. Confirm
the product, eligibility, introductory-offer interaction, one-year duration,
price point, storefronts, and renewal behavior before creating the production
offer. If one of those choices changes, create a new offer rather than assuming
the existing configuration can be repaired.

### Redemption flow

Implement both paths:

1. **Primary path:** open the prefilled App Store redemption URL so the customer
   does not have to type the public code:
   https://apps.apple.com/redeem?ctx=offercodes&id=6763945657&code=STRETCH26
2. **Secondary in-app path:** call
   Purchases.shared.presentCodeRedemptionSheet() when supported. The native
   sheet does not prefill STRETCH26, so label this path as entering a code.
3. When returning from the external App Store URL, call
   Purchases.shared.syncPurchases(), then refresh RevenueCat customer
   information. For the native sheet, rely on the existing RevenueCat customer
   information listener because Apple does not provide a redemption callback.
   Dismiss the seasonal sheet when the entitlement becomes active.
4. If Apple or RevenueCat does not propagate the entitlement immediately, show a clear
   Refresh purchase status or Restore Purchases fallback. Do not report a
   failed purchase merely because RevenueCat is briefly pending.

RevenueCat documents the redemption sheet and App Store URL flow, but also
warns that the in-app sheet has had reliability issues. The fallback URL is
therefore part of the design, not an afterthought. Upload the required Apple
In-App Purchase key to RevenueCat so offer-code transactions are accurately
tracked. RevenueCat notes that initial offer-code purchases may appear as $0 in
its revenue chart because of Apple data limitations. Use [Apple Sales and
Trends](https://developer.apple.com/help/app-store-connect/measure-app-performance/download-and-view-reports)
for initial offer revenue, and use RevenueCat for attribution, entitlements,
renewals, and retention. Do not place the key in the app.

Relevant RevenueCat references:

- [RevenueCat iOS subscription offers](https://www.revenuecat.com/docs/subscription-guidance/subscription-offers/ios-subscription-offers)
- [RevenueCat offer-code paywall support](https://www.revenuecat.com/docs/tools/paywalls/creating-paywalls/supporting-offers)

### What the app should show before redemption

The app cannot safely treat the ordinary RevenueCat yearly package as the
discounted package. The current package is still the standard product, and a
code redemption is handled by Apple's offer flow.

Use this hierarchy:

- Seasonal card: Limited-time first-year offer
- Supporting line: Redeem STRETCH26 to unlock the seasonal price. Apple shows
  your localized offer terms before purchase.
- CTA: Claim the offer
- Secondary action: See all plans
- Legal line: The offer applies for the stated discounted period, then the
  subscription renews at Apple's displayed yearly price unless cancelled at
  least 24 hours before renewal. Manage or cancel in Apple Account subscription
  settings.

For a US-only launch brief, the intended terms can say:

~~~text
$19.99 for your first year, then the standard yearly price. Exact price and
renewal terms vary by storefront and are shown by Apple before purchase.
~~~

This is planning copy, not a universal runtime string. Do not infer an App Store
storefront from Locale.current. Unless the app has a verified storefront-aware
offer object containing the localized price and renewal terms, omit the number
and let Apple's redemption surface display the exact offer.

Do not show a crossed-out $29.99 beside the ordinary yearly plan unless the
app has a verified StoreKit offer object containing both the localized offer and
base prices. A hardcoded sale badge would be misleading in other storefronts
and after any price schedule change.

### Offers that should not be the primary mechanism

#### Temporary base-price decrease

Apple's subscription pricing documentation says that when an auto-renewable
subscription price is decreased, existing subscriptions automatically renew at
the lower price and the higher price cannot be preserved. It also allows only
one future price change per storefront and billing plan type.

This would produce the cleanest-looking paywall, because the existing dynamic
plan card would show the lower price automatically. It would also:

- Give the discount to existing subscribers who did not need an incentive.
- Undercut the August 12 price raise almost immediately.
- Make the campaign's renewal treatment less explicit.
- Consume the price-change control plane for the yearly product.
- Create a sharp price experience for anyone who just purchased at the raised
  price.

Do not use a temporary base-price decrease for this campaign.

Source: [Apple subscription pricing and price decreases](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions).

#### Promotional offer with RevenueCat signing

Apple promotional offers can provide a smooth, native discounted purchase, but
they are intended for existing or previously subscribed customers. They require
an Apple subscription key, signed offer requests, and reliable eligibility
handling. They are useful later for a dedicated lapsed-subscriber win-back
campaign, not for the broad Stretch Run acquisition audience.

Source: [Apple promotional offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions).

#### New seasonal annual SKU

Do not create a second yearly product for this first campaign. The current code
sorts packages by product type, and yearlyPackage returns the first annual
package. A second annual SKU would require explicit offering selection,
entitlement mapping, upgrade and downgrade behavior, duplicate plan-card
handling, new review metadata, and cleanup after the campaign. It is too much
surface area for a time-limited test.

#### Discounted lifetime

Do not discount com.jackwallner.baseball.pro. A lifetime discount is difficult
to retract for customers who already redeemed it, cannibalizes annual revenue,
and would compound the fact that the current lifetime price is already only 2x
the planned annual price. The campaign should buy a first annual relationship,
not permanently sell the catalog at a clearance price.

#### New non-renewing seasonal pass

A seasonal pass would make the offer concept easy to explain, but it would be a
new entitlement model with new App Store review, new expiry behavior, a second
purchase path, and a poor transition to next season. Revisit only if annual
subscription conversion remains weak after a controlled offer-code pilot.

## Campaign UX

### Free-user experience

Present the campaign after onboarding and after current-season data is ready.
Do not interrupt the first launch before the user has seen the product.

Recommended order:

1. A small, dismissible dashboard card near the top of the current-season
   experience:

   **THE STRETCH RUN IS ON**

   **Know the players shaping October.**
   Trends, recent form, team scouting, and head-to-head comparisons for the final
   push.

2. Tapping the card opens the seasonal campaign sheet.
3. Claim the offer opens the prefilled App Store redemption URL. The secondary
   in-app path opens Apple's code-entry sheet.
4. See all plans opens the existing PaywallView.
5. Not now dismisses the card for the current campaign and does not trigger a
   second automatic modal in the same session.

The dashboard card should be shown once per campaign unless the user explicitly
opens it from Settings or a locked feature. The PaywallGate rule remains the
backstop for contextual prompts.

### Pro-user experience

Do not show a discount to a current StatScout+ user. Show a useful product
message instead:

> Your Stretch Run toolkit is active. Open Trends to find the biggest movers,
> Recent Form to catch hot streaks, or Compare to test the matchups behind the
> playoff picture.

The Pro path should deep-link to an existing feature. It should feel like a
benefit announcement, not an offer the customer missed.

### Lapsed-user experience

Use the seasonal message, but do not assume the user is eligible for a
promotional offer merely because RevenueCat's isLapsed is true. Apple owns offer
eligibility. The offer-code path can be shown; Apple's sheet decides whether
the account can redeem it. A later lapsed-only promotional offer can be added
after the general campaign is measured.

### New-user experience

Do not put the sale before the user has seen a player profile or the
leaderboard. Keep the existing onboarding trial path. The campaign can appear
after onboarding completion or from the normal upgrade entry point.

### Suggested copy

#### Campaign sheet

- Eyebrow: THE STRETCH RUN IS ON
- Title: Know the players shaping October.
- Body: The playoff picture is tightening. Use recent form, Trends, team
  scouting, and head-to-head comparisons to find the difference-makers before
  the postseason.
- Offer label: LIMITED-TIME FIRST-YEAR OFFER
- Primary CTA: Claim the offer
- Secondary CTA: See all plans
- Dismissal: Keep using the free version

#### Paywall trigger

- Title: Scout the stretch run
- Subtitle: Find the players heating up, compare the matchups that matter, and
  see the seasons behind today's race.
- Offer banner: Redeem STRETCH26 for the seasonal first-year offer.

#### Store metadata promotional text

> The stretch run is here. Track the players shaping the playoff picture with
> current-season Statcast rankings, recent form, comparisons, and team
> scouting.

Do not put the discount amount or a fixed price in permanent store metadata.
Prices vary by storefront and change over time. Before editing metadata, follow
the repository's required pull-and-diff workflow in the ios-dev guidance.

#### Copy to avoid

- Official MLB playoff intelligence
- Guaranteed playoff picks
- Your team is going to October
- Live playoff odds, unless a real odds feed exists
- Postseason stats, unless postseason data has been separately ingested and
  labeled
- Team-specific games-back numbers without an as-of timestamp

Retain the existing non-affiliation language for MLB, MLB Advanced Media,
MLBPA, and teams.

Place a compact non-affiliation statement on the campaign sheet or its
information path. Do not rely on a disclaimer that exists only in Settings when
the seasonal card uses MLB, postseason, or team language.

## Implementation plan

### Phase 0: verify the commercial state

Before writing app code:

- Verify the live yearly, monthly, and lifetime prices in App Store Connect.
- Verify the current RevenueCat products and default offering.
- Verify the app and associated subscription meet the current App Store Connect
  production offer-code requirements, including the approved in-app purchase
  state and the sale/distribution status shown in App Store Connect.
- Verify the existing 7-day introductory offer remains configured as intended.
- Record the introductory-offer interaction explicitly. For V1, choose no
  stacking so the seasonal code gives the discounted annual term and the normal
  7-day introductory offer remains a separate See all plans choice.
- Upload the Apple In-App Purchase key to RevenueCat if it is not already
  present.
- Create a sandbox offer code and a production custom code only after the
  product state is confirmed.
- Record the exact offer price, duration, eligibility, expiration, storefronts,
  and redemption limit in the release checklist.

Do not alter the current monthly or yearly introductory offers. The fleet
pricing guidance explicitly says to preserve them. The app should describe
these as offers attached to subscriptions, not as separate trial products.

### Phase 1: add a safe campaign control plane

The campaign should be remotely disableable. Add a small Supabase-backed campaign
record rather than burying every marketing decision in a release binary.

Suggested table shape:

~~~text
campaign_id              text primary key
season                   smallint not null
enabled                  boolean not null default false
starts_at                timestamptz not null
ends_at                  timestamptz not null
creative_id              text not null
offer_code               text not null
offer_reference          text not null
minimum_data_age_hours   integer not null default 48
~~~

The first row can be stretch-run-2026. Add the migration, read policy, client
decoder, production and preview data providers, and test mock coverage as part
of the change. The client must enforce all of these rules:

- enabled is true.
- The fetched campaign timestamps are UTC. Use a trusted server timestamp from
  the campaign response when available. If trusted time is unavailable, fail
  closed rather than activating the campaign from an untrusted device clock.
  A device clock may make an active campaign disappear, but must never activate
  or extend it beyond the hardcoded cutoff 2026-10-01T06:59:59Z.
- The campaign season matches StatScoutSeason.current.
- The creative_id, offer code, and offer reference match app-allowlisted values.
- Localized campaign copy comes from the reviewed binary for the creative_id.
  Do not ship arbitrary headline or body text from remote config.
- Recent-form coverage is within the allowed age, using the existing
  DashboardViewModel.dataThrough value where available. This is not a universal
  freshness timestamp for every player snapshot.
- Missing, malformed, stale, or expired config fails closed to the ordinary
  paywall.
- A last-known-good config is cached for at most six hours and never beyond the
  hardcoded cutoff. Use that cache only for transient fetch failures. An
  explicit disabled, malformed, stale, or expired response invalidates the
  cache immediately.
- Remote config controls merchandising only. It must never grant Pro or alter
  entitlement state.

For a strictly one-off release, a compiled SeasonalCampaign value type with the
same UTC date and allowlist checks is the safer fallback. A remote flag is useful
for a kill switch, but it must not extend the hardcoded cutoff or replace the
reviewed creative.

Do not add standings_as_of to the V1 campaign unless the campaign actually
renders standings. If a future version adds team-specific claims, then add
standings_as_of, standings_source, and a separate standings freshness check.

### Phase 2: app changes

Recommended file-level changes:

1. Add SeasonalCampaign and a small campaign-fetching layer next to the existing
   services. Update the Supabase migration, read policy, production and preview
   providers, decoder, and test mock together.
2. Add PaywallTrigger.stretchRun, icon, title, subtitle, feature copy, and
   statscout_paywall_stretch_run impression ID in PaywallView.swift. Update every
   exhaustive PaywallTrigger switch, including TrialPitchSheet.swift.
3. Add a presentOfferCodeRedemption method to StoreService that calls
   Purchases.shared.presentCodeRedemptionSheet(). Keep normal purchase and
   restore methods unchanged.
4. Add the prefilled App Store redemption URL as the primary offer path. When
   returning from that URL, call try await
   Purchases.shared.syncPurchases(), apply its returned CustomerInfo through
   StoreService, and then refresh customer information if needed. If sync
   throws, preserve the pending state and offer Refresh purchase status or
   Restore Purchases rather than reporting a failed purchase.
5. Add a dedicated seasonal card or sheet. Do not overload the existing
   UpdateShowcaseCampaign identifier with two unrelated campaign meanings.
6. Add a one-time lastSeenSeasonalCampaign AppStorage decision, matching the
   pure decision-test pattern already used by UpdateShowcaseCampaign.
7. Keep the existing full plan picker and a clear See all plans route.
8. Suppress the offer for active, grace-period, billing-retry, and lifetime
   users. Wait for a known RevenueCat customer state before rendering it, since
   isPro initially defaults to false.
9. Add only privacy-reviewed campaign events if card-to-tap and redemption
   funnel metrics are required. The existing paywall impression call does not
   measure those events.
10. Add a debug-only force flag such as STATSCOUT_FORCE_STRETCH_RUN=1, never
    enabled in Release.

If any new Swift file is added or project.yml changes, run xcodegen generate.

### Phase 3: copy and App Store metadata

Keep the permanent store listing evergreen. Update only promotional text or
release notes with the seasonal editorial message. Do not add an expiring price
to descriptions, keywords, screenshots, or the privacy policy.

If a new build is needed for the redemption flow, include App Review notes with:

- The offer code and its test/sandbox instructions.
- The dates when the offer is active.
- The path from launch to the seasonal card.
- The fallback path to the standard plans.
- A statement that Apple displays localized price and renewal terms.

The app must still be fully usable and the standard purchase path must remain
discoverable if the offer has expired.

Keep the offer duration, renewal price, and cancellation language clear at the
purchase point, consistent with [Apple's subscription review guidance](https://developer.apple.com/app-store/review/guidelines/).

## Measurement plan

Do not add a new analytics SDK for this campaign. The app currently has no
analytics or ad SDK and should preserve that privacy posture. If the campaign
adds event counters beyond RevenueCat impressions, review privacy wording and
App Privacy disclosures before release.

Use the following sources:

- RevenueCat custom paywall impression ID:
  statscout_paywall_stretch_run.
- App Store Connect Sales and Trends reports, segmented by offer code, for
  initial offer revenue.
- RevenueCat offer attribution, entitlement state, renewals, and retention after
  the Apple key is configured. Initial offer-code revenue may appear as $0 in
  RevenueCat's revenue chart.
- Support messages and redemption-failure reports.

The current app does not measure seasonal-card-to-tap or redemption attempts.
Add minimal privacy-reviewed counters if those funnel metrics are required;
otherwise mark them unavailable rather than presenting them as existing data.

Track:

| Metric | Why it matters | Decision use |
|---|---|---|
| Seasonal card impression to offer-sheet tap | Measures merchandising relevance | Copy and placement |
| Offer-code redemption rate | Measures friction and demand | Keep, fix, or retire flow |
| Annual starts per eligible user | Primary acquisition outcome | Incremental conversion |
| Trial starts and trial-to-paid | Protects the existing funnel | Ensure the sale does not hide the trial |
| First renewal / 30-day active rate | Tests customer quality | Discount is not success if users immediately churn |
| Lifetime share of revenue | Detects cannibalization | Keep lifetime price protected |
| Refunds and support complaints | Detects misleading terms or bad redemption | Kill switch and copy repair |
| Revenue per eligible install | Measures net economics | Compare with the post-raise baseline |

Use a stable per-install 80/20 holdout if the campaign instrumentation is added:

- 80% see the seasonal offer.
- 20% see the same seasonal value message, but only the standard plans and
  introductory offer.
- Keep assignment stable for the campaign and measure annual starts, trial
  starts, net revenue per eligible user, redemption failures, refunds, and
  lifetime cannibalization.

Use the post-raise window as context, not as the only causal baseline. If a
holdout cannot be implemented without adding unreviewed tracking, run an
observational pilot and do not claim incremental lift.

### Success thresholds

Set the thresholds before launch. A reasonable first-pass decision rule is:

- Keep the campaign if annual starts per eligible user and net revenue per
  eligible user beat the holdout without materially worse refunds.
- Keep it only if first-renewal and retention rates are not materially worse
  than the holdout or the post-raise standard annual cohort.
- Stop or revise it if offer-code redemption is low because of UI friction,
  even if the underlying demand is strong.
- Stop it if lifetime share rises enough to offset annual revenue gains.
- Stop it immediately if the offer terms shown in the app differ from the Apple
  purchase sheet.

The exact numeric thresholds should come from the current RevenueCat cohort
volume. Do not invent a statistically precise lift target before checking the
sample size.

## Testing and verification

### Unit tests

Add tests for:

- Campaign is inactive before starts_at.
- Campaign is active inside the valid window.
- Campaign is inactive after ends_at.
- Disabled, missing, malformed, stale, and wrong-season config fails closed.
- Missing trusted time fails closed; explicit disable, malformed, stale, or
  expired responses invalidate a cached config.
- Unknown customer state, active monthly/yearly, grace-period, billing-retry,
  and lifetime users do not see the acquisition offer.
- The campaign creative, offer reference, and link use the app-allowlisted
  STRETCH26 configuration. Apple, not the app, validates entered codes.
- The hardcoded cutoff wins over cached remote configuration and device-clock
  changes.
- The no-stacking introductory-offer rule is reflected in copy and tests.
- Seasonal PaywallTrigger copy and impression ID are stable.
- Existing UpdateShowcaseCampaign behavior remains unchanged.
- The standard See all plans purchase path remains available.

### Store and device states

Test on a real sandbox or TestFlight build, not only a plain simulator launch:

- Never purchased, eligible for the normal trial.
- Never purchased, redeemed seasonal offer.
- Trial active, then offer-code attempt.
- Trial expired without paid conversion.
- Active monthly subscriber.
- Active yearly subscriber.
- Subscriber in billing retry or grace period.
- Paid yearly subscriber.
- Lapsed yearly subscriber.
- Lifetime owner.
- Offer code invalid, expired, exhausted, or ineligible.
- User cancels the redemption sheet.
- User redeems through the App Store URL and returns to the app.
- App Store URL return calls syncPurchases() before customer refresh.
- Entitlement update delayed.
- Offline at campaign-config fetch.
- Offline at product fetch.
- Campaign disabled remotely while the app has cached config.

For simulator work, never configure the production appl_ RevenueCat key. The
existing simulator guard requires the test key. A real offer-code redemption
flow needs a sandbox/TestFlight check because the app has no active .storekit
configuration and the native Apple redemption sheet is not represented by an
empty simulator paywall.

### Release verification

Before release:

- Run xcodegen generate if source or project configuration changed.
- Run the full unit and UI test suite against a leased headless simulator using
  -destination "id=$UDID".
- Inspect the seasonal card, standard paywall, offer-code sheet entry point,
  fallback URL, and Pro state transitions.
- Verify every price shown in the normal paywall is StoreKit-localized.
- Verify no runtime price claim relies on Locale.current as a storefront proxy.
- Verify the seasonal text does not claim a specific team status.
- Verify the non-affiliation statement is reachable from the seasonal surface.
- Archive and upload a TestFlight build for any app-code change, following the
  repository's scripts/testflight.sh path after credentials are sourced.
- Test the real offer on TestFlight/Sandbox with a non-production test account.
- Record the exact ASC offer configuration in the release notes.

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---:|---:|---|
| Apple redemption sheet fails or hangs | Medium | High | App Store redemption URL fallback, foreground refresh, Restore Purchases |
| Discounted amount is wrong in a storefront | Medium | High | Apple owns price display, no hardcoded global amount, test multiple currencies |
| Current price references remain inconsistent | High | Medium | Verify ASC and RevenueCat before setup; keep runtime dynamic; fix web copy separately |
| Offer code is leaked | Medium | Low | Treat code as public, cap redemptions, expire after the campaign |
| Offer appears after the postseason window | Medium | Medium | Apple expiry, UTC client dates, hardcoded cutoff, remote kill switch, and season check |
| Stale player data makes urgency claim look false | Medium | Medium | Use generic stretch-run copy and hide campaign on stale coverage |
| Existing trial is accidentally removed or hidden | Low | High | Preserve intro offers, keep normal plan cards, test trial eligibility |
| Active customer sees an acquisition offer before RevenueCat syncs | Medium | High | Wait for known customer state; test active, grace-period, and billing-retry states |
| Lifetime cannibalizes annual | Medium | High | Do not discount lifetime, measure lifetime share, suppress offer for lifetime owners |
| A second annual SKU creates duplicate cards | Low | High | No new SKU in V1, use offer code on existing yearly product |
| Remote copy changes after review | Low | High | Remote creative ID only, reviewed localized copy in binary, hardcoded cutoff |
| RevenueCat reports initial offer revenue as zero | Medium | Medium | Use Apple Sales and Trends for initial revenue; use RevenueCat for renewals and entitlements |
| App Review cannot discover or test the offer | Medium | High | Review notes, sandbox code, standard paywall fallback, stable in-app route |
| Remote config grants entitlement | Low | Critical | Remote config controls copy and merchandising only; RevenueCat remains authoritative |
| The campaign claims MLB affiliation | Low | High | Generic language, existing non-affiliation disclaimer, no MLB branding or guarantees |

## Rollout checklist

### Commercial setup

- [ ] Verify live ASC prices and yearly product approval.
- [ ] Verify RevenueCat default offering and entitlement mapping.
- [ ] Confirm live annual baseline and provisional test price.
- [ ] Create stretch-run-2026-yearly paid offer.
- [ ] Configure new and expired subscribers only for V1.
- [ ] Configure no stacking with the existing introductory offer.
- [ ] Create sandbox code and test it.
- [ ] Create production custom code STRETCH26.
- [ ] Set redemption limit and October 1 Apple expiration, with the hardcoded
  2026-10-01T06:59:59Z in-app cutoff.
- [ ] Upload or verify the RevenueCat Apple In-App Purchase key.

### Product and code

- [ ] Add remote campaign row or safe compiled fallback.
- [ ] Add seasonal card/sheet and one-time dismissal.
- [ ] Add seasonal PaywallTrigger and impression ID.
- [ ] Add the App Store URL primary path and native redemption-sheet fallback.
- [ ] Call syncPurchases() after returning from the App Store URL, then refresh customer info.
- [ ] Keep standard plans, restore, terms, privacy, and trial copy intact.
- [ ] Add unit tests and debug force flags.
- [ ] Regenerate Xcode project when needed.

### Listing and release

- [ ] Pull current App Store metadata before any metadata edit.
- [ ] Add evergreen seasonal promotional text without a fixed price.
- [ ] Prepare App Review notes and sandbox instructions.
- [ ] Build and test headlessly with a leased simulator.
- [ ] Test offer redemption on TestFlight/Sandbox.
- [ ] Upload TestFlight for the app-code build.
- [ ] Commit only task-owned files and push the focused change.

### Post-launch

- [ ] Confirm offer-code transactions are attributed in RevenueCat and Apple Sales and Trends.
- [ ] Check redemption failures daily during the first week.
- [ ] Check current player-data coverage and campaign config freshness.
- [ ] Review annual starts, trial conversion, lifetime share, and refunds.
- [ ] Disable the campaign after September 30 or earlier if the kill criteria fire.
- [ ] Remove seasonal merchandising while leaving the normal StatScout+ plans intact.
- [ ] Write a short results note before designing the 2027 campaign.

## Final recommendation

The seasonal opportunity is real, but the value should be framed as **better
late-season scouting**, not as a speculative postseason-data feature. The app
already contains the right product: recent form, trends, head-to-head
comparisons, team scouting, and historical context. The safest real discount is
a time-boxed Apple offer code on the existing yearly product, configured for
new and expired subscribers, with the standard paywall and lifetime price
protected.

The one compromise is that an offer-code flow cannot display a universal,
inline discounted price as cleanly as a base-price change. That compromise is
worth accepting. Apple can show the exact localized offer and renewal terms,
while the app avoids giving every existing subscriber a price cut and avoids
hardcoded cross-storefront pricing. If the first pilot proves demand and
redemption reliability, a later lapsed-user promotional offer can provide a
smoother native purchase for that specific cohort.
