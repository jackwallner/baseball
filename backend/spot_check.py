"""
Spot check random players across seasons to verify data matches Baseball Savant.

Usage:
    python backend/spot_check.py
"""

import os
import random
import logging
from supabase import create_client
from pybaseball import (
    statcast_batter_percentile_ranks,
    statcast_pitcher_percentile_ranks,
    statcast_batter_expected_stats,
    statcast_batter_exitvelo_barrels,
    statcast_sprint_speed,
    statcast_pitcher_expected_stats,
    statcast_pitcher_exitvelo_barrels,
    statcast_pitcher_pitch_arsenal,
)
from pybaseball.statcast_fielding import statcast_outs_above_average
from pybaseball import statcast
import pandas as pd

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")


def get_random_players(client, player_type, count=10):
    """Get random players from database across different seasons."""
    # Get all players of type
    result = client.table("player_snapshots").select("id, name, season, metrics, player_type").execute()
    
    if not result.data:
        return []
    
    # Filter by player type
    players = [p for p in result.data if player_type in p.get("player_type", "")]
    
    # Group by season and pick random from each
    by_season = {}
    for p in players:
        season = p["season"]
        if season not in by_season:
            by_season[season] = []
        by_season[season].append(p)
    
    # Pick random players across seasons
    selected = []
    seasons = list(by_season.keys())
    
    for _ in range(count):
        season = random.choice(seasons)
        player = random.choice(by_season[season])
        selected.append(player)
    
    return selected


def get_metric_value(metrics, label):
    """Extract value from metrics array."""
    for m in metrics:
        if m.get("label") == label:
            return m.get("value", "N/A")
    return "N/A"


def verify_batter(player_id, season, name):
    """Verify batter stats against Savant data."""
    logger.info(f"\n{'='*70}")
    logger.info(f"VERIFYING BATTER: {name} (ID: {player_id}, Season: {season})")
    logger.info(f"{'='*70}")
    
    discrepancies = []
    
    try:
        # Get our data
        result = client.table("player_snapshots").select("metrics").eq("id", player_id).eq("season", season).execute()
        if not result.data:
            logger.error(f"  Player not found in database!")
            return False
        
        our_metrics = {m["label"]: m.get("value", "N/A") for m in result.data[0].get("metrics", [])}
        
        # Get Savant reference data
        pct = statcast_batter_percentile_ranks(season)
        savant = pct[pct["player_id"] == player_id]
        
        if savant.empty:
            logger.warning(f"  No Savant data found for this player/season")
            return False
        
        savant_row = savant.iloc[0]
        
        # Check key metrics
        checks = [
            ("xwOBA", "xwoba", lambda x: f"{float(x):.3f}" if x != "N/A" else "N/A"),
            ("xSLG", "xslg", lambda x: f"{float(x):.3f}" if x != "N/A" else "N/A"),
            ("EV", "exit_velocity", lambda x: f"{float(x):.1f} mph" if x != "N/A" else "N/A"),
            ("Barrel%", "brl_percent", lambda x: f"{float(x):.1f}%" if x != "N/A" else "N/A"),
            ("Sprint Speed", "sprint_speed", lambda x: f"{float(x):.1f} ft/s" if x != "N/A" else "N/A"),
        ]
        
        for our_label, savant_key, formatter in checks:
            our_val = our_metrics.get(our_label, "N/A")
            savant_val = savant_row.get(savant_key)
            
            if pd.notna(savant_val):
                # Compare percentile
                our_percentile = None
                for m in result.data[0].get("metrics", []):
                    if m["label"] == our_label:
                        our_percentile = m.get("percentile")
                        break
                
                savant_percentile = int(round(float(savant_val)))
                
                status = "✅" if our_percentile == savant_percentile else "❌"
                logger.info(f"  {our_label}: {status} Percentile {our_percentile} (Savant: {savant_percentile})")
                
                if our_percentile != savant_percentile:
                    discrepancies.append(f"{our_label}: {our_percentile} vs {savant_percentile}")
            else:
                logger.info(f"  {our_label}: ⚠️ No Savant data")
        
        # Check actual values from other sources
        try:
            exp = statcast_batter_expected_stats(season, 100)
            exp_row = exp[exp["player_id"] == player_id]
            if not exp_row.empty:
                our_xwoba = our_metrics.get("xwOBA", "N/A").replace(" ft/s", "").replace(" mph", "").replace("%", "")
                savant_xwoba = f"{exp_row.iloc[0]['est_woba']:.3f}"
                if our_xwoba != "N/A" and abs(float(our_xwoba) - float(savant_xwoba)) < 0.001:
                    logger.info(f"  xwOBA Actual: ✅ {our_xwoba} (Savant: {savant_xwoba})")
                elif our_xwoba != "N/A":
                    logger.info(f"  xwOBA Actual: ❌ {our_xwoba} (Savant: {savant_xwoba})")
                    discrepancies.append(f"xwOBA actual: {our_xwoba} vs {savant_xwoba}")
        except Exception as e:
            logger.debug(f"  Could not verify expected stats: {e}")
        
        if discrepancies:
            logger.warning(f"  Discrepancies found: {discrepancies}")
            return False
        else:
            logger.info(f"  ✅ All checks passed!")
            return True
            
    except Exception as e:
        logger.error(f"  Error verifying: {e}")
        return False


