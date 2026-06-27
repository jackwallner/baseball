# Astro ASO setup — Baseball Savvy StatScout

> Playbook: [`astro-global-aso-go-2026.md`](astro-global-aso-go-2026.md) · say **"go"** to re-run.

Last **go** run: **2026-05-26**

## App

| Field | Value |
|-------|-------|
| App Store name | Baseball Savvy StatScout |
| Astro app ID | `6763945657` |
| Bundle ID | `com.jackwallner.baseball` |
| Draft ASC version | **1.1.0** |
| Live ASC version | **1.0** |

## Current draft metadata (en-US)

| Field | Value |
|-------|-------|
| **Name** | Baseball Savvy StatScout |
| **Subtitle** | MLB Statcast Percentiles |
| **Keywords** | `savant,wrc,xwoba,oaa,barrel,sprint,velo,sports,strike,wrcplus,dfs,fantasy,metrics,leaderboard` |

Keywords intentionally **omit** `mlb`, `statcast`, `scout`, `percentile` — those are indexed via subtitle/name (dedupe pass).

## US Astro strategy

- **Defend:** branded terms (`statscout`, `baseball savvy statscout`), **oaa** (#14), savant-adjacent phrases  
- **Push:** `mlb`, `statcast`, `savant`, `percentile` via subtitle + long-tail Astro phrases  
- **Astro phrases:** `scripts/astro-keywords-us.json` + sync from fastlane  

## Commands

```bash
# Re-optimize ranks (after 7–14 days live)
./scripts/astro-optimize.sh

# Full global go
python3 scripts/aso-apply-locale-optimizations.py
./scripts/astro-sync-all-stores.sh
./scripts/astro-prune-all-stores.sh
python3 scripts/astro-tier1-second-pass.py
./scripts/asc-finish-missed.sh
```

## ASC experiment (shipped on draft 1.1.0)

- Subtitle: `Percentile Rankings & Stats` → **MLB Statcast Percentiles**  
- Keywords: pop/diff pack + **name/subtitle dedupe**  
- **50 locales** on draft via API + deliver 2.234  

Backups: see [`localization-aso.md`](localization-aso.md).
