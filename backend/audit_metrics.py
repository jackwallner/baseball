"""
Comprehensive audit script for player data metrics.

This script verifies that all play-by-play based calculated metrics are present
for all players across all years in the Supabase database.

Metrics audited:
- Batter Metrics: xwOBA, xBA, xSLG, xISO, xOBP, EV, Barrel%, Hard-Hit%, LA Sweet Spot%, 
  Max EV, Bat Speed, Swing Length, Squared-Up%, Chase%, Whiff%, K%, BB%
- Running Metrics: Sprint Speed
- Fielding Metrics: OAA (Range), Arm Value, Arm Strength
- Pitcher Metrics: xERA, xwOBA, xBA, xSLG, xISO, xOBP, Barrel%, Avg EV Against,
  Hard-Hit%, Max EV Against, K%, BB%, Whiff%, Chase%, Fastball Velo, Fastball Spin, Curve Spin
"""

import json
import logging
import os
import sys
from collections import defaultdict
from datetime import datetime
from typing import Any, Optional

import pandas as pd
import requests
from dotenv import load_dotenv
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

# All metrics we expect to find in the database
EXPECTED_BATTER_METRICS = [
    "xwOBA", "xBA", "xSLG", "xISO", "xOBP",
    "EV", "Barrel%", "Hard-Hit%", "LA Sweet Spot%", "Max EV",
    "Bat Speed", "Swing Length", "Squared-Up%",
    "Chase%", "Whiff%", "K%", "BB%"
]

EXPECTED_RUNNING_METRICS = ["Sprint Speed"]

EXPECTED_FIELDING_METRICS = ["Range (OAA)", "Arm Value", "Arm Strength"]

EXPECTED_PITCHER_METRICS = [
    "xERA", "xwOBA", "xBA", "xSLG", "xISO", "xOBP",
    "Barrel%", "Avg EV Against", "Hard-Hit%", "Max EV Against",
    "K%", "BB%", "Whiff%", "Chase%",
    "Fastball Velo", "Fastball Spin", "Curve Spin"
]

ALL_EXPECTED_METRICS = (
    EXPECTED_BATTER_METRICS + 
    EXPECTED_RUNNING_METRICS + 
    EXPECTED_FIELDING_METRICS + 
    EXPECTED_PITCHER_METRICS
)


