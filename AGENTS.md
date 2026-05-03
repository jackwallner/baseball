# Project Notes for Devin

## Supabase Migrations

When migrations need to be applied to the remote Supabase database:

1. Check Supabase CLI is installed: `which supabase`
2. Ensure project is linked: `supabase link --project-ref <ref>` (ref is in SUPABASE_URL)
3. Push migrations: `supabase db push`

Migrations are in `supabase/migrations/` and should be applied after any schema changes.

## Workflow Triggers

- Nightly refresh: `.github/workflows/nightly-statcast.yml`
- Manual trigger: `gh workflow run nightly-statcast.yml`
- Watch run: `gh run watch <run-id>`

## Key Environment Variables

- `SUPABASE_URL` - From GitHub secrets/vars
- `SUPABASE_SERVICE_ROLE_KEY` - From GitHub secrets
- `STATCAST_SEASON` - Optional, defaults to current season logic

## Common Issues

- FanGraphs blocks cloud IPs (403) - disabled in favor of MLB Stats API
- Supabase composite PK on `(id, season)` required for upsert - migration: `20260502000000_ensure_composite_pk.sql`
- Node.js 20 deprecation warning - handled by `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`

## Build & TestFlight Upload

Credentials are stored in `~/.baseball_credentials`:
- SUPABASE_URL: https://babzqsbmcunrezsdpyng.supabase.co (updated May 3, 2026)
- SUPABASE_ANON_KEY: [see ~/.baseball_credentials - get from Supabase dashboard]

**Note**: The Supabase project was changed on April 28, 2026. The new project is `babzqsbmcunrezsdpyng`. 
You must update your `~/.baseball_credentials` file with the new ANON_KEY from the Supabase dashboard.

To upload to TestFlight:
```bash
source ~/.baseball_credentials && bash scripts/testflight.sh
```
