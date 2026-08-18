# StatScout 2026 Stretch Run Campaign

## Decision

Ship a seasonal **Stretch Run** campaign for the 2026 playoff chase, with a
real but controlled discount on the existing yearly StatScout+ subscription.
Use an Apple custom offer code for the first annual term, keep the normal
monthly, yearly, lifetime, and 7-day trial products intact, and sell the
campaign through the features that already exist in the app: Trends, recent
form, team scouting, player comparison, and historical context.

Do not add a postseason data product, a new seasonal SKU, or a lifetime sale in
the first version. Do not make team-specific playoff claims until the app has a
fresh, authoritative standings feed.

This is the best balance of urgency, real customer value, reversible economics,
App Store safety, and implementation scope.

## Executive recommendation

### Campaign concept

**Name:** StatScout+ Stretch Run

**Positioning:** The playoff picture is tightening. StatScout helps fans find
the players shaping the race before the postseason.

**Recommended merchandising window:** Launch as soon as the approved binary and
Apple offer are ready, ideally August 25 to August 31, 2026. Run through
October 5, 2026, covering the final regular-season push and the opening Wild
Card window. If the build is not ready by August 31, move the start and end
dates together. Never ship copy that says an offer is active when its Apple
offer is not active.

**Offer code:** STRETCH26

**Product:** Existing yearly subscription,
com.jackwallner.baseball.pro.yearly

**US price target:** $19.99 for the first annual term, then the standard yearly
price, currently planned in the repository as $29.99/year after the August 12
price raise. The exact price must be configured and confirmed in App Store
Connect, then shown through Apple's localized purchase and redemption surfaces.
Never hardcode $19.99 into the app for every storefront.

**Discount:** Approximately 33% off the planned $29.99 US annual price. This is
meaningful enough to create urgency without resetting the product's normal
price position.

**Renewal:** The customer sees the standard localized yearly renewal price after
the discounted term. The final terms shown by Apple are authoritative.

**Audience:** Free users who have never purchased, plus eligible former or
recent purchasers as allowed by the Apple offer configuration. Hide the
campaign from users who already have active StatScout+ or lifetime access.

**Primary CTA:** Claim the Stretch Run offer

