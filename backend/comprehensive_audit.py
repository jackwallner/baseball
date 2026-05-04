"""Comprehensive audit of the entire StatScout database.

Checks every season, every team, every player, and every stat for:
- TBD teams (players missing team assignment)
- Zero percentiles with actual values
- Missing expected metrics per player type
- Missing standard stats
- Empty positions
- Incomplete data coverage

Usage:
    python3 comprehensive_audit.py
"""

import json
import logging
import os
import sys
from collections import defaultdict
from typing import Any

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Expected MLB teams
EXPECTED_TEAMS = {
    "ARI", "ATL", "BAL", "BOS", "CHC", "CHW", "CIN", "CLE", "COL",
    "DET", "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM",
    "NYY", "OAK", "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB",
    "TEX", "TOR", "WSH",
}

# Core metrics that should exist for each player type
BATTER_CORE_METRICS = {"xwOBA", "xSLG", "xBA", "K%", "BB%"}
PITCHER_CORE_METRICS = {"xwOBA", "xERA", "K%", "BB%", "Whiff%", "Chase%"}
RUNNING_CORE_METRICS = {"Sprint Speed"}
FIELDING_CORE_METRICS = {"Range (OAA)"}

STANDARD_STATS_EXPECTED = {"PA", "AB", "H", "HR", "BB", "SO", "AVG", "OBP", "SLG", "OPS"}


def fetch_all_seasons(client) -> list[int]:
    """Get all distinct seasons from player_snapshots."""
    rows = []
    batch_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots")
            .select("season")
            .range(offset, offset + batch_size - 1)
            .execute()
        )
        batch = resp.data or []
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < batch_size:
            break
        offset += batch_size

    seasons = sorted(set(r["season"] for r in rows if r.get("season")), reverse=True)
    logger.info("Found seasons: %s", seasons)
    return seasons


def fetch_all_players_for_season(client, season: int) -> list[dict]:
    """Fetch every player for a season."""
    players = []
    batch_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots")
            .select("id,name,team,position,player_type,metrics,standard_stats,season")
            .eq("season", season)
            .range(offset, offset + batch_size - 1)
            .execute()
        )
        batch = resp.data or []
        if not batch:
            break
        players.extend(batch)
        if len(batch) < batch_size:
            break
        offset += batch_size
    return players


def audit_season(client, season: int) -> dict[str, Any]:
    """Thoroughly audit a single season."""
    logger.info("Auditing season %s...", season)
    players = fetch_all_players_for_season(client, season)
    total = len(players)

    # Team analysis
    team_counts = defaultdict(int)
    tbd_players = []

    # Metric analysis
    zero_pct_issues = []
    missing_core_metrics = []
    missing_standard_stats = []
    empty_position = []

    # Per-team metric coverage
    team_metric_coverage = defaultdict(lambda: defaultdict(int))

    for p in players:
        pid = p["id"]
        name = p.get("name", "UNKNOWN")
        team = p.get("team", "TBD")
        position = p.get("position", "")
        ptype = p.get("player_type", "batter")

        team_counts[team] += 1
        if team == "TBD":
            tbd_players.append({"id": pid, "name": name})

        if not position or position.strip() == "":
            empty_position.append({"id": pid, "name": name, "team": team})

        # Parse metrics
        metrics = p.get("metrics") or []
        if isinstance(metrics, str):
            try:
                metrics = json.loads(metrics)
            except Exception:
                metrics = []

        metric_labels = {m.get("label") for m in metrics}
        metric_dict = {m.get("label"): m for m in metrics}

        # Check for zero percentiles with actual values
        for m in metrics:
            label = m.get("label", "")
            pct = m.get("percentile")
            val = m.get("value") or m.get("actual_value")
            if pct == 0 and val and str(val).strip() and str(val).strip() not in ("0.0%", "0%", "0.0", "0"):
                zero_pct_issues.append({
                    "id": pid,
                    "name": name,
                    "team": team,
                    "label": label,
                    "value": val,
                })

        # Track metric coverage per team
        for m in metrics:
            cat = m.get("category", "Unknown")
            label = m.get("label", "")
            team_metric_coverage[team][f"{cat}:{label}"] += 1

        # Check missing core metrics by player type
        expected = set()
        if ptype in ("batter", "two_way"):
            expected.update(BATTER_CORE_METRICS)
            expected.update(RUNNING_CORE_METRICS)
            expected.update(FIELDING_CORE_METRICS)
        if ptype in ("pitcher", "two_way"):
            expected.update(PITCHER_CORE_METRICS)

        missing = expected - metric_labels
        if missing:
            missing_core_metrics.append({
                "id": pid,
                "name": name,
                "team": team,
                "type": ptype,
                "missing": sorted(missing),
            })

        # Check standard stats
        std_stats = p.get("standard_stats") or []
        if isinstance(std_stats, str):
            try:
                std_stats = json.loads(std_stats)
            except Exception:
                std_stats = []
        std_labels = {s.get("label") for s in std_stats}
        missing_std = STANDARD_STATS_EXPECTED - std_labels
        if missing_std:
            missing_standard_stats.append({
                "id": pid,
                "name": name,
                "team": team,
                "missing": sorted(missing_std),
            })

    # Determine missing teams
    present_teams = set(team_counts.keys())
    missing_teams = EXPECTED_TEAMS - present_teams
    extra_teams = present_teams - EXPECTED_TEAMS - {"TBD", "MLB"}

    # Team player count distribution
    team_dist = {t: team_counts.get(t, 0) for t in sorted(EXPECTED_TEAMS)}
    avg_players = sum(team_dist.values()) / len(EXPECTED_TEAMS) if EXPECTED_TEAMS else 0
    low_teams = {t: c for t, c in team_dist.items() if c < avg_players * 0.5 and c > 0}

    return {
        "season": season,
        "total_players": total,
        "teams": {
            "present": sorted(present_teams),
            "missing_from_mlb_30": sorted(missing_teams),
            "unexpected": sorted(extra_teams),
            "tbd_count": len(tbd_players),
            "tbd_players": tbd_players[:20],  # Sample
            "team_distribution": dict(sorted(team_counts.items(), key=lambda x: -x[1])),
            "low_coverage_teams": low_teams,
            "avg_players_per_team": round(avg_players, 1),
        },
        "metrics": {
            "zero_percentile_with_value": {
                "count": len(zero_pct_issues),
                "samples": zero_pct_issues[:20],
            },
            "missing_core_metrics": {
                "count": len(missing_core_metrics),
                "samples": missing_core_metrics[:20],
            },
            "missing_standard_stats": {
                "count": len(missing_standard_stats),
                "samples": missing_standard_stats[:20],
            },
        },
        "players": {
            "empty_position_count": len(empty_position),
            "empty_position_samples": empty_position[:20],
        },
    }


