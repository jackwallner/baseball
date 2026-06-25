# Player Metrics Data Quality Audit - Summary

**Date:** May 3, 2026  
**Auditor:** Cascade AI  
**Scope:** All play-by-play based calculated metrics for all players, all years

---

## Executive Summary

A comprehensive audit of player data revealed significant data quality issues across all seasons. **The primary issue was that metrics were being created with empty actual values** - showing percentiles without corresponding stat values (e.g., "75th percentile" instead of "12.5% · 75th").

### Key Finding: Mike Trout Example
- **Issue:** Barrel% showing as just percentile without actual value
- **Root Cause:** Baseball Savant provides percentiles for players below qualification thresholds, but the ingestion code was creating metrics even when actual values were unavailable

---

## Audit Results by Season

| Season | Total Players | Data Completeness | Players with Missing Metrics | Players with Empty Values |
|--------|---------------|-------------------|------------------------------|---------------------------|
| 2024   | 1,302         | 57.6%             | 1,122 (86%)                  | 1,073 (82%)               |
| 2025   | 1,328         | 56.1%             | 1,151 (87%)                  | 1,084 (82%)               |
| 2026   | 844           | 75.5%             | 749 (89%)                    | 843 (100%)                |

### Most Common Issues (2026)

**Missing Metrics (not in data structure):**
- LA Sweet Spot%: 419 players (49.6%)
- Arm Value: 419 players (49.6%)
- Curve Spin: 327 players (38.7%)
- xwOBA, xBA, xSLG, xISO, xOBP, Barrel%, Hard-Hit%: 193 players (22.9%)

**Empty Values (in structure but no data):**
- xISO, xOBP: 651 players (77.1%)
- Hard-Hit%: 472 players (55.9%)
- Barrel%: 437 players (51.8%)
- Max EV: 384 players (45.5%)
- Whiff%, Chase%: 377 players (44.7%)

---

## Root Causes Identified

### 1. Qualification Thresholds Too High
pybaseball endpoints require minimum PA/BBE thresholds that exclude many players, especially early in the season:
- Batter expected stats: 100 PA minimum
- Batter exit velo: 100 BBE minimum
- Pitcher expected stats: 50 PA minimum
- Pitcher exit velo: 50 BBE minimum

### 2. Percentile-Only Data Being Included
Baseball Savant provides percentile rankings for players who don't meet qualification thresholds for actual stats. The ingestion code was creating metrics with just percentiles and empty actual values.

### 3. Missing Data Sources
Some expected metrics have no corresponding data source:
- LA Sweet Spot% - Not consistently available from pybaseball
- Arm Value - Not consistently available from pybaseball
- Arm Strength - Limited availability
- Curve Spin - Limited availability

---

## Fixes Implemented

### Fix 1: Skip Metrics Without Actual Values
**File:** `backend/ingest.py` - `build_metrics_with_values()` function

**Change:** Added check to skip metrics when actual_value is None or empty:
```python
# Skip metrics without actual values to prevent empty value issues
if not actual_value:
    continue
```

**Impact:** Metrics will only be included if they have both a percentile AND an actual value. This prevents the app from showing "75th percentile" without the corresponding "12.5%" value.

### Fix 2: Use Minimal Thresholds (Zero/One)
**File:** `backend/ingest.py` - `ActualValueStore._prefetch_all()` method

**Changes:** All data sources now use minimal thresholds (1 PA/BBE/pitch/attempt):
- Batter expected stats: 1 PA (was 100)
- Batter exit velo: 1 BBE (was 100)
- Sprint speed: 1 opportunity (was 25)
- OAA (fielding): 1 attempt (was 25)
- Pitcher expected stats: 1 PA (was 50)
- Pitcher exit velo: 1 BBE (was 50)
- Pitcher arsenal: 1 pitch (was 100)

**Philosophy:** If Baseball Savant provides a percentile ranking, we should provide the corresponding actual value regardless of sample size. This ensures consistency between what's shown in the app and what Savant calculates.

---

## Files Modified

1. **`backend/ingest.py`**
   - `build_metrics_with_values()` - Skip metrics without actual values
   - `ActualValueStore._prefetch_all()` - Lower thresholds for early season data

2. **`backend/audit_metrics.py`** (new)
   - Comprehensive audit script to verify data quality
   - Can audit specific players or entire seasons
   - Reports missing metrics and empty values

3. **`backend/test_fix.py`** (new)
   - Unit tests for the fix
   - Verifies metrics without values are skipped
   - Verifies no empty values in output

---

## Next Steps

### 1. Deploy the Fixes
Run the nightly ingestion workflow to populate the database with corrected data:
```bash
gh workflow run nightly-statcast.yml
```

### 2. Verify the Fix
After the next ingestion run, verify the fix by auditing Mike Trout and other players:
```bash
cd backend
source .env
python3 audit_metrics.py --season 2026 --player "Trout"
```

### 3. Re-Audit All Data
Run the comprehensive audit again to measure improvement:
```bash
python3 audit_metrics.py --all-seasons
```

### 4. Consider Additional Enhancements
- **Calculate missing metrics from play-by-play:** For metrics like Barrel%, EV, etc., calculate from raw Statcast pitch data when API thresholds aren't met
- **Add data source fallbacks:** Use multiple data sources (MLB Stats API, Baseball-Reference) to fill gaps
- **Update app display logic:** Show "Qualifying: N/A" instead of hiding metrics entirely for better UX

---

## Metrics Reference

### Batter Metrics (17 expected)
1. xwOBA ✓
2. xBA ✓
3. xSLG ✓
4. xISO (often missing)
5. xOBP (often missing)
6. EV (Exit Velocity) ✓
7. Barrel% ✓
8. Hard-Hit% ✓
9. LA Sweet Spot% (often missing)
10. Max EV ✓
11. Bat Speed ✓
12. Swing Length ✓
13. Squared-Up% ✓
14. Chase% ✓
15. Whiff% ✓
16. K% ✓
17. BB% ✓

### Running Metrics (1 expected)
1. Sprint Speed ✓

### Fielding Metrics (3 expected)
1. Range (OAA) ✓
2. Arm Value (often missing)
3. Arm Strength (often missing)

### Pitcher Metrics (17 expected)
1. xERA ✓
2. xwOBA ✓
3. xBA ✓
4. xSLG ✓
5. xISO (often missing)
6. xOBP (often missing)
7. Barrel% ✓
8. Avg EV Against ✓
9. Hard-Hit% ✓
10. Max EV Against ✓
11. K% ✓
12. BB% ✓
13. Whiff% ✓
14. Chase% ✓
15. Fastball Velo ✓
16. Fastball Spin ✓
17. Curve Spin (often missing)

---

## Appendix: Audit Commands

### Check a specific player
```bash
cd backend
source .env
python3 audit_metrics.py --season 2026 --player "Player Name"
```

### Audit entire season
```bash
python3 audit_metrics.py --season 2026
```

### Audit all seasons
```bash
python3 audit_metrics.py --all-seasons
```

### Save detailed results
```bash
python3 audit_metrics.py --season 2026 --output audit_2026.json
```
