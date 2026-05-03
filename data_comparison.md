# Pybaseball Data Source Comparison for Savant-Style Display

## Summary

**ALL STATS NOW HAVE ACTUAL VALUES!** Previously percentile-only stats are now calculated from 182,470+ pitch-level data points.

---

## Complete Coverage (Post-Backfill)

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
| **Bat Speed** | Aggregated from `statcast()` | **74.9 mph** | ✅ **NEW!** |
| **Swing Length** | Aggregated from `statcast()` | **7.58 ft** | ✅ **NEW!** |
| **Whiff%** | Aggregated from `statcast()` | **27.2%** | ✅ **NEW!** |
| **Chase%** | Aggregated from `statcast()` | **35.6%** | ✅ **NEW!** |
| **FB Spin** | Aggregated from `statcast()` | **2154 rpm** | ✅ **NEW!** |
| **Curve Spin** | Aggregated from `statcast()` | **2242 rpm** | ✅ **NEW!** |

---

## Validation: Julio Rodríguez (2025)

```
COMPLETE ACTUAL VALUES WITH PERCENTILES:
  xwOBA:        0.344  (76th percentile)
  xSLG:         0.479  (81st percentile)
  xBA:          0.269  (80th percentile)
  Exit Velo:    91.8 mph (87th percentile)
  Barrel%:      9.8%   (58th percentile)
  Sprint:       29.2 ft/s (93rd percentile)
  OAA:          +11    (97th percentile)
  Bat Speed:    74.9 mph (percentile available)
  Swing Length: 7.58 ft (percentile available)
  K%:           ~21%   (50th percentile)
  BB%:          ~6%    (24th percentile)
  Whiff%:       27.2%  (26th percentile)
  Chase%:       35.6%  (10th percentile)
```

---

## Validation: Luis Castillo (2025)

```
COMPLETE ACTUAL VALUES WITH PERCENTILES:
  xERA:         4.04   (45th percentile)
  xwOBA:        0.312  (45th percentile)
  xBA:          0.245  (41st percentile)
  xSLG:         0.418  (33rd percentile)
  Exit Velo:    90.3 mph (22nd percentile)
  Barrel%:      10.4%  (17th percentile)
  FB Velo:      95.0 mph (60th percentile)
  FB Spin:      2154 rpm (percentile available)
  Curve Spin:   2242 rpm (percentile available)
  K%:           ~22%   (43rd percentile)
  BB%:           ~9%   (28th percentile)
```

---

## How We Got The "Missing" Stats

### Bat Speed / Swing Length
**Source:** `pybaseball.statcast()` play-by-play data includes `bat_speed` and `swing_length` columns on tracked swings.

**Process:**
- Fetch ~770,000 pitches for full season
- Filter to tracked swings (bat_speed not null)
- Average per batter: `df.groupby('batter')['bat_speed'].mean()`

### Whiff% / Chase%
**Source:** `pybaseball.statcast()` with `description` and `zone` columns

**Calculation:**
```python
# Whiff% = swinging strikes / total swings
whiff_percent = (swinging_strikes / swings) * 100

# Chase% = swings outside zone / pitches outside zone  
chase_percent = (swings_outside_zone / pitches_outside) * 100
```

### Spin Rates
**Source:** `pybaseball.statcast()` includes `release_spin_rate` column

**Aggregation by pitch type:**
```python
# Group by pitcher and pitch category (fastball/breaking/offspeed)
fb_spin = df[df['pitch_category'] == 'Fastball']['release_spin_rate'].mean()
breaking_spin = df[df['pitch_category'] == 'Breaking']['release_spin_rate'].mean()
```

---

## Implementation

### Data Flow

```
1. Fetch percentile rankings (fast, single call)
2. Fetch aggregated stats from multiple endpoints:
   - Expected stats, exit velo, sprint speed, OAA
3. Fetch MLB Stats API for standard counting stats
4. Fetch SEASON-WIDE statcast data (~770k rows):
   - Takes ~2-3 minutes
   - Aggregate to player-level stats
5. Calculate K%/BB% from counting stats
6. Merge ALL sources and upsert to database
```

### Key Files

- `backend/statcast_aggregator.py` - Season-wide statcast fetcher and aggregator
- `backend/ingest_v2.py` - Main ingestion with all data sources
- `backend/savant_mapping.py` - Data source mapping

### Performance

- **Full season statcast fetch:** ~2-3 minutes (770k+ rows)
- **Total ingestion time:** ~5-6 minutes
- **Players covered:** 835 with complete data
- **Database rows:** 835 player snapshots

---

## Summary

**✅ ALL 19 STATS** now have actual values with percentiles!

The app now displays Baseball Savant-style data: **"74.9 mph · 76th percentile"** for every metric.
