"""Backfill team data for historical seasons where all players have team='TBD'.

Uses MLB Stats API rosters for the given season to patch team and position data.
Fetches all players from Supabase for a season, builds a roster lookup from MLB API,
then patches matching players. Only updates players where team == 'TBD'.

Usage:
    python3 backfill_team_data.py --season 2021
    python3 backfill_team_data.py --from-year 2020 --to-year 2025
    python3 backfill_team_data.py --season 2021 --dry-run
"""

import argparse
import json
import logging
import os
import sys
from typing import Optional

import requests
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

MLB_TEAMS_API = "https://statsapi.mlb.com/api/v1/teams"
MLB_ROSTER_API = "https://statsapi.mlb.com/api/v1/teams/{team_id}/roster"


def build_roster_lookup(season: int) -> dict[int, dict[str, str]]:
    """Build player_id -> {team, position} from MLB Stats API rosters for a season."""
    lookup: dict[int, dict[str, str]] = {}
    try:
        resp = requests.get(
            MLB_TEAMS_API,
            params={"sportId": 1, "season": season},
            timeout=30,
        )
        resp.raise_for_status()
        teams = resp.json().get("teams", [])
    except Exception:
        logger.exception("Failed to fetch MLB teams for season %s", season)
        return lookup

    for team in teams:
        team_id = team.get("id")
        if not team_id:
            continue
        # Use abbreviation first, fallback to teamCode/fileCode
        abbr = (
            team.get("abbreviation")
            or team.get("teamCode")
            or team.get("fileCode")
            or ""
        )
        if not abbr:
            continue

        for roster_type in ("active", "40Man"):
            try:
                r = requests.get(
                    MLB_ROSTER_API.format(team_id=team_id),
                    params={"season": season, "rosterType": roster_type},
                    timeout=30,
                )
                r.raise_for_status()
                for item in r.json().get("roster", []):
                    person = item.get("person", {})
                    pid = person.get("id")
                    if not pid:
                        continue
                    position = item.get("position", {}).get("abbreviation", "")
                    lookup[int(pid)] = {"team": abbr.upper(), "position": str(position)}
            except Exception:
                logger.exception(
                    "Failed to fetch %s roster for team %s season %s",
                    roster_type,
                    abbr,
                    season,
                )

    logger.info(
        "Built roster lookup for season %s: %d players across %d teams",
        season,
        len(lookup),
        len(teams),
    )
    return lookup


def normalize_team_abbr(value: str) -> str:
    """Match the backend's team normalization logic."""
    raw = str(value).strip().upper()
    if not raw:
        return "TBD"
    aliases = {
        "CWS": "CHW",
        "CUB": "CHC",
        "SDP": "SD",
        "SFG": "SF",
        "KCR": "KC",
        "TBR": "TB",
        "LAA": "LAA",
        "LAD": "LAD",
        "NYY": "NYY",
        "NYM": "NYM",
        "CHW": "CHW",
        "CHC": "CHC",
        "STL": "STL",
        "BOS": "BOS",
        "BAL": "BAL",
        "TOR": "TOR",
        "TEX": "TEX",
        "HOU": "HOU",
        "SEA": "SEA",
        "OAK": "OAK",
        "MIN": "MIN",
        "CLE": "CLE",
        "DET": "DET",
        "MIL": "MIL",
        "CIN": "CIN",
        "PIT": "PIT",
        "ATL": "ATL",
        "PHI": "PHI",
        "WSH": "WSH",
        "MIA": "MIA",
        "COL": "COL",
        "ARI": "ARI",
        "SD": "SD",
        "SF": "SF",
        "KC": "KC",
        "TB": "TB",
        "AZ": "ARI",
    }
    return aliases.get(raw, raw)


def fetch_players_for_season(client, season: int) -> list[dict]:
    """Fetch all player_snapshot rows for a season."""
    rows: list[dict] = []
    batch_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots")
            .select("id,season,team,position,metrics")
            .eq("season", season)
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
    return rows


def backfill_season(client, season: int, dry_run: bool = False) -> dict:
    """Patch team/position data for a single season."""
    players = fetch_players_for_season(client, season)
    logger.info("Season %s: loaded %d players from Supabase", season, len(players))

    # Count how many have TBD team
    tbd_count = sum(1 for p in players if p.get("team") == "TBD")
    logger.info("Season %s: %d players with team='TBD'", season, tbd_count)

    if tbd_count == 0:
        logger.info("Season %s: no TBD players, skipping", season)
        return {
            "season": season,
            "players": len(players),
            "tbd_players": 0,
            "roster_lookup_size": 0,
            "patched": 0,
            "dry_run": dry_run,
        }

    roster_lookup = build_roster_lookup(season)
    if not roster_lookup:
        logger.warning("Season %s: empty roster lookup, skipping", season)
        return {
            "season": season,
            "players": len(players),
            "tbd_players": tbd_count,
            "roster_lookup_size": 0,
            "patched": 0,
            "dry_run": dry_run,
        }

    patched = 0
    for p in players:
        pid = p["id"]
        if p.get("team") != "TBD":
            continue
        if pid not in roster_lookup:
            continue

        new_team = normalize_team_abbr(roster_lookup[pid]["team"])
        new_position = roster_lookup[pid]["position"]

        updates: dict[str, any] = {"team": new_team}
        if new_position and not p.get("position"):
            updates["position"] = new_position

        if not dry_run:
            client.table("player_snapshots").update(updates).eq("id", pid).eq("season", season).execute()
        patched += 1

    logger.info(
        "Season %s done: %d players patched (dry_run=%s)",
        season,
        patched,
        dry_run,
    )
    return {
        "season": season,
        "players": len(players),
        "tbd_players": tbd_count,
        "roster_lookup_size": len(roster_lookup),
        "patched": patched,
        "dry_run": dry_run,
    }


def main() -> int:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        logger.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing")
        return 1

    parser = argparse.ArgumentParser()
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--from-year", type=int, default=2020)
    parser.add_argument("--to-year", type=int, default=2025)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    seasons = [args.season] if args.season else list(range(args.from_year, args.to_year + 1))
    results = []
    for season in seasons:
        results.append(backfill_season(client, season, dry_run=args.dry_run))

    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
