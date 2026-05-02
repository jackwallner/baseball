# Pybaseball Data Source Comparison for Savant-Style Display

## Summary

This document tracks which stats have **actual values** vs. **percentiles only** in pybaseball.

---

## Current Coverage (Post-Backfill)

| Stat | Actual Value Source | Example | Status |
|------|---------------------|---------|--------|
| **xwOBA** | `statcast_*_expected_stats` | 0.344 | ✅ Available |
| **xBA** | `statcast_*_expected_stats` | 0.269 | ✅ Available |
| **xSLG** | `statcast_*_expected_stats` | 0.479 | ✅ Available |
| **xERA** | `statcast_pitcher_expected_stats` | 4.04 | ✅ Available |
| **Exit Velocity** | `statcast_*_exitvelo_barrels` | 91.8 mph | ✅ Available |
| **Barrel%** | `statcast_*_exitvelo_barrels` | 9.8% | ✅ Available |
| **Hard-Hit%** | `statcast_*_exitvelo_barrels` | 37.2% | ✅ Available |
| **Max EV** | `statcast_*_exitvelo_barrels` | 113.2 mph | ✅ Available |
| **Sprint Speed** | `statcast_sprint_speed` | 29.2 ft/s | ✅ Available |
| **OAA** | `statcast_outs_above_average` | +11 | ✅ Available |
| **Fastball Velo** | `statcast_pitcher_pitch_arsenal` | 95.0 mph | ✅ Available |
| **K%** | Calculated from MLB Stats API | 21.4% | ✅ Available |
| **BB%** | Calculated from MLB Stats API | 6.2% | ✅ Available |
| **Whiff%** | Play-by-play only | - | ❌ Percentile only |
| **Chase%** | Play-by-play only | - | ❌ Percentile only |
| **Bat Speed** | No aggregated source | - | ❌ Percentile only |
| **Swing Length** | No aggregated source | - | ❌ Percentile only |
| **FB Spin** | No aggregated source | - | ❌ Percentile only |
| **Curve Spin** | No aggregated source | - | ❌ Percentile only |

---

## Validation: Julio Rodríguez (2025)

```
ACTUAL VALUES WITH PERCENTILES:
  xwOBA:     0.344  (76th percentile)
  xSLG:      0.479  (81st percentile)
  xBA:       0.269  (80th percentile)
  Exit Velo: 91.8 mph (87th percentile)
  Barrel%:   9.8%   (58th percentile)
  Sprint:    29.2 ft/s (93rd percentile)
  OAA:       +11    (97th percentile)
  K%:        ~21%   (50th percentile)
  BB%:       ~6%    (24th percentile)

PERCENTILE-ONLY:
  Whiff%:    (26th percentile) - no actual value source
  Chase%:    (10th percentile) - no actual value source
  Bat Speed: (percentile only) - no aggregated source
```

---

## Validation: Luis Castillo (2025)

```
ACTUAL VALUES WITH PERCENTILES:
  xERA:      4.04   (45th percentile)
  xwOBA:     0.312  (45th percentile)
  xBA:       0.245  (41st percentile)
  xSLG:      0.418  (33rd percentile)
  Exit Velo: 90.3 mph (22nd percentile)
  Barrel%:   10.4%  (17th percentile)
  FB Velo:   95.0 mph (60th percentile)
  K%:        ~22%   (43rd percentile)
  BB%:       ~9%    (28th percentile)

PERCENTILE-ONLY:
  Whiff%, Chase%, FB Spin, Curve Spin
```

---

## Why Some Stats Are Percentile-Only

### Whiff% / Chase% / Plate Discipline
- **Source needed:** Play-by-play pitch data (`statcast_batter` / `statcast_pitcher`)
- **Problem:** Returns ~2900 rows per player (one per pitch)
- **To calculate:** Would need to:
  1. Fetch 2900+ rows × 835 players = **2.4+ million rows**
  2. Parse every pitch's zone and description
  3. Calculate rates per player
  4. Runtime: **hours** instead of minutes
- **Trade-off:** Too slow for nightly ingestion

### Bat Speed / Swing Length
- **Source needed:** Tracking data (newer Statcast metrics)
- **Problem:** Only available via percentile ranks endpoint
- **No aggregated source** in pybaseball

### Spin Rates
- **Source needed:** `statcast_pitcher_pitch_arsenal` or similar
- **Problem:** pybaseball only returns velocities, not spin rates
- **MLB Savant:** Has this data but not exposed in pybaseball

---

## Implementation Details

### Data Flow

```
1. Fetch percentile rankings (batter/pitcher) - fast
2. Prefetch actual values:
   - Expected stats (one call each for batters/pitchers)
   - Exit velo/barrels (one call each)
   - Sprint speed (one call)
   - OAA (one call)
   - Pitch arsenal (one call)
3. Fetch standard stats from MLB Stats API (batched)
4. Calculate K%/BB% from counting stats
5. Merge and upsert to database
```

### Key Files

- `backend/ingest_v2.py` - Main ingestion script
- `backend/savant_mapping.py` - Mapping of stats to data sources
- `.github/workflows/nightly-statcast.yml` - Automated nightly refresh

---

## Summary

**✅ 13 stats** now have actual values with percentiles
**❌ 6 stats** remain percentile-only (would require play-by-play processing or unavailable data)

The enhanced backend successfully displays data in Baseball Savant format: **"91.8 mph · 87th percentile"**
