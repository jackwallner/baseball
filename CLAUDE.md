# Baseball — Project Guide

StatScout: Statcast percentiles / player-comparison app (iOS). XcodeGen
project/scheme: `StatScout`, simulator device `agent-baseball`.

**This repo is the fastlane template for the other iOS apps** — keep `Appfile`,
`metadata/en-US/`, `screenshots/en-US/`, and `Fastfile` review info canonical
here and copy outward.

**App Store reviews:** enjoyment funnel in `StatScout/Services/ReviewPromptTracker.swift`
(passive triggers: 3rd+ player profile open, Pro player comparison). App Store
ID `6743780853`; feedback `jackwallner+bb@gmail.com`.

## Backend / data pipeline (Statcast)

Unlike the other apps, StatScout is backed by a Supabase Statcast dataset fed by a nightly pipeline.

- **Supabase migrations**: in `supabase/migrations/`, applied after any schema change. Check CLI (`which supabase`), link (`supabase link --project-ref <ref>`, ref is in `SUPABASE_URL`), then `supabase db push`.
- **Data refresh workflows**: nightly `.github/workflows/nightly-statcast.yml`; manual `gh workflow run nightly-statcast.yml`; watch with `gh run watch <run-id>`.
- **Env vars**: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (GitHub secrets), `STATCAST_SEASON` (optional, defaults to current season). App reads `SUPABASE_URL` + `SUPABASE_ANON_KEY` from `~/.baseball_credentials` (Supabase project is `babzqsbmcunrezsdpyng` as of 2026-05-03 — refresh the ANON_KEY there if it rotates).
- **Common issues**: FanGraphs blocks cloud IPs (403) — using MLB Stats API instead. Supabase upsert needs the composite PK on `(id, season)` (migration `20260502000000_ensure_composite_pk.sql`). Node 20 deprecation handled via `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`.
- **TestFlight upload** sources the creds first: `source ~/.baseball_credentials && bash scripts/testflight.sh`.

---
Shared iOS conventions (build, simulator, release scripts, ASC key, review funnel, signing, gotchas):
always-loaded global CLAUDE.md + the `ios-dev` skill.
