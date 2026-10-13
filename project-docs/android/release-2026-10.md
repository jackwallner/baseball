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
  history-loading instrumentation regression. Final regression results pending.
- Release lint, APK and AAB builds passed before the streaming correction.
  The corrected release is being rebuilt and revalidated.
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

The app displays localized Play prices and actual trial eligibility. Pending
and cancelled transactions do not grant access. Actual Play purchase and
restore verification are pending catalog activation and the internal release.

## Console staging

The app record is created. Privacy, ads, government, financial, health,
Sports category, contact email, website, listing text, and icon are saved.
Version code 1 was uploaded to an internal draft but will be replaced by the
memory-corrected version code 2 before rollout.

The existing RevenueCat service account was granted only Baseball app access:
read-only app information, automatically included quality information,
financial data, orders/subscriptions, store presence, and its automatically
included policy permission. No production release or administrator permission.

Reviewer instructions, content rating, target audience, Data Safety, artwork,
Play products, internal-track billing proof, pre-launch report, and production
staging are still being completed. Nothing has been submitted for production
review. The final Send for review action belongs to Jack.