def get_supabase_client():
    """Create Supabase client."""
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def fetch_all_players_for_season(season: int) -> list[dict]:
    """Fetch all player snapshots for a given season."""
    supabase = get_supabase_client()
    
    logger.info(f"Fetching all players for season {season}...")
    
    all_players = []
    batch_size = 1000
    offset = 0
    
    while True:
        response = (
            supabase.table("player_snapshots")
            .select("*")
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
    
    logger.info(f"Fetched {len(all_players)} players for season {season}")
    return all_players


def audit_player_metrics(player: dict) -> dict[str, Any]:
    """
    Audit a single player's metrics.
    
    Returns a dict with:
    - player_id, name, team, player_type
    - present_metrics: list of metrics that exist
    - missing_metrics: list of metrics that should exist but don't
    - empty_metrics: list of metrics with empty/null values
    """
    metrics = player.get("metrics", [])
    if isinstance(metrics, str):
        metrics = json.loads(metrics)
    
    player_type = player.get("player_type", "unknown")
    
    # Determine which metrics are expected for this player type
    if player_type == "batter":
        expected = EXPECTED_BATTER_METRICS + EXPECTED_RUNNING_METRICS + EXPECTED_FIELDING_METRICS
    elif player_type == "pitcher":
        expected = EXPECTED_PITCHER_METRICS
    elif player_type == "two_way":
        expected = list(set(
            EXPECTED_BATTER_METRICS + EXPECTED_RUNNING_METRICS + 
            EXPECTED_FIELDING_METRICS + EXPECTED_PITCHER_METRICS
        ))
    else:
        expected = []
    
    # Get present metrics (by label)
    present_metrics = []
    empty_metrics = []
    
    for metric in metrics:
        label = metric.get("label", "")
        value = metric.get("value", "")
        
        if label:
            present_metrics.append(label)
            # Check if value is empty or null
            if not value or value == "" or value == "None":
                empty_metrics.append(label)
    
    # Find missing metrics
    missing_metrics = [m for m in expected if m not in present_metrics]
    
    return {
        "player_id": player.get("id"),
        "name": player.get("name"),
        "team": player.get("team"),
        "player_type": player_type,
        "present_metrics": present_metrics,
        "missing_metrics": missing_metrics,
        "empty_metrics": empty_metrics,
        "total_expected": len(expected),
        "total_present": len(present_metrics),
        "completeness_pct": round(len(present_metrics) / len(expected) * 100, 1) if expected else 0,
    }


def audit_season(season: int) -> dict[str, Any]:
    """
    Audit all players for a given season.
    
    Returns comprehensive audit results.
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"AUDITING SEASON {season}")
    logger.info(f"{'='*60}")
    
    players = fetch_all_players_for_season(season)
    
    if not players:
        logger.warning(f"No players found for season {season}")
        return {"season": season, "players": [], "summary": {}}
    
    # Audit each player
    player_audits = []
    for player in players:
        try:
            audit = audit_player_metrics(player)
            player_audits.append(audit)
        except Exception as e:
            logger.error(f"Failed to audit player {player.get('id')}: {e}")
    
    # Calculate summary statistics
    total_players = len(player_audits)
    batter_count = sum(1 for p in player_audits if p["player_type"] == "batter")
    pitcher_count = sum(1 for p in player_audits if p["player_type"] == "pitcher")
    two_way_count = sum(1 for p in player_audits if p["player_type"] == "two_way")
    
    # Calculate average completeness
    avg_completeness = sum(p["completeness_pct"] for p in player_audits) / total_players if total_players else 0
    
    # Find players with missing metrics
    players_with_missing = [p for p in player_audits if p["missing_metrics"]]
    players_with_empty = [p for p in player_audits if p["empty_metrics"]]
    
    # Count missing metrics across all players
    all_missing_counts = defaultdict(int)
    all_empty_counts = defaultdict(int)
    
    for p in player_audits:
        for metric in p["missing_metrics"]:
            all_missing_counts[metric] += 1
        for metric in p["empty_metrics"]:
            all_empty_counts[metric] += 1
    
    # Sort by frequency
    top_missing = sorted(all_missing_counts.items(), key=lambda x: x[1], reverse=True)[:10]
    top_empty = sorted(all_empty_counts.items(), key=lambda x: x[1], reverse=True)[:10]
    
    summary = {
        "season": season,
        "total_players": total_players,
        "batters": batter_count,
        "pitchers": pitcher_count,
        "two_way": two_way_count,
        "avg_completeness_pct": round(avg_completeness, 1),
        "players_with_missing_metrics": len(players_with_missing),
        "players_with_empty_values": len(players_with_empty),
        "top_missing_metrics": top_missing,
        "top_empty_metrics": top_empty,
    }
    
    return {
        "season": season,
        "players": player_audits,
        "summary": summary,
    }


def print_audit_report(results: dict[str, Any], detail_limit: int = 20):
    """Print a formatted audit report."""
    summary = results["summary"]
    season = summary["season"]
    
    print(f"\n{'='*70}")
    print(f"AUDIT REPORT FOR SEASON {season}")
    print(f"{'='*70}")
    
    print(f"\n📊 SUMMARY:")
    print(f"  Total Players: {summary['total_players']}")
    print(f"  - Batters: {summary['batters']}")
    print(f"  - Pitchers: {summary['pitchers']}")
    print(f"  - Two-Way: {summary['two_way']}")
    print(f"\n  Average Completeness: {summary['avg_completeness_pct']}%")
    print(f"  Players with Missing Metrics: {summary['players_with_missing_metrics']}")
    print(f"  Players with Empty Values: {summary['players_with_empty_values']}")
    
    if summary["top_missing_metrics"]:
        print(f"\n🔴 TOP MISSING METRICS (by frequency):")
        for metric, count in summary["top_missing_metrics"]:
            pct = count / summary["total_players"] * 100
            print(f"  - {metric}: {count} players ({pct:.1f}%)")
    
    if summary["top_empty_metrics"]:
        print(f"\n⚠️  TOP EMPTY VALUE METRICS (by frequency):")
        for metric, count in summary["top_empty_metrics"]:
            pct = count / summary["total_players"] * 100
            print(f"  - {metric}: {count} players ({pct:.1f}%)")
    
    # Show sample players with issues
    players_with_issues = [
        p for p in results["players"] 
        if p["missing_metrics"] or p["empty_metrics"]
    ][:detail_limit]
    
    if players_with_issues:
        print(f"\n🔍 SAMPLE PLAYERS WITH ISSUES (showing {len(players_with_issues)}):")
        for p in players_with_issues:
            issues = []
            if p["missing_metrics"]:
                issues.append(f"missing: {', '.join(p['missing_metrics'][:3])}")
            if p["empty_metrics"]:
                issues.append(f"empty: {', '.join(p['empty_metrics'][:3])}")
            print(f"  - {p['name']} ({p['team']}, {p['player_type']}): {', '.join(issues)}")
    
    print(f"\n{'='*70}\n")


def check_specific_player(season: int, player_name: str) -> Optional[dict]:
    """Check a specific player by name."""
    supabase = get_supabase_client()
    
    response = (
        supabase.table("player_snapshots")
        .select("*")
        .eq("season", season)
        .ilike("name", f"%{player_name}%")
        .execute()
    )
    
    if not response.data:
        logger.warning(f"Player '{player_name}' not found in season {season}")
        return None
    
    player = response.data[0]
    audit = audit_player_metrics(player)
    
    print(f"\n{'='*60}")
    print(f"DETAILED AUDIT: {audit['name']} (Season {season})")
    print(f"{'='*60}")
    print(f"Player ID: {audit['player_id']}")
    print(f"Team: {audit['team']}")
    print(f"Type: {audit['player_type']}")
    print(f"Completeness: {audit['completeness_pct']}% ({audit['total_present']}/{audit['total_expected']})")
    
    if audit["missing_metrics"]:
        print(f"\n🔴 MISSING METRICS:")
        for m in audit["missing_metrics"]:
            print(f"  - {m}")
    
    if audit["empty_metrics"]:
        print(f"\n⚠️  EMPTY VALUE METRICS:")
        for m in audit["empty_metrics"]:
            print(f"  - {m}")
    
    if not audit["missing_metrics"] and not audit["empty_metrics"]:
        print("\n✅ All metrics present and populated!")
    
    print(f"\n📋 ALL PRESENT METRICS:")
    for m in sorted(audit["present_metrics"]):
        status = "✅" if m not in audit["empty_metrics"] else "⚠️"
        print(f"  {status} {m}")
    
    print(f"{'='*60}\n")
    
    return audit


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Audit player metrics in Supabase")
    parser.add_argument("--season", type=int, default=2026, help="Season to audit (default: 2026)")
    parser.add_argument("--player", type=str, help="Check specific player by name")
    parser.add_argument("--all-seasons", action="store_true", help="Audit all seasons (2024, 2025, 2026)")
    parser.add_argument("--output", type=str, help="Save detailed results to JSON file")
    
    args = parser.parse_args()
    
    if args.player:
        check_specific_player(args.season, args.player)
    elif args.all_seasons:
        all_results = []
        for season in [2024, 2025, 2026]:
            try:
                results = audit_season(season)
                print_audit_report(results)
                all_results.append(results)
            except Exception as e:
                logger.error(f"Failed to audit season {season}: {e}")
        
        if args.output:
            with open(args.output, "w") as f:
                json.dump(all_results, f, indent=2, default=str)
            logger.info(f"Saved detailed results to {args.output}")
    else:
        results = audit_season(args.season)
        print_audit_report(results)
        
        if args.output:
            with open(args.output, "w") as f:
                json.dump(results, f, indent=2, default=str)
            logger.info(f"Saved detailed results to {args.output}")


if __name__ == "__main__":
    main()