def verify_pitcher(player_id, season, name):
    """Verify pitcher stats against Savant data."""
    logger.info(f"\n{'='*70}")
    logger.info(f"VERIFYING PITCHER: {name} (ID: {player_id}, Season: {season})")
    logger.info(f"{'='*70}")
    
    discrepancies = []
    
    try:
        # Get our data
        result = client.table("player_snapshots").select("metrics").eq("id", player_id).eq("season", season).execute()
        if not result.data:
            logger.error(f"  Player not found in database!")
            return False
        
        our_metrics = {m["label"]: m.get("value", "N/A") for m in result.data[0].get("metrics", [])}
        
        # Get Savant reference data
        pct = statcast_pitcher_percentile_ranks(season)
        savant = pct[pct["player_id"] == player_id]
        
        if savant.empty:
            logger.warning(f"  No Savant data found for this player/season")
            return False
        
        savant_row = savant.iloc[0]
        
        # Check key metrics
        checks = [
            ("xwOBA", "xwoba", "percentile"),
            ("xERA", "xera", "percentile"),
            ("Avg EV Against", "exit_velocity", "percentile"),
            ("Barrel%", "brl_percent", "percentile"),
            ("Fastball Velo", "fb_velocity", "percentile"),
        ]
        
        for our_label, savant_key, check_type in checks:
            savant_val = savant_row.get(savant_key)
            
            if pd.notna(savant_val):
                # Compare percentile
                our_percentile = None
                for m in result.data[0].get("metrics", []):
                    if m["label"] == our_label:
                        our_percentile = m.get("percentile")
                        break
                
                savant_percentile = int(round(float(savant_val)))
                
                status = "✅" if our_percentile == savant_percentile else "❌"
                logger.info(f"  {our_label}: {status} Percentile {our_percentile} (Savant: {savant_percentile})")
                
                if our_percentile != savant_percentile:
                    discrepancies.append(f"{our_label}: {our_percentile} vs {savant_percentile}")
            else:
                logger.info(f"  {our_label}: ⚠️ No Savant data")
        
        # Check actual values
        try:
            exp = statcast_pitcher_expected_stats(season, 50)
            exp_row = exp[exp["player_id"] == player_id]
            if not exp_row.empty:
                our_xera = our_metrics.get("xERA", "N/A")
                savant_xera = f"{exp_row.iloc[0]['xera']:.2f}"
                if our_xera != "N/A" and abs(float(our_xera) - float(savant_xera)) < 0.01:
                    logger.info(f"  xERA Actual: ✅ {our_xera} (Savant: {savant_xera})")
                elif our_xera != "N/A":
                    logger.info(f"  xERA Actual: ❌ {our_xera} (Savant: {savant_xera})")
                    discrepancies.append(f"xERA actual: {our_xera} vs {savant_xera}")
        except Exception as e:
            logger.debug(f"  Could not verify expected stats: {e}")
        
        if discrepancies:
            logger.warning(f"  Discrepancies found: {discrepancies}")
            return False
        else:
            logger.info(f"  ✅ All checks passed!")
            return True
            
    except Exception as e:
        logger.error(f"  Error verifying: {e}")
        return False


def main():
    global client
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    
    if not url or not key:
        logger.error("Missing Supabase credentials")
        return
    
    client = create_client(url, key)
    
    logger.info("="*70)
    logger.info("SPOT CHECK: Verifying 10 random hitters and 10 random pitchers")
    logger.info("="*70)
    
    # Get random hitters
    hitters = get_random_players(client, "batter", 10)
    logger.info(f"\nSelected {len(hitters)} random hitters")
    
    hitter_pass = 0
    for h in hitters:
        if verify_batter(h["id"], h["season"], h["name"]):
            hitter_pass += 1
    
    # Get random pitchers
    pitchers = get_random_players(client, "pitcher", 10)
    logger.info(f"\nSelected {len(pitchers)} random pitchers")
    
    pitcher_pass = 0
    for p in pitchers:
        if verify_pitcher(p["id"], p["season"], p["name"]):
            pitcher_pass += 1
    
    # Summary
    logger.info("\n" + "="*70)
    logger.info("SPOT CHECK SUMMARY")
    logger.info("="*70)
    logger.info(f"Hitters: {hitter_pass}/{len(hitters)} passed")
    logger.info(f"Pitchers: {pitcher_pass}/{len(pitchers)} passed")
    logger.info(f"Total: {hitter_pass + pitcher_pass}/{len(hitters) + len(pitchers)} passed")
    
    if hitter_pass == len(hitters) and pitcher_pass == len(pitchers):
        logger.info("✅ ALL SPOT CHECKS PASSED!")
    else:
        logger.warning("⚠️ Some spot checks failed - review discrepancies above")


if __name__ == "__main__":
    main()
