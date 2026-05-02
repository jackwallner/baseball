# Pybaseball Data Source Comparison for Savant-Style Display

## Summary

**Key Finding:** pybaseball provides **BOTH** percentile rankings AND actual values, but from **different endpoints**.

To display data like Baseball Savant (e.g., "95.4 mph · 100th percentile"), we need to fetch from multiple sources and merge them.

---

## Data Sources Comparison

### 1. Percentile Ranks Only (0-100 scale)

| Function | Data Type | Key Metrics |
|----------|-----------|-------------|
| `statcast_batter_percentile_ranks` | Percentiles | xwoba, xslg, xba, exit_velocity, sprint_speed, oaa, brl_percent, k_percent, bb_percent, whiff_percent, chase_percent, arm_strength, bat_speed |
| `statcast_pitcher_percentile_ranks` | Percentiles | xwoba, xera, xba, exit_velocity, k_percent, bb_percent, whiff_percent, chase_percent, fb_velocity, fb_spin, curve_spin |

**Limitation:** Only returns 0-100 percentiles, not actual stat values.

---

### 2. Actual Values (Raw Stats)

| Function | Data Type | Key Metrics | Sample Values |
|----------|-----------|-------------|---------------|
| `statcast_sprint_speed` | Actual ft/s | sprint_speed, hp_to_1b, bolts | **30.3 ft/s**, 4.13 sec |
| `statcast_batter_expected_stats` | Actual decimals | est_woba, est_slg, est_ba | **0.460**, **0.708**, **0.300** |
| `statcast_batter_exitvelo_barrels` | Actual mph/% | avg_hit_speed, brl_percent, ev95percent | **95.4 mph**, **24.7%** |
| `statcast_pitcher_expected_stats` | Actual decimals | est_woba, xera, est_ba | **2.85**, **3.12** |
| `statcast_pitcher_exitvelo_barrels` | Actual mph/% | avg_hit_speed, brl_percent | **88.2 mph** |
| `statcast_pitcher_pitch_arsenal` | Actual mph | ff_avg_speed, sl_avg_speed, ch_avg_speed | **96.5 mph** |
| `statcast_outs_above_average` | Actual count | outs_above_average, fielding_runs_prevented | **+15 OAA**, **+12 runs** |
| `statcast_outfielder_jump` | Actual feet | f_bootup_distance, outs_above_average | **38.9 ft** |

---

## Example: Aaron Judge (2025)

| Metric | Percentile Rank | Actual Value | Source for Actual |
|--------|-----------------|--------------|-------------------|
| xwOBA | 100 | 0.460 | expected_stats |
| xSLG | 100 | 0.708 | expected_stats |
| xBA | - | 0.300 | expected_stats |
| Exit Velocity | 100 | 95.4 mph | exitvelo_barrels |
| Barrel % | - | 24.7% | exitvelo_barrels |
| Sprint Speed | 42 | 27.1 ft/s | sprint_speed |
| OAA | 87 | +15 | outs_above_average |

---

## Recommendation: Hybrid Approach

### Option A: Simple (Current) - Percentiles Only
- **Pros:** Single API call, consistent data, easier to cache
- **Cons:** Can't show "95.4 mph" - only "100th percentile"

### Option B: Enhanced - Fetch Both
- **Pros:** Shows actual values like Baseball Savant, more informative
- **Cons:** Multiple API calls, more complex backend, higher latency

### Option C: Tiered (Recommended)
1. **Primary:** Use percentile_ranks for overview (fast, single call)
2. **On demand:** Fetch actual values from specific endpoints when needed
3. **Smart caching:** Cache actual values separately with same TTL

---

## Implementation Strategy

```python
# New endpoints needed:
GET /player/{id}/savant-values  # Actual values from specific endpoints
GET /player/{id}/savant         # Existing: percentiles

# Merge in backend or let frontend call both
```

### Data Flow for Savant-Style Display:

```
Player Profile View
    ↓
[1] Fetch percentiles (existing endpoint)
    ↓
[2] Fetch actual values:
    - Sprint speed → statcast_sprint_speed
    - xwOBA/xSLG → statcast_batter_expected_stats  
    - Exit velo → statcast_batter_exitvelo_barrels
    - Pitch velo → statcast_pitcher_pitch_arsenal
    - Fielding → statcast_outs_above_average
    ↓
[3] Merge by player_id
    ↓
Response: {
  "percentiles": { "xwoba": 100, ... },
  "actual_values": { "xwoba": 0.460, "exit_velocity": 95.4, ... }
}
```

---

## Coverage Gaps

**NOT available in pybaseball (actual MLB Savant feature):**
- Run Values (Batting, Baserunning, Fielding, Pitching)
- These require play-by-play run expectancy calculations

**Workaround:** Remove these metrics or calculate from `statcast()` play-by-play data (very large dataset).

---

## Data Completeness by Source

| Metric Category | Percentiles Available | Actual Values Available | Can Merge? |
|-----------------|----------------------|-------------------------|------------|
| Hitting (xwOBA) | ✅ Yes | ✅ Yes (expected_stats) | ✅ Yes |
| Exit Velocity | ✅ Yes | ✅ Yes (exitvelo_barrels) | ✅ Yes |
| Sprint Speed | ✅ Yes | ✅ Yes (sprint_speed) | ✅ Yes |
| Fielding (OAA) | ✅ Yes | ✅ Yes (outs_above_average) | ✅ Yes |
| K% / BB% | ✅ Yes | ❌ No | ❌ No |
| Whiff% / Chase% | ✅ Yes | ❌ No | ❌ No |
| Pitch Velocity | ✅ Yes | ✅ Yes (pitch_arsenal) | ✅ Yes |
| Pitch Spin | ✅ Yes | ❌ No | ❌ No |
