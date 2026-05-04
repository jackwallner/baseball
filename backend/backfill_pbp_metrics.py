"""
Backfill play-by-play calculable metrics for all years (2015-2026).

These metrics are available from box scores / play-by-play data but may not
be in the Statcast tables. We fetch them from Baseball-Reference and update
the player_snapshots table.

Metrics backfilled:
- K%, BB% (plate discipline from box scores)
- AVG, OBP, SLG (traditional batting stats)
- BABIP (calculated from box score)
- GB%, FB% (from batted ball type strings)
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Optional

import pandas as pd
from dotenv import load_dotenv
from pybaseball import batting_stats_bref, pitching_stats_bref
from supabase import create_client

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Stats we can get from Baseball-Reference for all years
BATTER_PBP_STATS = {
    # Map BRef column -> (metric_key, display_name, category)
    "SO%": ("k_percent", "K%", "Hitting"),
    "BB%": ("bb_percent", "BB%", "Hitting"),  
    "AVG": ("avg", "AVG", "Hitting"),
    "OBP": ("obp", "OBP", "Hitting"),
    "SLG": ("slg", "SLG", "Hitting"),
    "BABIP": ("babip", "BABIP", "Hitting"),
    "GB%": ("gb_percent", "GB%", "Hitting"),
    "FB%": ("fb_percent", "FB%", "Hitting"),
}

PITCHER_PBP_STATS = {
    "SO%": ("k_percent", "K%", "Pitching"),
    "BB%": ("bb_percent", "BB%", "Pitching"),
    "AVG": ("avg_against", "AVG Against", "Pitching"),
    "BABIP": ("babip", "BABIP", "Pitching"),
}


def get_supabase_client():
    """Create Supabase client."""
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def fetch_batter_pbp_stats(season: int) -> pd.DataFrame:
    """Fetch batter stats from Baseball-Reference for a season."""
    logger.info(f"Fetching batter PBP stats for {season} from Baseball-Reference...")
    try:
        df = batting_stats_bref(season)
        logger.info(f"Fetched {len(df)} batter records for {season}")
        return df
    except Exception as e:
        logger.error(f"Failed to fetch batter stats for {season}: {e}")
        return pd.DataFrame()


def fetch_pitcher_pbp_stats(season: int) -> pd.DataFrame:
    """Fetch pitcher stats from Baseball-Reference for a season."""
    logger.info(f"Fetching pitcher PBP stats for {season} from Baseball-Reference...")
    try:
        df = pitching_stats_bref(season)
        logger.info(f"Fetched {len(df)} pitcher records for {season}")
        return df
    except Exception as e:
        logger.error(f"Failed to fetch pitcher stats for {season}: {e}")
        return pd.DataFrame()


def fetch_existing_players(season: int) -> dict[str, dict]:
    """Fetch existing players from Supabase for a season."""
    supabase = get_supabase_client()
    
    logger.info(f"Fetching existing players for {season} from Supabase...")
    all_players = []
    batch_size = 1000
    offset = 0
    
    while True:
        response = (
            supabase.table("player_snapshots")
            .select("id, name, team, player_type, metrics")
            .eq("season", season)
            .range(offset, offset + batch_size - 1)
            .execute()
        )
        
        batch = response.data
        if not batch:
            break
        
        all_players.extend(batch)
        offset += batch_size
        
        if len(batch) < batch_size:
            break
    
    # Index by name for matching (BRef uses player names)
    # Note: This is imperfect - names may not match exactly
    players_by_name = {}
    for p in all_players:
        name = p.get("name", "").lower().strip()
        if name:
            players_by_name[name] = p
    
    logger.info(f"Found {len(players_by_name)} existing players for {season}")
    return players_by_name


def match_player(bref_name: str, existing_players: dict[str, dict]) -> Optional[dict]:
    """Match a Baseball-Reference player name to Supabase player."""
    name_lower = bref_name.lower().strip()
    
    # Direct match
    if name_lower in existing_players:
        return existing_players[name_lower]
    
    # Try common variations (remove accents, etc.)
    variations = [
        name_lower,
        name_lower.replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u"),
        name_lower.replace("ñ", "n"),
    ]
    
    for var in variations:
        if var in existing_players:
            return existing_players[var]
    
    return None


def convert_stat_to_metric(value: Any, metric_key: str, display_name: str, category: str) -> dict:
    """Convert a stat value to a metric entry."""
    if pd.isna(value) or value is None:
        return None
    
    # Format the value
    if isinstance(value, (int, float)):
        if metric_key in ["avg", "obp", "slg", "babip"]:
            # Rate stats: show as .XXX
            formatted = f"{value:.3f}".lstrip("0") if value < 1 else f"{value:.3f}"
        elif "%" in display_name.lower():
            # Percentage: show as XX.X%
            formatted = f"{value:.1f}%"
        else:
            formatted = str(value)
        numeric = float(value)
    else:
        formatted = str(value)
        try:
            numeric = float(value)
        except (ValueError, TypeError):
            numeric = None
    
    return {
        "key": metric_key,
        "label": display_name,
        "value": formatted,
        "numeric": numeric,
        "category": category,
    }


def update_player_metrics(player: dict, new_metrics: list[dict]) -> dict:
    """Update a player's metrics list with new metrics."""
    existing_metrics = player.get("metrics", [])
    if isinstance(existing_metrics, str):
        existing_metrics = json.loads(existing_metrics)
    
    # Create lookup by label (Supabase uses 'label' not 'key')
    metrics_by_label = {m.get("label", m.get("key", "")): m for m in existing_metrics}
    
    # Add/update new metrics
    for metric in new_metrics:
        if metric:
            label = metric.get("label", metric.get("key", ""))
            metrics_by_label[label] = metric
    
    return {**player, "metrics": list(metrics_by_label.values())}


