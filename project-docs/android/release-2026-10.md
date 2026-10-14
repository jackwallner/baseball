# First Android release

Package: `com.jackwallner.baseball`. Play Console app: `4974521223452573673`.
Version name: `1.5.3`. Publisher: E3 Apps.

## Implementation

Kotlin and Jetpack Compose port using Football's Android foundation and
StatScout's iOS data models, copy, fonts, icon, and navy/red palette. Four tabs
cover Stats, Trends, Teams, and Compare. Current-season scouting and following
are free. StatScout+ unlocks past seasons, recent form, full Trends, player and
team comparisons, and year-over-year views.

Regular and postseason queries use separate tables. Historical coverage
contains all 14,032 iOS player-season rows for 2015 through 2025. The archive
streams one player-season at a time to stay within a 192 MB Android heap.

## Verification

- Local unit and live-feed tests: 18 passed.
- Live Supabase feed: 1,317 current players, 950 rolling-form rows,
  and 275 postseason players at verification.
- MacBook Pro API 36 emulator: four original Debug and four QA flows passed.
- Extended manual testing exposed a history-loading memory crash after those
  short tests. Version code 2 streams the history archive and adds a complete
  history-loading instrumentation regression.
- Version code 3 (2026-10-13): Teams lists only the 30 clubs (a stray `TBD`
  group ranked first), screens show a spinner instead of an empty state while
  the cache loads, Trends hides "Through Not available" before data arrives,
  and comparisons show the percentile alone when the feed omits a raw value.
- Version code 3 on the Pro API 36 emulator: Debug connected 5/5, QA connected
  5/5 (v2 code), unit tests 18/18, release lint has no errors, AAB signed with
  the upload key.
- Upload key is external to the repository with an encrypted PKCS12 backup.
  Production credentials and signing material were not copied to Pro.

## Billing

RevenueCat project `proje8aeddd9`, Google Play app `app94f43f7fc0`, entitlement
`Baseball Savvy StatScout Pro`, Android offering `android`.
The existing iOS default offering is preserved.

Planned US prices, approximately 20% below current iOS:

| Product | Base plan | US price | Trial |
| --- | --- | --- | --- |
| `com.jackwallner.baseball.pro.monthly` | `monthly` | $2.49/month | 7 days, eligible accounts |
| `com.jackwallner.baseball.pro.yearly` | `yearly` | $7.99/year | 7 days, eligible accounts |
| `com.jackwallner.baseball.pro` | One-time | $15.99 | None |

All three Play products were created and activated on 2026-10-13 at these
prices, with Play's converted local prices. The trial offer `free-trial-7d`
targets accounts that never had any subscription in the app. RevenueCat's
`android` offering maps `$rc_monthly`, `$rc_annual` and `$rc_lifetime` to the
Play products.

The app displays localized Play prices and actual trial eligibility. Pending
and cancelled transactions do not grant access. Purchase and restore
verification needs a licence tester. The service account JSON was attached to
the RevenueCat Play app on 2026-10-13 through API v2, and RevenueCat now reads
both subscriptions' Play store state.

Licence-tester run, verified 2026-10-13 (passed):

- Play Console **Settings > License testing** selects the "IM Iron Splits
  internal testers" list (1 user, `RESPOND_NORMALLY`). That user is the Google
  account on the Pro Play AVD `small_phone`, which joined the internal test
  through the Testers page opt-in link. Play shows the temporary name
  `com.jackwallner.baseball (unreviewed)` until the app is reviewed.
- StatScout 1.5.3 (versionCode 3) installed from the Play test listing
  (installer `com.android.vending`). Free state showed 3 Trends rows, then the
  StatScout+ lock card.
- Paywall Yearly ($7.99/year, 7-Day Free Trial) opened Google Play with "Test
  card, always approves" and "This is a test subscription ... You will not be
  charged." Play's test schedule is a 3-minute trial, then renewals every 30
  minutes. No fingerprint prompt appeared.
- After Subscribe the app showed the PRO badge, Trends scrolled past 3 rows
  with no lock, and the 2025 season loaded.
- RevenueCat (API v2): active entitlement `Baseball Savvy StatScout Pro`;
  subscription to `com.jackwallner.baseball.pro.yearly:yearly`, store
  `play_store`, environment `sandbox`, status `trialing`, `gives_access` true,
  `will_renew`, no pending payment.
- Settings > Restore Purchases showed "StatScout+ restored." Access persisted
  after a force-stop and relaunch (PRO badge, 2025 season).
- `small_phone` has a PIN lock and cold-boots (no valid snapshot), so Jack
  unlocks it before an agent billing run. This test account now owns the
  yearly test subscription; use Restore rather than buying again.

## Console staging

The app record is created. Privacy, ads, government, financial, health,
Sports category, contact email, website, listing text, and icon are saved.
Version code 1 was uploaded to an internal draft but will be replaced by the
memory-corrected version code 2 before rollout.

The existing RevenueCat service account was granted only Baseball app access:
read-only app information, automatically included quality information,
financial data, orders/subscriptions, store presence, and its automatically
included policy permission. No production release or administrator permission.

Completed on 2026-10-13: version code 3 rolled out to internal testing,
Data safety (purchase history, app interactions and device IDs collected via
RevenueCat, encrypted in transit, deletion by email, nothing shared), target
audience 13 and over, six listing screenshots and the feature graphic.
Publishing overview lists these as changes not yet sent for review.

Remaining: add a licence tester and
run the no-charge purchase and restore test (done), then create the production
release. The pre-launch report cannot be checked first: Play does not run it
for internal-only builds, so it appears after a closed or production release
is sent for review. The final Send for review action belongs to
Jack.
