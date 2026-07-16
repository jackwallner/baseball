# Astro Phase B report — StatScout go (2026-05-26)

## Summary

| Item | Result |
|------|--------|
| ASC draft version | **1.1.0** (`PREPARE_FOR_SUBMISSION`) |
| Live version | **1.0** (`READY_FOR_SALE`) |
| Locales optimized (fastlane) | **50** |
| Char limits | All `name`/`subtitle` ≤30, `keywords` ≤100 ✓ |
| ASC upload (`asc-finish-missed.sh`) | **Success** — deliver finished successfully |
| Astro app ID | `6763945657` |
| Astro 91-store sync | See `scripts/astro-pipeline.log` / `_summary.json` |

## en-US before → after

| Field | Before | After (chars) |
|-------|--------|---------------|
| Name | Baseball Savvy StatScout | Baseball Savvy StatScout (24) |
| Subtitle | Percentile Rankings & Stats | **MLB Statcast Percentiles** (24) |
| Keywords | `sabermetric,analytic,scout,sports,statcast,velo,wRC,strike,statistic,savant,barrel,sprint,OAA,expect` (100) | `savant,wrc,xwoba,oaa,barrel,sprint,velo,sports,strike,wrcplus,dfs,fantasy,metrics,leaderboard` (94) |

**Dedupe note:** `mlb`, `statcast`, `percentile`, and `scout` moved to subtitle/name indexing — removed from keywords per ASC ASO Assist.

## Subtitle changes (selected)

| Locale | New subtitle |
|--------|----------------|
| en-* | MLB Statcast Percentiles |
| de-DE | MLB Statcast Perzentile |
| fr-* / es-* | Percentiles MLB Statcast |
| ja | MLBスタットキャスト順位 |
| ko | MLB 스탯캐스트 백분위 |
| zh-Hans/Hant | MLB Statcast百分位 |

Full per-locale keywords: `scripts/aso-locale-optimization-report.json`

## Upload log

- Command: `./scripts/asc-finish-missed.sh`
- fastlane: **2.234.0** via `scripts/fastlane-bin.sh`
- Deliver: all 50 `Deliverfile` languages uploaded to draft **1.1.0**
- Screenshots: skipped (`SKIP_SCREENSHOTS=true`)

## Astro pipeline

After ASC upload:

1. `astro-sync-all-stores.py` — 91 Search Ads countries  
2. `astro-prune-all-stores.sh` — junk / wrong-language removal  
3. `astro-tier1-second-pass.py` — suggestions on tier-1 stores  

Log: `scripts/astro-pipeline.log`  
Store payloads: `scripts/astro-keywords-by-store/`

## Next steps

1. Attach a **1.1.0** build in App Store Connect and submit for review.  
2. **go refine** in 14 days: re-pull draft/live → tune from Astro ranks → `asc-finish-missed.sh`.
