# Baseball Project Guide

StatScout: Statcast percentiles / player-comparison app (iOS). XcodeGen
project/scheme: `StatScout`, sim lease owner `baseball`.

**This repo is the fastlane template for the other iOS apps.** Keep `Appfile`,
`metadata/en-US/`, `screenshots/en-US/`, and `Fastfile` review info canonical
here and copy outward.

**App Store reviews:** enjoyment funnel in `StatScout/Services/ReviewPromptTracker.swift`
(passive triggers: 3rd+ player profile open, Pro player comparison). App Store
ID `6763945657`; feedback `jackwallner+bb@gmail.com`.

## Backend / data pipeline (Statcast)

Unlike the other apps, StatScout is backed by a Supabase Statcast dataset fed by a nightly pipeline.

- **Supabase migrations**: in `supabase/migrations/`, applied after any schema change. Check CLI (`which supabase`), link (`supabase link --project-ref <ref>`, ref is in `SUPABASE_URL`), then `supabase db push`.
- **Data refresh workflows**: `.github/workflows/nightly-statcast.yml`, driven by a self-booked timer chain (`refresh-timer.yml`, slots in `backend/refresh_slots.py`) since 2026-10-12; the crons are only a backup. Manual `gh workflow run nightly-statcast.yml` forces the steps; `-f planned=true` lets the guard decide (that is also how to restart a broken chain). Watch with `gh run watch <run-id>`. Staleness alerts come from the stat watchdog in the football repo.
- **Env vars**: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (GitHub secrets), `STATCAST_SEASON` (optional, defaults to current season). App reads `SUPABASE_URL` + `SUPABASE_ANON_KEY` from `~/.baseball_credentials` (Supabase project is `babzqsbmcunrezsdpyng` as of 2026-05-03). Refresh the ANON_KEY there if it rotates.
- **Game types / phases**: `pybaseball.statcast()` requests `hfGT=R|PO|S`, so every date-range pull carries spring training and the postseason too. Spring is dropped; the postseason is written to `player_postseason_game_logs`, never to `player_game_logs`. That split is load bearing: shipped builds query `player_game_logs` with no phase filter of their own, so a playoff row there lands inside a regular-season "last 7 days". `STATCAST_GAME_TYPES` overrides the collected set for one-off runs. Savant publishes no postseason percentile leaderboards, so `rollup_postseason_percentiles.py` places October values on the regular-season curve; the app ranks postseason boards only above MLB's qualifier (3.1 PA / 1 IP per team game, `PostseasonQualifier.swift`).
- **Common issues**: Use MLB Stats API when FanGraphs blocks cloud IPs (403). Supabase upsert needs the composite PK on `(id, season)` (migration `20260502000000_ensure_composite_pk.sql`). Node 20 deprecation handled via `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`.
- **TestFlight upload** sources the creds first: `source ~/.baseball_credentials && bash scripts/testflight.sh`.

---
Shared iOS conventions (build, simulator, release scripts, ASC key, review funnel, signing, gotchas):
the global agent rules + the `ios-dev` skill.
