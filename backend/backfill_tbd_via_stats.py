"""Fallback team backfill for players whose team is still 'TBD' after the
roster-based backfill.

The roster endpoints only return current 40-man / active rosters, so traded
or DFA'd players from past seasons never resolve. This script instead asks
the season-stats endpoint, which returns the team(s) the player actually
appeared for, and patches the most-frequent / latest team back into Supabase.

Usage:
    python3 backfill_tbd_via_stats.py --from-year 2015 --to-year 2026
    python3 backfill_tbd_via_stats.py --season 2023 --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import os
from typing import Optional

import requests
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

PEOPLE_STATS_API = "https://statsapi.mlb.com/api/v1/people/{pid}/stats"
PEOPLE_API = "https://statsapi.mlb.com/api/v1/people/{pid}"

# Mirror app/team abbreviation normalization (DB uses CWS not CHW, etc).
TEAM_NAME_TO_ABBR = {
    "Arizona Diamondbacks": "ARI", "Atlanta Braves": "ATL", "Baltimore Orioles": "BAL",
    "Boston Red Sox": "BOS", "Chicago Cubs": "CHC", "Chicago White Sox": "CWS",
    "Cincinnati Reds": "CIN", "Cleveland Guardians": "CLE", "Cleveland Indians": "CLE",
    "Colorado Rockies": "COL", "Detroit Tigers": "DET", "Houston Astros": "HOU",
    "Kansas City Royals": "KC", "Los Angeles Angels": "LAA", "Los Angeles Dodgers": "LAD",
    "Miami Marlins": "MIA", "Milwaukee Brewers": "MIL", "Minnesota Twins": "MIN",
    "New York Mets": "NYM", "New York Yankees": "NYY", "Oakland Athletics": "OAK",
    "Athletics": "OAK", "Philadelphia Phillies": "PHI", "Pittsburgh Pirates": "PIT",
    "San Diego Padres": "SD", "Seattle Mariners": "SEA", "San Francisco Giants": "SF",
    "St. Louis Cardinals": "STL", "Tampa Bay Rays": "TB", "Texas Rangers": "TEX",
    "Toronto Blue Jays": "TOR", "Washington Nationals": "WSH",
}


def resolve_team(pid: int, season: int) -> Optional[tuple[str, str]]:
    """Returns (team_abbr, group) — group is "hitting" or "pitching" depending
    on which stats endpoint resolved first. Tries hitting then pitching."""
    for group in ("hitting", "pitching"):
        try:
            r = requests.get(
                PEOPLE_STATS_API.format(pid=pid),
                params={"stats": "season", "season": season, "group": group},
                timeout=15,
            )
            r.raise_for_status()
        except Exception:
            continue
        splits = (r.json().get("stats") or [{}])[0].get("splits") or []
        if not splits:
            continue
        # Last split = latest team in trade chain.
        team_name = splits[-1].get("team", {}).get("name", "")
        abbr = TEAM_NAME_TO_ABBR.get(team_name)
        if abbr:
            return abbr, group
    return None


def fetch_tbd_players(client, season: int) -> list[dict]:
    rows = (
        client.table("player_snapshots")
        .select("id,name,team,position,player_type")
        .eq("season", season)
        .eq("team", "TBD")
        .execute()
    )
    return rows.data or []


def fetch_empty_position_players(client, season: int) -> list[dict]:
    """Players with a team set but no fielding position. The stats endpoint
    can't return a position, so resolve via /people/{pid} primaryPosition."""
    rows = (
        client.table("player_snapshots")
        .select("id,name,team,position,player_type")
        .eq("season", season)
        .or_("position.is.null,position.eq.")
        .execute()
    )
    return [r for r in (rows.data or []) if not (r.get("position") or "").strip()]


def resolve_primary_position(pid: int) -> Optional[str]:
    try:
        r = requests.get(PEOPLE_API.format(pid=pid), timeout=15)
        r.raise_for_status()
    except Exception:
        return None
    people = r.json().get("people") or []
    if not people:
        return None
    pos = people[0].get("primaryPosition", {}).get("abbreviation", "")
    return pos or None


def fix_season(client, season: int, dry_run: bool) -> dict:
    tbd = fetch_tbd_players(client, season)
    no_pos = fetch_empty_position_players(client, season)
    if not tbd and not no_pos:
        logger.info("Season %s: nothing to patch", season)
        return {"season": season, "tbd": 0, "patched": 0, "no_pos": 0, "pos_patched": 0, "unresolved": []}

    patched = 0
    unresolved = []
    for p in tbd:
        pid = int(p["id"])
        resolved = resolve_team(pid, season)
        if not resolved:
            unresolved.append({"id": pid, "name": p.get("name", "")})
            continue
        team, _group = resolved
        update: dict = {"team": team}
        pos = resolve_primary_position(pid)
        if pos and not (p.get("position") or "").strip():
            update["position"] = pos
        logger.info("  %s (%s) → %s %s", p.get("name"), pid, team, pos or "")
        if not dry_run:
            client.table("player_snapshots").update(update).eq("id", pid).eq("season", season).execute()
        patched += 1

    # Players with a team but a blank fielding position. /people/{pid} returns
    # a primaryPosition for ~all players (P for pitchers, C/1B/SS/etc. for
    # position players), so this resolves cleanly.
    pos_patched = 0
    for p in no_pos:
        # Skip the TBD entries we already handled above.
        if any(t["id"] == p["id"] for t in tbd):
            continue
        pid = int(p["id"])
        pos = resolve_primary_position(pid)
        if not pos:
            unresolved.append({"id": pid, "name": p.get("name", ""), "reason": "no primaryPosition"})
            continue
        logger.info("  pos %s (%s) → %s", p.get("name"), pid, pos)
        if not dry_run:
            client.table("player_snapshots").update({"position": pos}).eq("id", pid).eq("season", season).execute()
        pos_patched += 1

    logger.info(
        "Season %s: %d TBD → %d patched, %d empty-pos → %d patched, %d unresolved",
        season, len(tbd), patched, len(no_pos), pos_patched, len(unresolved),
    )
    return {
        "season": season,
        "tbd": len(tbd),
        "patched": patched,
        "no_pos": len(no_pos),
        "pos_patched": pos_patched,
        "unresolved": unresolved,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--season", type=int)
    ap.add_argument("--from-year", type=int)
    ap.add_argument("--to-year", type=int)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.season:
        seasons = [args.season]
    elif args.from_year and args.to_year:
        seasons = list(range(args.from_year, args.to_year + 1))
    else:
        ap.error("Provide --season or --from-year + --to-year")

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    results = [fix_season(client, s, args.dry_run) for s in seasons]
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
