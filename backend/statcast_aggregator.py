"""
Aggregates pitch-by-pitch Statcast data to compute player-level statistics.

Fetches season-wide data and calculates:
- Bat speed (average mph on swings)
- Swing length (average ft on swings)
- Whiff% (swinging strikes / total swings)
- Chase% (swings outside zone / pitches outside zone)
- Pitch spin rates by type (for pitchers)
"""

import logging
from typing import Optional
import pandas as pd
from pybaseball import statcast

logger = logging.getLogger(__name__)


def fetch_season_statcast(season: int) -> pd.DataFrame:
    """Fetch all Statcast pitch data for a season.
    
    Fetches in monthly chunks to avoid timeouts.
    """
    logger.info(f"Fetching Statcast data for season {season}...")
    
    # Define season date ranges (approximate MLB season)
    months = [
        (f"{season}-03-15", f"{season}-03-31"),  # Spring training + opening
        (f"{season}-04-01", f"{season}-04-30"),  # April
        (f"{season}-05-01", f"{season}-05-31"),  # May
        (f"{season}-06-01", f"{season}-06-30"),  # June
        (f"{season}-07-01", f"{season}-07-31"),  # July
        (f"{season}-08-01", f"{season}-08-31"),  # August
        (f"{season}-09-01", f"{season}-09-30"),  # September
        (f"{season}-10-01", f"{season}-10-31"),  # October (playoffs)
    ]
    
    all_data = []
    for start, end in months:
        try:
            logger.info(f"  Fetching {start} to {end}...")
            df = statcast(start, end)
            if len(df) > 0:
                all_data.append(df)
                logger.info(f"    Got {len(df):,} rows")
        except Exception as e:
            logger.warning(f"    Failed to fetch {start} to {end}: {e}")
    
    if not all_data:
        return pd.DataFrame()
    
    combined = pd.concat(all_data, ignore_index=True)
    logger.info(f"Total rows fetched: {len(combined):,}")
    return combined


def compute_batter_stats(df: pd.DataFrame) -> pd.DataFrame:
    """Compute batter statistics from pitch data.
    
    Returns DataFrame with columns:
    - batter (player_id)
    - bat_speed (avg mph)
    - swing_length (avg ft)
    - whiff_percent
    - chase_percent
    """
    logger.info("Computing batter statistics...")
    
    # Define swing outcomes
    swing_outcomes = [
        'hit_into_play', 'foul', 'swinging_strike', 
        'foul_tip', 'swinging_strike_blocked', 'foul_bunt'
    ]
    whiff_outcomes = ['swinging_strike', 'swinging_strike_blocked']
    
    # Mark swings, whiffs, and outside-zone pitches
    df['is_swing'] = df['description'].isin(swing_outcomes)
    df['is_whiff'] = df['description'].isin(whiff_outcomes)
    df['is_outside'] = df['zone'].isin([11, 12, 13, 14])
    df['is_chase'] = df['is_swing'] & df['is_outside']
    
    # Group by batter
    batter_stats = []
    
    for batter_id, group in df.groupby('batter'):
        # Bat speed and swing length (on tracked swings)
        swings_tracked = group[group['bat_speed'].notna()]
        
        bat_speed = swings_tracked['bat_speed'].mean() if len(swings_tracked) > 0 else None
        swing_length = swings_tracked['swing_length'].mean() if len(swings_tracked) > 0 else None
        
        # Plate discipline - calculate for any player with data
        # No minimum thresholds: if Baseball Savant provides a percentile,
        # we should provide the corresponding actual value
        total_swings = group['is_swing'].sum()
        total_whiffs = group['is_whiff'].sum()
        pitches_outside = group['is_outside'].sum()
        total_chases = group['is_chase'].sum()

        whiff_percent = (total_whiffs / total_swings * 100) if total_swings > 0 else None
        chase_percent = (total_chases / pitches_outside * 100) if pitches_outside > 0 else None
        
        batter_stats.append({
            'player_id': int(batter_id),
            'bat_speed': round(bat_speed, 1) if pd.notna(bat_speed) else None,
            'swing_length': round(swing_length, 2) if pd.notna(swing_length) else None,
            'whiff_percent': round(whiff_percent, 1) if whiff_percent is not None else None,
            'chase_percent': round(chase_percent, 1) if chase_percent is not None else None,
            'tracked_swings': len(swings_tracked),
            'total_swings': int(total_swings),
        })
    
    return pd.DataFrame(batter_stats)


