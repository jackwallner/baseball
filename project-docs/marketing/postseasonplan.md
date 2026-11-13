# StatScout Pennant Race promo — postseason as a StatScout+ benefit

## Context

StatScout's demand peaks Aug–Oct and dies in the offseason. Jack wants a
seasonal push. The original idea was a winback discount, but two research
findings killed that and pointed at a simpler play:

1. **There is no discount room.** Live ASC prices are Monthly $1.99 / Yearly
   $4.99 / Lifetime $9.99. Yearly works out to **$0.42/month**. A "$1.99 for 3
   months" pass is $0.66/month — 59% *more* per month than the yearly. Any
   short-term SKU is a worse rate, not a deal.
2. **Apple can't reach the target audience anyway.** Promotional and win-back
   offers are restricted to existing/former *subscribers*. Users who declined
   on day one and never started a trial are ineligible for everything except a
   one-per-group intro offer (already spent on the 7-day trial) or an offer
   code.

So: no new SKU, no new plan, no offer plumbing. Ship postseason data as a
StatScout+ benefit and promote it. Existing subscribers gain a feature and
nobody's price moves.

---

## The enabling finding

`backend/ingest_game_logs.py:563` calls `pybaseball.statcast(start_dt, end_dt)`
with no game-type filter, across `SEASON_START = 2026-03-20` → `SEASON_END =
2026-11-05` (`:37-38`). pybaseball's default Savant query is `hfGT=R|PO|S|` —
**regular season, postseason, and spring training**.

Two consequences:

- **Latent bug that fires this October.** Postseason games will silently merge
  into `player_game_logs` and therefore into Recent Form / trend windows,
  presenting playoff plate appearances as regular-season form. The module
  docstring at `:253` claims game logs "stay season-only"; they don't.
- **The feature is nearly free.** The postseason pitch data is already being
  pulled. Splitting it out needs a `game_type` column (already in the Statcast
  dataframe), a migration, and a filter.

**Percentiles are the exception.** `backend/ingest.py` sources percentiles by
scraping Savant leaderboard CSVs (`SAVANT_LEADERBOARD_URL:214`), and Savant
publishes percentile ranks for the regular season only. Combined with tiny
postseason samples (~60–80 PA for a deep run) and the standing "match Savant
exactly" rule, **postseason ships without percentile bars** — raw Statcast plus
the traditional line, ranked within the playoff field, clearly labelled as
StatScout's own cut.

---

## Plan

### 1. Fix the leak (do this first, it's a live bug)

- Add `game_type` to the rows written in `backend/ingest_game_logs.py`
  (`:407`, `:497`) — the column is already present in the Statcast dataframe.
- New migration alongside
  `supabase/migrations/20260519000000_create_player_game_logs.sql`; apply with
  `supabase db push`.
- Backfill: `python backend/ingest_game_logs.py --full`.
- Filter `backend/rollup_recent_form.py` to `game_type == 'R'` so Recent Form
  stays regular-season-only.
- Correct the stale docstring at `ingest_game_logs.py:253`.

### 2. Postseason data

- **Standard line:** the hydrate calls in `backend/ingest.py:1345-1400,1453`
  use `stats(type=season,season=…,group=…)`. Add a parallel call with
  `gameType=P` for the postseason line.
- **Statcast line:** aggregate the postseason rows already landing in
  `player_game_logs`.

### 3. App surface (StatScout+ gated)

- Postseason toggle on Player Profile, and a postseason leaderboard.
- Raw Statcast + traditional stats, ranked within the playoff field. No
  percentile bars.
- Gate with the existing entitlement path — `StoreService.isPro` /
  `CustomerInfo.hasProEntitlement`
  (`StatScout/Services/StoreService.swift:212-231`). Nothing new in the store
  layer.
- Follow the existing season-gating pattern in
  `StatScout/ViewModels/DashboardViewModel.swift` (`isSeasonLocked:110`) rather
  than inventing a second gate.
- Native SwiftUI `Menu` for the regular/postseason switch, per the
  native-pickers-only rule.

### 4. Promote it

- **App Store promotional text** — `fastlane/metadata/en-US/promotional_text.txt`
  is editable in ASC without a build submission. Seasonal headline goes here.