def backfill_season(season: int) -> dict[str, int]:
    """Backfill PBP metrics for a single season."""
    logger.info(f"\n{'='*70}")
    logger.info(f"BACKFILLING SEASON {season}")
    logger.info(f"{'='*70}")
    
    stats = {"batters_matched": 0, "pitchers_matched": 0, "updated": 0, "failed": 0}
    
    # Fetch existing players from Supabase
    existing_players = fetch_existing_players(season)
    if not existing_players:
        logger.warning(f"No existing players found for {season}, skipping")
        return stats
    
    # Fetch BRef stats
    batter_df = fetch_batter_pbp_stats(season)
    pitcher_df = fetch_pitcher_pbp_stats(season)
    
    if batter_df.empty and pitcher_df.empty:
        logger.warning(f"No BRef data available for {season}")
        return stats
    
    supabase = get_supabase_client()
    
    # Process batters
    if not batter_df.empty:
        logger.info(f"Processing {len(batter_df)} batter records...")
        for _, row in batter_df.iterrows():
            bref_name = row.get("Name", "")
            player = match_player(bref_name, existing_players)
            
            if player:
                stats["batters_matched"] += 1
                new_metrics = []
                
                for bref_col, (metric_key, display_name, category) in BATTER_PBP_STATS.items():
                    if bref_col in row:
                        metric = convert_stat_to_metric(
                            row[bref_col], metric_key, display_name, category
                        )
                        if metric:
                            new_metrics.append(metric)
                
                if new_metrics:
                    updated_player = update_player_metrics(player, new_metrics)
                    try:
                        # Need to include all required fields for upsert
                        upsert_data = {
                            "id": updated_player["id"],
                            "season": season,
                            "name": updated_player.get("name", bref_name),
                            "team": updated_player.get("team", "TBD"),
                            "player_type": updated_player.get("player_type", "unknown"),
                            "data_source": updated_player.get("data_source", "pbp_backfill"),
                            "metrics": updated_player["metrics"],
                        }
                        supabase.table("player_snapshots").upsert(upsert_data, on_conflict="id,season").execute()
                        stats["updated"] += 1
                    except Exception as e:
                        logger.error(f"Failed to update {bref_name}: {e}")
                        stats["failed"] += 1
    
    # Process pitchers
    if not pitcher_df.empty:
        logger.info(f"Processing {len(pitcher_df)} pitcher records...")
        for _, row in pitcher_df.iterrows():
            bref_name = row.get("Name", "")
            player = match_player(bref_name, existing_players)
            
            if player:
                stats["pitchers_matched"] += 1
                new_metrics = []
                
                for bref_col, (metric_key, display_name, category) in PITCHER_PBP_STATS.items():
                    if bref_col in row:
                        metric = convert_stat_to_metric(
                            row[bref_col], metric_key, display_name, category
                        )
                        if metric:
                            new_metrics.append(metric)
                
                if new_metrics:
                    updated_player = update_player_metrics(player, new_metrics)
                    try:
                        # Need to include all required fields for upsert
                        upsert_data = {
                            "id": updated_player["id"],
                            "season": season,
                            "name": updated_player.get("name", bref_name),
                            "team": updated_player.get("team", "TBD"),
                            "player_type": updated_player.get("player_type", "unknown"),
                            "data_source": updated_player.get("data_source", "pbp_backfill"),
                            "metrics": updated_player["metrics"],
                        }
                        supabase.table("player_snapshots").upsert(upsert_data, on_conflict="id,season").execute()
                        stats["updated"] += 1
                    except Exception as e:
                        logger.error(f"Failed to update {bref_name}: {e}")
                        stats["failed"] += 1
    
    logger.info(f"\nSeason {season} summary:")
    logger.info(f"  Batters matched: {stats['batters_matched']}")
    logger.info(f"  Pitchers matched: {stats['pitchers_matched']}")
    logger.info(f"  Players updated: {stats['updated']}")
    logger.info(f"  Failed: {stats['failed']}")
    
    return stats


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Backfill PBP-calculable metrics")
    parser.add_argument("--season", type=int, help="Single season to backfill")
    parser.add_argument("--start", type=int, default=2015, help="Start year (default: 2015)")
    parser.add_argument("--end", type=int, default=2026, help="End year (default: 2026)")
    args = parser.parse_args()
    
    if args.season:
        years = [args.season]
    else:
        years = list(range(args.start, args.end + 1))
    
    logger.info("=" * 70)
    logger.info("BACKFILLING PBP-CALCULABLE METRICS")
    logger.info(f"Years: {years}")
    logger.info("=" * 70)
    
    total_stats = {"batters_matched": 0, "pitchers_matched": 0, "updated": 0, "failed": 0}
    
    for season in years:
        try:
            stats = backfill_season(season)
            for key in total_stats:
                total_stats[key] += stats[key]
        except Exception as e:
            logger.exception(f"Failed to process season {season}: {e}")
    
    logger.info("\n" + "=" * 70)
    logger.info("BACKFILL COMPLETE")
    logger.info("=" * 70)
    logger.info(f"Total batters matched: {total_stats['batters_matched']}")
    logger.info(f"Total pitchers matched: {total_stats['pitchers_matched']}")
    logger.info(f"Total players updated: {total_stats['updated']}")
    logger.info(f"Total failures: {total_stats['failed']}")


if __name__ == "__main__":
    main()
