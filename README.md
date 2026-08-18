# StatScout

StatScout is a native SwiftUI iOS app for fans and media to view mobile-friendly player percentile pages from a nightly refreshed advanced-metrics data feed.

## Stack

- **iOS app:** SwiftUI, iOS 17+
- **Project generation:** XcodeGen
- **Database/API:** Supabase Postgres + generated REST API
- **Nightly refresh:** GitHub Actions scheduled Python job
- **Ingestion:** Python + `pybaseball` percentile rankings

## Project layout

```text
StatScout/                  SwiftUI source
backend/                    Nightly ingestion job
supabase/schema.sql         Supabase database schema and RLS policy
.github/workflows/          Scheduled refresh workflow
project.yml                 XcodeGen project definition
```

## Run the iOS app

1. Install XcodeGen if needed:

   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:

   ```bash
   xcodegen generate
   ```

3. Open `StatScout.xcodeproj` in Xcode.

4. Run the `StatScout` scheme on an iPhone simulator.

The app loads real data through `StatcastAPI` using Supabase REST. Previews and unit tests use `PreviewStatcastAPI` with sample data. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as build settings or in `Info.plist` variables.

## Set up Supabase

1. Create a free Supabase project.
2. Open the SQL editor.
3. Run `supabase/schema.sql`.
4. Copy your project URL, anon key, and service role key.

The table is `public.player_snapshots`. Public read access is enabled through RLS for app consumption. Writes should use only the service role key from GitHub Actions secrets.

## Configure GitHub Actions

Add these repository secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY` (used by iOS build; rotate the old key immediately if it was ever committed)

Optional repository variable:

- `STATCAST_SEASON`

## Apple Retention Messaging

Baseball's Retention Messaging endpoint is a Supabase Edge Function at
`supabase/functions/apple-retention-message`. It does not use the database or
RevenueCat at request time, so it can respond within Apple's 700 ms limit.

The function verifies Apple's signed request, selects a message by product, and
returns the approved message identifier. Supabase JWT verification is disabled
for this function because Apple calls it directly.

Deploy it with:

```bash
supabase functions deploy apple-retention-message --no-verify-jwt
supabase secrets set \
  APPLE_RETENTION_MESSAGE_ID_YEARLY=011d8acb-3ea0-5c98-bdd4-6d72ab531072 \
  APPLE_RETENTION_MESSAGE_ID_MONTHLY=252b8604-d259-5318-a6f2-dcce30824529 \
  APPLE_RETENTION_MESSAGE_ID_DEFAULT=011d8acb-3ea0-5c98-bdd4-6d72ab531072
```

The Apple setup script uploads the sandbox messages, configures the English
fallbacks, and registers the deployed URL:

```bash
python3 scripts/apple-retention-messaging.py setup-sandbox \
  --endpoint-url https://babzqsbmcunrezsdpyng.supabase.co/functions/v1/apple-retention-message
```

Apple's Retention Messaging access must be enabled for the app before those
StoreKit API calls succeed. The script uses the In-App Purchase JWT credentials
from `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, and `APPLE_IAP_KEY_PATH`, with
the existing `ASC_*` values as a local fallback.

The workflow runs daily at `14:00 UTC` (10:00 EDT) and can also be run manually from GitHub Actions.

## Next production steps

- Add team/position enrichment to the percentile snapshot rows.
- Add dedicated player search/profile navigation around percentile cards.
- Add cached local persistence in the iOS app.
- Add push alerts for major percentile movers.
- Add share cards for media-friendly player insights.