- **In-app campaign:** reuse `UpdateShowcaseCampaign`
  (`StatScout/Views/UpdateShowcaseView.swift:8-36`) — it already has a string
  identifier, an AppStorage key, a pure `decision(...)` function, and a
  `STATSCOUT_FORCE_UPDATE_SHOWCASE` debug override. Add a
  `"pennant-race-2026"` identifier to announce postseason to existing users and
  pitch it to free users.
- **Paywall copy:** add a `PaywallTrigger.postseason` case with its own copy and
  `statscout_paywall_*` impression id (`StatScout/Views/PaywallView.swift:99-115`).
  Copy only — the CTA still buys the existing yearly at the existing price via
  `purchaseYearlyDirect()` (`StoreService.swift:499-516`). Nothing to change in
  the purchase path.
- **Screenshots / release notes** for the update.

---

## Constraints carried from existing conventions

- Don't touch the monthly/yearly `FREE_TRIAL` intro offers (ios-dev hard rule).
- Premium tier is user-facing **"StatScout+"**, never "Pro"; don't rename
  RevenueCat product/entitlement IDs.
- Keep the simulator early-return in `configureIfNeeded()`
  (`StoreService.swift:570-585`).
- No feature branches: commit to `main`, push, then
  `source ~/.baseball_credentials && bash scripts/testflight.sh`.
- Rerun `xcodegen generate` after adding any `.swift` file.

## Verification

- **Pipeline:** run `python backend/ingest_game_logs.py --full` against 2025
  (which has a completed postseason), assert postseason rows carry
  `game_type != 'R'`, and assert they are excluded from `player_recent_form`.
- **Regression:** confirm Recent Form numbers for a 2025 playoff participant
  are unchanged by the postseason rows.
- **Backend tests:** `PYTHONPATH=backend python -m pytest backend/tests`.
- **App:** build and test against the `agent-baseball` headless simulator; use
  `STATSCOUT_FORCE_PRO=1` to exercise the gated postseason surfaces, since
  RevenueCat is never configured on sim.
- **Paywall copy:** extend `StatScoutTests/UpgradeCTATests.swift` (note its ≤12
  character assertion on the toolbar pill) for the new trigger.
- **End-to-end:** `scripts/testflight.sh`, verify postseason surfaces on device.

## Open decision

Postseason ships without percentile bars, which makes it the only surface in a
percentile-first app that isn't percentile-first. Confirm that's acceptable —
the alternative is StatScout computing its own postseason percentiles, which
would break the "match Savant exactly" rule and be statistically junk at
60–80 PA.

---

## Appendix — Apple offer research (why no discount is in this plan)

Apple gates discounts by subscription history. Eligibility by audience:

| Audience | Intro offer | Promotional offer | Win-back offer | Offer code |
|---|---|---|---|---|
| Never subscribed, never trialled | ✅ (one per group, ever) | ❌ | ❌ | ✅ |
| Currently inside the 7-day trial | already consumed | ✅ | ❌ | ✅ |
| Trial started, expired, never paid | ❌ (burned) | ✅ *(verify in sandbox)* | ❌ | ✅ |
| Paid, then cancelled | ❌ | ✅ | ✅ | ✅ |

- Apple's wording for promotional offers: *"giving existing or former
  subscribers a free or discounted subscription for a specific duration."* A
  user inside a free trial **is** an existing subscriber — that's the mechanic
  behind "lock in a cheaper yearly halfway through your trial." It's a
  promotional offer, not a win-back offer.
- Win-back offers (iOS 18+) are paid-then-cancelled only. They cannot reach
  trial-lapsed or never-subscribed users.
- Promotional offers: up to 10 per subscription, require server-side signing.
  RevenueCat can sign, but the ASC subscription key `.p8` must first be
  uploaded to the RevenueCat dashboard.
- Offer codes: reusable custom codes (e.g. `PENNANT26`) redeemable in-app via
  `presentCodeRedemptionSheet()`; eligibility is configurable and *can* include
  never-purchased users. The only Apple discount mechanism reaching every
  audience. Downside: reusable codes leak to deal sites.
- Legacy promo codes are removed by Apple on **2026-03-26**; offer codes are
  the replacement. Don't build on promo codes.

Current ASC state (group `STATSCOUT+`, id 22079676): both subs carry a 1-week
`FREE_TRIAL` intro offer started 2026-07-09 with no end date. **No** promotional
offers, win-back offers, or offer codes exist on either product today.

If a discount is ever wanted later, the two viable levers are a promotional
offer on the yearly (reaches mid-trial and lapsed users) and a custom offer code
(reaches everyone). Neither is in scope here.
