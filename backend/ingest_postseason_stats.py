"""Postseason stat lines for everyone still playing.

The MLB Stats API supplies the real postseason standard line directly, and the
following percentile rollup maps Statcast values onto the current regular
season curve because Baseball Savant publishes no postseason percentile
leaderboards. Keeping the two steps separate lets the standard board render as
soon as the line lands, before percentile enrichment completes.

Writes to player_postseason_stats, never to player_snapshots, for the same
reason the postseason game logs have their own table: the shipped app reads
player_snapshots filtered only by season, so an October row placed there shows
up on a regular-season leaderboard in a build nobody can patch.

The roster comes from player_postseason_game_logs rather than from a schedule
lookup: whoever actually appeared in a playoff game is exactly who has a
postseason line worth showing, and it keeps this script in step with whatever
the game-log ingest has managed to close out.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Optional

import requests
from dotenv import load_dotenv
from supabase import create_client

from ingest import _build_standard_stats_from_mlb
from tables import POSTSEASON_TABLE

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

STATS_TABLE = "player_postseason_stats"
PEOPLE_URL = "https://statsapi.mlb.com/api/v1/people"
# The MLB Stats API's postseason split. Without it the same request answers
# with the regular season, which is what keeps ingest.py's leaderboards clean
# and what would make this script pointless if it were forgotten.
POSTSEASON_GAME_TYPE = "P"
BATCH = 50


def _resolve_season() -> int:
    now = datetime.now(UTC)
    return now.year if now.month >= 4 else now.year - 1


def _client():
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)
    return create_client(url, key)


def _postseason_roster(client, season: int) -> dict[int, str]:
    """player_id -> most recent team, for everyone with a playoff game."""
    roster: dict[int, str] = {}
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table(POSTSEASON_TABLE)
            .select("player_id,team,game_date")
            .eq("season", season)
            .order("game_date", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )
        page = resp.data or []
        for row in page:
            pid = row.get("player_id")
            # Date-descending, so the first sighting is the newest and a player
            # traded mid-run keeps the club he is actually playing for.
            if pid is not None and pid not in roster:
                roster[pid] = row.get("team") or "TBD"
        if len(page) < page_size:
            break
        offset += page_size
    return roster


def _split_stat(person: dict, group: str) -> Optional[dict]:
    for stat_group in person.get("stats", []):
        group_data = stat_group.get("group", {})
        if not isinstance(group_data, dict) or group_data.get("displayName") != group:
            continue
        for split in stat_group.get("splits", []):
            stat = split.get("stat", {})
            if stat:
                return stat
    return None


def _fetch_group(player_ids: list[int], season: int, group: str) -> dict[int, dict]:
    """One hydrated people call for a batch, restricted to the postseason."""
    out: dict[int, dict] = {}
    params = {
        "personIds": ",".join(str(p) for p in player_ids),
        "hydrate": (
            f"stats(type=season,season={season},group={group},"
            f"gameType={POSTSEASON_GAME_TYPE})"
        ),
    }
    try:
        resp = requests.get(PEOPLE_URL, params=params, timeout=30)
        resp.raise_for_status()
        payload = resp.json()
    except Exception:
        logger.exception("people lookup failed for %s batch", group)
        return out

    for person in payload.get("people", []):
        pid = person.get("id")
        if pid is None:
            continue
        out[pid] = {
            "name": person.get("fullName") or "",
            "position": (person.get("primaryPosition") or {}).get("abbreviation") or "",
            "stat": _split_stat(person, group),
        }
    return out


def _fetch_fielding_group(player_ids: list[int], season: int) -> dict[int, dict]:
    """Fetch and total postseason fielding splits across positions."""
    out: dict[int, dict] = {}
    params = {
        "personIds": ",".join(str(p) for p in player_ids),
        "hydrate": (
            f"stats(type=season,season={season},group=fielding,"
            f"gameType={POSTSEASON_GAME_TYPE})"
        ),
    }
    try:
        resp = requests.get(PEOPLE_URL, params=params, timeout=30)
        resp.raise_for_status()
        payload = resp.json()
    except Exception:
        logger.exception("people lookup failed for fielding batch")
        return out

    for person in payload.get("people", []):
        pid = person.get("id")
        if pid is None:
            continue

        totals = {"e": 0, "a": 0, "po": 0, "dp": 0, "gf": 0}
        found = False
        for stat_group in person.get("stats", []):
            group_data = stat_group.get("group", {})
            if not isinstance(group_data, dict) or group_data.get("displayName") != "fielding":
                continue
            for split in stat_group.get("splits", []):
                stat = split.get("stat", {})
                if not stat:
                    continue
                position = (split.get("position") or {}).get("abbreviation")
                if position == "DH":
                    continue
                found = True
                totals["e"] += int(stat.get("errors", 0) or 0)
                totals["a"] += int(stat.get("assists", 0) or 0)
                totals["po"] += int(stat.get("putOuts", 0) or 0)
                totals["dp"] += int(stat.get("doublePlays", 0) or 0)
                totals["gf"] += int(stat.get("games", 0) or 0)

        if found:
            chances = totals["po"] + totals["a"] + totals["e"]
            totals["fpct"] = (
                f"{(totals['po'] + totals['a']) / chances:.3f}" if chances else ""
            )
            out[pid] = {
                "name": person.get("fullName") or "",
                "position": (person.get("primaryPosition") or {}).get("abbreviation") or "",
                "stats": totals,
            }
    return out


def _hitting_fields(stat: dict) -> dict[str, Any]:
    return {
        "avg": stat.get("avg", ""), "obp": stat.get("obp", ""),
        "slg": stat.get("slg", ""), "ops": stat.get("ops", ""),
        "hr": stat.get("homeRuns", 0), "rbi": stat.get("rbi", 0),
        "r": stat.get("runs", 0), "h": stat.get("hits", 0),
        "doubles": stat.get("doubles", 0), "triples": stat.get("triples", 0),
        "bb": stat.get("baseOnBalls", 0), "so": stat.get("strikeOuts", 0),
        "sb": stat.get("stolenBases", 0), "cs": stat.get("caughtStealing", 0),
        "pa": stat.get("plateAppearances", 0), "ab": stat.get("atBats", 0),
        "g_bat": stat.get("gamesPlayed", 0),
    }


def _pitching_fields(stat: dict) -> dict[str, Any]:
    # p_-prefixed, so a two-way player's batting H/R/HR/BB/SO survive alongside
    # the line he allowed. Sharing the bare keys is what corrupted those players
    # on the regular-season boards.
    return {
        "era": stat.get("era", ""), "whip": stat.get("whip", ""),
        "wins": stat.get("wins", 0), "losses": stat.get("losses", 0),
        "saves": stat.get("saves", 0), "ip": stat.get("inningsPitched", ""),
        "p_h": stat.get("hits", 0), "p_r": stat.get("runs", 0),
        "er": stat.get("earnedRuns", 0), "p_hr": stat.get("homeRuns", 0),
        "p_bb": stat.get("baseOnBalls", 0), "p_so": stat.get("strikeOuts", 0),
        "g": stat.get("gamesPlayed", 0), "gs": stat.get("gamesStarted", 0),
        "bf": stat.get("battersFaced", 0),
    }


def build_rows(
    season: int,
    roster: dict[int, str],
    hitting: dict,
    pitching: dict,
    fielding: Optional[dict] = None,
) -> list[dict]:
    """Assemble one upsertable row per player who has any postseason line.

    This ingest step intentionally leaves ``metrics`` to the enrichment step;
    standard stats are immediately usable while the percentile rollup runs.
    """
    rows: list[dict] = []
    fielding = fielding or {}
    for pid, team in sorted(roster.items()):
        hit = hitting.get(pid) or {}
        pit = pitching.get(pid) or {}
        fld = fielding.get(pid) or {}
        hit_stat = hit.get("stat")
        pit_stat = pit.get("stat")
        field_stats = fld.get("stats") or {}
        if not hit_stat and not pit_stat and not field_stats:
            continue

        if hit_stat and pit_stat:
            player_type = "two_way"
        elif pit_stat:
            player_type = "pitcher"
        else:
            player_type = "batter"

        merged: dict[str, Any] = {"player_type": player_type}
        if hit_stat:
            merged.update(_hitting_fields(hit_stat))
        if pit_stat:
            merged.update(_pitching_fields(pit_stat))
        merged.update(field_stats)

        rows.append({
            "id": pid,
            "season": season,
            "name": hit.get("name") or pit.get("name") or fld.get("name") or "",
            "team": team,
            "position": hit.get("position") or pit.get("position") or fld.get("position") or "",
            "player_type": player_type,
            "standard_stats": _build_standard_stats_from_mlb(merged),
        })
    return rows


def _upsert(client, rows: list[dict]) -> None:
    if not rows:
        return
    for i in range(0, len(rows), 200):
        batch = rows[i:i + 200]
        try:
            client.table(STATS_TABLE).upsert(batch, on_conflict="id,season").execute()
        except Exception:
            logger.exception("Upsert into %s failed at %d", STATS_TABLE, i)
            raise


def run() -> None:
    season = _resolve_season()
    client = _client()

    roster = _postseason_roster(client, season)
    if not roster:
        logger.info("No postseason games ingested for %s yet; nothing to do.", season)
        return

    logger.info("Fetching postseason lines for %d players", len(roster))
    ids = sorted(roster)
    hitting: dict[int, dict] = {}
    pitching: dict[int, dict] = {}
    fielding: dict[int, dict] = {}
    for i in range(0, len(ids), BATCH):
        batch = ids[i:i + BATCH]
        hitting.update(_fetch_group(batch, season, "hitting"))
        pitching.update(_fetch_group(batch, season, "pitching"))
        fielding.update(_fetch_fielding_group(batch, season))

    rows = build_rows(season, roster, hitting, pitching, fielding)
    _upsert(client, rows)
    logger.info("Done. Upserted %d postseason stat lines.", len(rows))


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    run()