def main() -> int:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        logger.error("Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY")
        return 1

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    seasons = fetch_all_seasons(client)

    all_results = []
    for season in seasons:
        result = audit_season(client, season)
        all_results.append(result)
        logger.info(
            "Season %s: %d players, %d TBD, %d zero-pct issues, %d missing core metrics, %d missing std stats, %d empty positions",
            season,
            result["total_players"],
            result["teams"]["tbd_count"],
            result["metrics"]["zero_percentile_with_value"]["count"],
            result["metrics"]["missing_core_metrics"]["count"],
            result["metrics"]["missing_standard_stats"]["count"],
            result["players"]["empty_position_count"],
        )

    # Summary across all seasons
    summary = {
        "total_seasons": len(seasons),
        "seasons": seasons,
        "total_players": sum(r["total_players"] for r in all_results),
        "total_tbd": sum(r["teams"]["tbd_count"] for r in all_results),
        "total_zero_pct": sum(r["metrics"]["zero_percentile_with_value"]["count"] for r in all_results),
        "total_missing_core": sum(r["metrics"]["missing_core_metrics"]["count"] for r in all_results),
        "total_missing_std": sum(r["metrics"]["missing_standard_stats"]["count"] for r in all_results),
        "total_empty_pos": sum(r["players"]["empty_position_count"] for r in all_results),
    }

    logger.info("=" * 60)
    logger.info("COMPREHENSIVE AUDIT SUMMARY")
    logger.info("=" * 60)
    logger.info("Total seasons: %d (%s)", summary["total_seasons"], summary["seasons"])
    logger.info("Total players: %d", summary["total_players"])
    logger.info("Total TBD teams: %d", summary["total_tbd"])
    logger.info("Total zero-percentile-with-value: %d", summary["total_zero_pct"])
    logger.info("Total missing core metrics: %d", summary["total_missing_core"])
    logger.info("Total missing standard stats: %d", summary["total_missing_std"])
    logger.info("Total empty positions: %d", summary["total_empty_pos"])

    # Write full report
    report = {
        "summary": summary,
        "seasons": all_results,
    }
    with open("comprehensive_audit_report.json", "w") as f:
        json.dump(report, f, indent=2, default=str)
    logger.info("Full report written to comprehensive_audit_report.json")

    return 0


if __name__ == "__main__":
    sys.exit(main())