def compute_pitcher_stats(df: pd.DataFrame) -> pd.DataFrame:
    """Compute pitcher statistics from pitch data.
    
    Returns DataFrame with columns:
    - pitcher (player_id)
    - avg_spin_rate (overall)
    - fastball_spin (4-seam, sinker)
    - breaking_spin (slider, curve, sweeper)
    - changeup_spin
    """
    logger.info("Computing pitcher statistics...")
    
    # Map pitch names to categories
    fastball_types = ['4-Seam Fastball', 'Sinker', 'Fastball']
    breaking_types = ['Slider', 'Curveball', 'Sweeper', 'Knuckle Curve']
    offspeed_types = ['Changeup', 'Split-Finger']
    
    def categorize_pitch(pitch_name):
        if not isinstance(pitch_name, str):
            return 'Other'
        if any(t in pitch_name for t in fastball_types):
            return 'Fastball'
        if any(t in pitch_name for t in breaking_types):
            return 'Breaking'
        if any(t in pitch_name for t in offspeed_types):
            return 'Offspeed'
        return 'Other'
    
    df['pitch_category'] = df['pitch_name'].apply(categorize_pitch)
    
    pitcher_stats = []
    
    for pitcher_id, group in df.groupby('pitcher'):
        # Overall spin rate (min 100 pitches)
        pitches_with_spin = group[group['release_spin_rate'].notna()]
        avg_spin = pitches_with_spin['release_spin_rate'].mean() if len(pitches_with_spin) >= 100 else None
        
        # Spin by pitch type (min 25 pitches each)
        fb_spins = group[(group['pitch_category'] == 'Fastball') & group['release_spin_rate'].notna()]
        breaking_spins = group[(group['pitch_category'] == 'Breaking') & group['release_spin_rate'].notna()]
        offspeed_spins = group[(group['pitch_category'] == 'Offspeed') & group['release_spin_rate'].notna()]
        
        fb_spin = fb_spins['release_spin_rate'].mean() if len(fb_spins) >= 25 else None
        breaking_spin = breaking_spins['release_spin_rate'].mean() if len(breaking_spins) >= 25 else None
        offspeed_spin = offspeed_spins['release_spin_rate'].mean() if len(offspeed_spins) >= 25 else None
        
        pitcher_stats.append({
            'player_id': int(pitcher_id),
            'avg_spin_rate': round(avg_spin, 0) if pd.notna(avg_spin) else None,
            'fastball_spin': round(fb_spin, 0) if pd.notna(fb_spin) else None,
            'breaking_spin': round(breaking_spin, 0) if pd.notna(breaking_spin) else None,
            'offspeed_spin': round(offspeed_spin, 0) if pd.notna(offspeed_spin) else None,
            'total_pitches': len(group),
        })
    
    return pd.DataFrame(pitcher_stats)


def build_complete_player_stats(season: int) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Build complete player stats for a season.
    
    Returns (batter_stats_df, pitcher_stats_df)
    """
    # Fetch all pitch data
    df = fetch_season_statcast(season)
    
    if df.empty:
        logger.error("No data fetched!")
        return pd.DataFrame(), pd.DataFrame()
    
    # Compute stats
    batter_stats = compute_batter_stats(df)
    pitcher_stats = compute_pitcher_stats(df)
    
    logger.info(f"Computed stats for {len(batter_stats)} batters and {len(pitcher_stats)} pitchers")
    
    return batter_stats, pitcher_stats


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    
    # Test for 2025
    batters, pitchers = build_complete_player_stats(2025)
    
    print("\n" + "="*60)
    print("SAMPLE BATTER STATS")
    print("="*60)
    print(batters[batters['tracked_swings'] > 100].head(10))
    
    print("\n" + "="*60)
    print("SAMPLE PITCHER STATS")
    print("="*60)
    print(pitchers[pitchers['total_pitches'] > 500].head(10))