The CTA opens Apple's offer-code redemption flow. The normal See all plans path
remains available and continues to use the existing RevenueCat purchase flow.

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
- Target Stretch Run yearly: $19.99, about 33% below the standard yearly price.
- Target Stretch Run monthly equivalent: about $1.67.
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
period for auto-renewable subscriptions, can be configured for never-purchased,
recently purchased, and older purchased customers, and can be redeemed through
the App Store, a redemption URL, or an in-app StoreKit sheet. See [Apple's
offer-code setup guide](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes)
and [Apple's StoreKit offer-code support](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).

Configure:

| Field | Recommendation |
|---|---|
| Product | Existing yearly StatScout+ SKU |
| Reference name | stretch-run-2026-yearly |
| Custom code | STRETCH26 |
| Offer type | Paid offer, one annual discounted term |
| US price target | $19.99, subject to a valid App Store price point |
| Eligibility | Start with all three Apple purchase-history cohorts; suppress in-app merchandising for active StatScout+ users |
| Redemption limit | Start conservatively, for example 10,000; increase only if demand justifies it |
| Expiration | October 5, 2026 at 11:59 p.m. Pacific Time |
| Local prices | Use Apple's comparable price calculation, then review high-volume storefronts manually |

The code is not a secret. It is a campaign identifier and discount key. A
redemption limit and expiration date make leakage bounded. A unique reference
name also makes offer-code sales attributable in App Store Connect and
RevenueCat.

### Redemption flow

Implement both paths:

1. **Primary in-app path:** present Apple's native offer-code redemption sheet
   from a Claim offer button.
2. **Fallback path:** provide a prefilled App Store redemption URL if the native
   sheet fails or is unavailable:
   https://apps.apple.com/redeem?ctx=offercodes&id=6763945657&code=STRETCH26
3. When the app returns to the foreground, refresh RevenueCat customer
   information using the existing path. Dismiss the seasonal sheet when
   isPro changes to true.
4. If Apple does not propagate the entitlement immediately, show a clear
   Refresh purchase status or Restore Purchases fallback. Do not report a
   failed purchase merely because RevenueCat is briefly pending.

RevenueCat documents the redemption sheet and App Store URL flow, but also
warns that the in-app sheet has had reliability issues. The fallback URL is
therefore part of the design, not an afterthought. Upload the required Apple
In-App Purchase key to RevenueCat so offer-code transactions are accurately
tracked. Do not place that key in the app.

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

For the US launch brief, the intended terms can say:

~~~text
$19.99 for your first year, then the standard yearly price. Exact price and
renewal terms vary by storefront and are shown by Apple before purchase.
~~~

Only show the $19.99 sentence when the copy is explicitly US-localized and the
ASC price has been verified. The safer default copy omits the number and lets
the native Apple sheet display the exact localized discounted price.

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
3. Claim the offer opens the Apple redemption sheet.
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
> nightly-updated Statcast rankings, recent form, comparisons, and team
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

## Implementation plan

### Phase 0: verify the commercial state

Before writing app code:

- Verify the live yearly, monthly, and lifetime prices in App Store Connect.
- Verify the current RevenueCat products and default offering.
- Verify the yearly subscription is approved and the app is Ready for
  Distribution, which Apple requires for production custom offer codes.
- Verify the existing 7-day introductory offer remains configured as intended.
- Upload the Apple In-App Purchase key to RevenueCat if it is not already
  present.
- Create a sandbox offer code and a production custom code only after the
  product state is confirmed.
- Record the exact offer price, duration, eligibility, expiration, storefronts,
  and redemption limit in the release checklist.

Do not alter the current monthly or yearly free-trial intro offers. The fleet
pricing guidance explicitly says to preserve them.

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
offer_code               text not null
offer_reference          text not null
headline                 text not null
body                     text not null
minimum_data_age_hours   integer not null default 48
~~~

The first row can be stretch-run-2026. The client must enforce all of these
rules:

- enabled is true.
- The current date is inside the start and end interval.
- The campaign season matches StatScoutSeason.current.
- The offer code equals an app-allowlisted value such as STRETCH26.
- Copy is plain text, not executable or HTML.
- Current player data is within the allowed age, using the existing
  DashboardViewModel.dataThrough coverage value where available.
- Missing, malformed, stale, or expired config fails closed to the ordinary
  paywall.
- A last-known-good config is cached for at most six hours.
- Remote config controls merchandising only. It must never grant Pro or alter
  entitlement state.

For a strictly one-off release, a compiled SeasonalCampaign value type with the
same date and allowlist checks is acceptable as a fallback. The remote flag is
better because an expired code, App Store mistake, or copy problem can be fixed
without a new binary.

Do not add standings_as_of to the V1 campaign unless the campaign actually
renders standings. If a future version adds team-specific claims, then add
standings_as_of, standings_source, and a separate standings freshness check.

### Phase 2: app changes

Recommended file-level changes:

1. Add SeasonalCampaign and a small campaign-fetching layer next to the existing
   services.
2. Add PaywallTrigger.stretchRun, icon, title, subtitle, feature copy, and
   statscout_paywall_stretch_run impression ID in PaywallView.swift.
3. Add a presentOfferCodeRedemption method to StoreService that calls the
   RevenueCat-supported Apple redemption sheet. Keep normal purchase and
   restore methods unchanged.
4. Add a fallback redemption URL for the App Store path.
5. Add a dedicated seasonal card or sheet. Do not overload the existing
   UpdateShowcaseCampaign identifier with two unrelated campaign meanings.
6. Add a one-time lastSeenSeasonalCampaign AppStorage decision, matching the
   pure decision-test pattern already used by UpdateShowcaseCampaign.
7. Keep the existing full plan picker and a clear See all plans route.
8. Suppress the offer for active Pro and lifetime users.
9. Refresh customer information on return from the redemption sheet and rely on
   the existing isPro observation to dismiss after successful entitlement sync.
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

## Measurement plan

Do not add a new analytics SDK for this campaign. The app currently has no
analytics or ad SDK and should preserve that privacy posture.

Use the following sources:

- RevenueCat custom paywall impression ID:
  statscout_paywall_stretch_run.
- RevenueCat offer-code transactions, after the Apple key is configured.
- App Store Connect Sales and Trends reports, segmented by offer code.
- Existing RevenueCat entitlement and renewal charts.
- Support messages and redemption-failure reports.

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

Use at least one pre-campaign window after the August price raise as the
baseline. A simple before-and-after read is acceptable for this first campaign.
A later experiment can add a stable holdout, but do not build a full
experimentation framework before validating that offer-code redemption works.

### Success thresholds

Set the thresholds before launch. A reasonable first-pass decision rule is:

- Keep the campaign if annual starts per eligible user increase materially over
  baseline and net revenue per eligible install does not fall.
- Keep it only if first-renewal and refund rates are not materially worse than
  the standard annual cohort.
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
- Active Pro and lifetime users do not see the acquisition offer.
- STRETCH26 is the only accepted offer code.
- Seasonal PaywallTrigger copy and impression ID are stable.
- Existing UpdateShowcaseCampaign behavior remains unchanged.
- The standard See all plans purchase path remains available.

### Store and device states

Test on a real sandbox or TestFlight build, not only a plain simulator launch:

- Never purchased, eligible for the normal trial.
- Never purchased, redeemed seasonal offer.
- Trial active, then offer-code attempt.
- Trial expired without paid conversion.
- Paid yearly subscriber.
- Lapsed yearly subscriber.
- Lifetime owner.
- Offer code invalid, expired, exhausted, or ineligible.
- User cancels the redemption sheet.
- User redeems through the App Store URL and returns to the app.
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
- Verify the seasonal text does not claim a specific team status.
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
| Offer appears after the postseason window | Medium | Medium | ASC expiry plus client dates plus remote kill switch and season check |
| Stale player data makes urgency claim look false | Medium | Medium | Use generic stretch-run copy and hide campaign on stale coverage |
| Existing trial is accidentally removed or hidden | Low | High | Preserve intro offers, keep normal plan cards, test trial eligibility |
| Lifetime cannibalizes annual | Medium | High | Do not discount lifetime, measure lifetime share, suppress offer for lifetime owners |
| A second annual SKU creates duplicate cards | Low | High | No new SKU in V1, use offer code on existing yearly product |
| App Review cannot discover or test the offer | Medium | High | Review notes, sandbox code, standard paywall fallback, stable in-app route |
| Remote config grants entitlement | Low | Critical | Remote config controls copy and merchandising only; RevenueCat remains authoritative |
| The campaign claims MLB affiliation | Low | High | Generic language, existing non-affiliation disclaimer, no MLB branding or guarantees |

## Rollout checklist

### Commercial setup

- [ ] Verify live ASC prices and yearly product approval.
- [ ] Verify RevenueCat default offering and entitlement mapping.
- [ ] Confirm planned annual baseline and target offer price.
- [ ] Create stretch-run-2026-yearly paid offer.
- [ ] Create sandbox code and test it.
- [ ] Create production custom code STRETCH26.
- [ ] Set redemption limit and October 5 expiration.
- [ ] Upload or verify the RevenueCat Apple In-App Purchase key.

### Product and code

- [ ] Add remote campaign row or safe compiled fallback.
- [ ] Add seasonal card/sheet and one-time dismissal.
- [ ] Add seasonal PaywallTrigger and impression ID.
- [ ] Add Apple redemption sheet and App Store URL fallback.
- [ ] Refresh customer info after returning to the app.
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

- [ ] Confirm offer-code transactions are attributed in RevenueCat and ASC.
- [ ] Check redemption failures daily during the first week.
- [ ] Check current player-data coverage and campaign config freshness.
- [ ] Review annual starts, trial conversion, lifetime share, and refunds.
- [ ] Disable the campaign after October 5 or earlier if the kill criteria fire.
- [ ] Remove seasonal merchandising while leaving the normal StatScout+ plans intact.
- [ ] Write a short results note before designing the 2027 campaign.

## Final recommendation

The seasonal opportunity is real, but the value should be framed as **better
late-season scouting**, not as a speculative postseason-data feature. The app
already contains the right product: recent form, trends, head-to-head
comparisons, team scouting, and historical context. The safest real discount is
a time-boxed Apple offer code on the existing yearly product, with the standard
paywall and lifetime price protected.

The one compromise is that an offer-code flow cannot display a universal,
inline discounted price as cleanly as a base-price change. That compromise is
worth accepting. Apple can show the exact localized offer and renewal terms,
while the app avoids giving every existing subscriber a price cut and avoids
hardcoded cross-storefront pricing. If the first pilot proves demand and
redemption reliability, a later lapsed-user promotional offer can provide a
smoother native purchase for that specific cohort.
