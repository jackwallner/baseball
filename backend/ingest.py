import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

import pandas as pd
import requests
from dotenv import load_dotenv
from pybaseball import (
    batting_stats,
    pitching_stats,
    statcast_batter_percentile_ranks,
    statcast_pitcher_percentile_ranks,
)
from supabase import create_client

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

# Lazy env-var access so tests can import the module without real secrets.
SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")


def _default_season() -> int:
    today = datetime.now(UTC)
    return today.year if today.month >= 4 else today.year - 1


def _resolve_season() -> int:
    raw = os.environ.get("STATCAST_SEASON")
    fallback = _default_season()
    if raw is None or raw == "":
        return fallback
    try:
        season = int(raw)
    except ValueError:
        logger.warning("Invalid STATCAST_SEASON=%r; using %d", raw, fallback)
        return fallback
    if season < 2015 or season > fallback:
        logger.warning("STATCAST_SEASON=%d out of range [2015, %d]; clamping to %d", season, fallback, fallback)
        return fallback
    return season


STATCAST_SEASON = _resolve_season()

BATTER_METRICS = [
    ("xwoba", "xwOBA", "Hitting"),
    ("xba", "xBA", "Hitting"),
    ("xslg", "xSLG", "Hitting"),
    ("xiso", "xISO", "Hitting"),
    ("xobp", "xOBP", "Hitting"),
    ("brl_percent", "Barrel%", "Hitting"),
    ("exit_velocity", "Avg EV", "Hitting"),
    ("max_ev", "Max EV", "Hitting"),
    ("hard_hit_percent", "Hard-Hit%", "Hitting"),
    ("k_percent", "K%", "Hitting"),
    ("bb_percent", "BB%", "Hitting"),
    ("whiff_percent", "Whiff%", "Hitting"),
    ("chase_percent", "Chase%", "Hitting"),
    ("bat_speed", "Bat Speed", "Hitting"),
    ("squared_up_rate", "Squared-Up%", "Hitting"),
    ("swing_length", "Swing Length", "Hitting"),
]

RUNNING_METRICS = [
    ("sprint_speed", "Sprint Speed", "Running"),
]

FIELDING_METRICS = [
    ("arm_strength", "Arm Strength", "Fielding"),
    ("oaa", "OAA", "Fielding"),
]

PITCHER_METRICS = [
    ("xera", "xERA", "Pitching"),
    ("xwoba", "xwOBA", "Pitching"),
    ("xba", "xBA", "Pitching"),
    ("xslg", "xSLG", "Pitching"),
    ("xiso", "xISO", "Pitching"),
    ("xobp", "xOBP", "Pitching"),
    ("brl_percent", "Barrel%", "Pitching"),
    ("exit_velocity", "Avg EV Against", "Pitching"),
    ("max_ev", "Max EV Against", "Pitching"),
    ("hard_hit_percent", "Hard-Hit%", "Pitching"),
    ("k_percent", "K%", "Pitching"),
    ("bb_percent", "BB%", "Pitching"),
    ("whiff_percent", "Whiff%", "Pitching"),
    ("chase_percent", "Chase%", "Pitching"),
    ("fb_velocity", "Fastball Velo", "Pitching"),
    ("fb_spin", "Fastball Spin", "Pitching"),
    ("curve_spin", "Curve Spin", "Pitching"),
]

# Standard (traditional) stats from FanGraphs leaderboards
HITTER_STANDARD_STATS = [
    ("AVG", "AVG"),
    ("OBP", "OBP"),
    ("SLG", "SLG"),
    ("OPS", "OPS"),
    ("HR", "HR"),
    ("RBI", "RBI"),
    ("R", "R"),
    ("H", "H"),
    ("2B", "2B"),
    ("3B", "3B"),
    ("BB", "BB"),
    ("SO", "SO"),
    ("SB", "SB"),
    ("CS", "CS"),
    ("PA", "PA"),
    ("AB", "AB"),
]

PITCHER_STANDARD_STATS = [
    ("ERA", "ERA"),
    ("WHIP", "WHIP"),
    ("W", "W"),
    ("L", "L"),
    ("SV", "SV"),
    ("IP", "IP"),
    ("H", "H"),
    ("R", "R"),
    ("ER", "ER"),
    ("HR", "HR"),
    ("BB", "BB"),
    ("SO", "SO"),
    ("K/9", "K/9"),
    ("BB/9", "BB/9"),
    ("K/BB", "K/BB"),
    ("QS", "QS"),
    ("G", "G"),
    ("GS", "GS"),
]


def _all_metric_defs(player_type: str) -> list[tuple[str, str, str]]:
    if player_type == "batter":
        return BATTER_METRICS + RUNNING_METRICS + FIELDING_METRICS
    return PITCHER_METRICS


def display_name(player_name: Any) -> str:
    value = str(player_name).strip()
    if "," not in value:
        return value
    parts = [p.strip() for p in value.split(",")]
    if len(parts) == 2:
        return f"{parts[1]} {parts[0]}"
    # More than one comma: assume last part is suffix (e.g. Jr., III)
    last = parts[0]
    first_and_suffix = ", ".join(parts[1:])
    return f"{first_and_suffix} {last}"


def percentile_value(value: Any) -> Optional[int]:
    try:
        if pd.isna(value):
            return None
        return max(0, min(100, int(round(float(value)))))
    except (ValueError, TypeError):
        return None


def raw_stat_value(row: pd.Series, key: str) -> Optional[str]:
    """Attempt to extract a raw stat value from the row.

    Percentile-rank DataFrames from pybaseball primarily contain percentiles (0-100).
    Some versions also include raw values in companion columns or the same column.
    We try multiple heuristics to find the actual baseball number.
    """
    # If a companion raw column exists (e.g. 'xwoba_value'), use it.
    raw_key = f"{key}_value"
    if raw_key in row:
        raw = row[raw_key]
        if pd.notna(raw):
            return str(raw)

    # If the key itself has a '_percentile' suffix, the bare key might be raw.
    base_key = key.replace("_percentile", "")
    if base_key != key and base_key in row:
        raw = row[base_key]
        if pd.notna(raw):
            return str(raw)

    # Heuristic: if the value in the key column has a decimal component,
    # it's almost certainly a raw stat, not an integer percentile.
    if key in row:
        val = row[key]
        if pd.notna(val):
            try:
                f = float(val)
                # Percentiles are integers 0-100. If it has decimals, it's raw.
                if f != int(f):
                    return str(val)
                # If outside 0-100, it's definitely raw.
                if f < 0 or f > 100:
                    return str(val)
                # For known raw-stat columns where values can legitimately be 0-100
                # (like exit_velocity ~96, bat_speed ~70), we still might miss them.
                # We accept that limitation here; standard stats fill the gap.
            except (ValueError, TypeError):
                pass
    return None


def build_metrics(row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]], player_id: int) -> list[dict[str, Any]]:
    metrics: list[dict[str, Any]] = []
    for key, label, category in metric_defs:
        if key not in row:
            logger.debug("Skipping metric %s/%s for player %s: column missing", label, category, player_id)
            continue
        percentile = percentile_value(row[key])
        if percentile is None:
            continue
        raw_value = raw_stat_value(row, key)
        value = raw_value if raw_value is not None else ""
        metrics.append(
            {
                "id": f"{player_type}-{player_id}-{key}",
                "label": label,
                "value": value,
                "percentile": percentile,
                "category": category,
            }
        )
    return metrics


def safe_player_id(row: pd.Series) -> Optional[int]:
    try:
        val = row["player_id"]
        if pd.isna(val):
            return None
        return int(val)
    except (KeyError, ValueError, TypeError):
        return None


def team_from_row(row: pd.Series) -> str:
    for col in ("team", "team_name", "player_team", "Team"):
        if col in row and pd.notna(row[col]):
            return normalize_team_abbr(str(row[col]))
    return "TBD"


def normalize_team_abbr(value: Any) -> str:
    raw = str(value).strip()
    if not raw:
        return "TBD"
    upper = raw.upper()
    aliases = {
        "ARIZONA DIAMONDBACKS": "ARI",
        "AZ": "ARI",
        "ATLANTA BRAVES": "ATL",
        "BALTIMORE ORIOLES": "BAL",
        "BOSTON RED SOX": "BOS",
        "CHICAGO CUBS": "CHC",
        "CHICAGO WHITE SOX": "CWS",
        "CHW": "CWS",
        "CHW0": "CWS",
        "CINCINNATI REDS": "CIN",
        "CLEVELAND GUARDIANS": "CLE",
        "CLEVELAND INDIANS": "CLE",
        "COLORADO ROCKIES": "COL",
        "DETROIT TIGERS": "DET",
        "HOUSTON ASTROS": "HOU",
        "KANSAS CITY ROYALS": "KC",
        "KCR": "KC",
        "LOS ANGELES ANGELS": "LAA",
        "ANAHEIM ANGELS": "LAA",
        "LOS ANGELES DODGERS": "LAD",
        "MIAMI MARLINS": "MIA",
        "MILWAUKEE BREWERS": "MIL",
        "MINNESOTA TWINS": "MIN",
        "NEW YORK METS": "NYM",
        "NEW YORK YANKEES": "NYY",
        "ATHLETICS": "OAK",
        "OAKLAND ATHLETICS": "OAK",
        "ATH": "OAK",
        "PHILADELPHIA PHILLIES": "PHI",
        "PITTSBURGH PIRATES": "PIT",
        "SAN DIEGO PADRES": "SD",
        "SDP": "SD",
        "SEATTLE MARINERS": "SEA",
        "SAN FRANCISCO GIANTS": "SF",
        "SFG": "SF",
        "ST. LOUIS CARDINALS": "STL",
        "ST LOUIS CARDINALS": "STL",
        "TAMPA BAY RAYS": "TB",
        "TBR": "TB",
        "TEXAS RANGERS": "TEX",
        "TORONTO BLUE JAYS": "TOR",
        "WASHINGTON NATIONALS": "WSH",
        "WSN": "WSH",
    }
    canonical = aliases.get(upper, upper)
    if canonical not in MLB_TEAM_WHITELIST:
        logger.warning("Unrecognized team string %r — falling back to TBD", value)
        return "TBD"
    return canonical


MLB_TEAM_WHITELIST: set[str] = {
    "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
    "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "OAK",
    "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB", "TEX", "TOR", "WSH",
}


def position_from_row(row: pd.Series, player_type: str) -> str:
    for col in ("position", "player_position", "pos", "Pos"):
        if col in row and pd.notna(row[col]):
            return str(row[col]).strip()
    return "Hitter" if player_type == "batter" else "Pitcher"


def handedness_from_row(row: pd.Series) -> str:
    bats = ""
    throws = ""
    for col in ("bats", "bat_side", "batting_side"):
        if col in row and pd.notna(row[col]):
            bats = str(row[col]).strip()
            break
    for col in ("throws", "throw_side", "throwing_side"):
        if col in row and pd.notna(row[col]):
            throws = str(row[col]).strip()
            break
    if bats and throws:
        return f"{bats}/{throws}"
    return bats or throws or ""


def _normalize_name(name: str) -> str:
    """Normalize a player name for cross-source matching."""
    return str(name).strip().lower().replace(".", "").replace("'", "")


def _build_standard_stats(row: pd.Series, stat_defs: list[tuple[str, str]]) -> list[dict[str, Any]]:
    """Build standard_stats JSON from a FanGraphs stats row."""
    stats: list[dict[str, Any]] = []
    for col, label in stat_defs:
        if col in row and pd.notna(row[col]):
            val = row[col]
            # Format numbers nicely
            if isinstance(val, (int, float)):
                if label in ("AVG", "OBP", "SLG", "OPS", "ERA", "WHIP"):
                    val_str = f"{float(val):.3f}"
                elif label in ("K/9", "BB/9", "K/BB"):
                    val_str = f"{float(val):.2f}"
                else:
                    val_str = str(int(val)) if float(val).is_integer() else str(float(val))
            else:
                val_str = str(val)
            stats.append({"id": f"std-{label}", "label": label, "value": val_str})
    return stats


def _fetch_standard_stats(season: int) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Fetch FanGraphs standard stats for hitters and pitchers."""
    logger.info("Fetching standard batting stats for season %s", season)
    try:
        bat = batting_stats(season, qual=100)
        logger.info("Standard batting rows: %d", len(bat))
    except Exception:
        logger.exception("Failed to fetch standard batting stats")
        bat = pd.DataFrame()

    logger.info("Fetching standard pitching stats for season %s", season)
    try:
        pitch = pitching_stats(season, qual=10)
        logger.info("Standard pitching rows: %d", len(pitch))
    except Exception:
        logger.exception("Failed to fetch standard pitching stats")
        pitch = pd.DataFrame()

    return bat, pitch


def _fetch_mlb_roster_lookup(season: int) -> dict[int, dict[str, str]]:
    lookup: dict[int, dict[str, str]] = {}
    try:
        teams_response = requests.get(
            "https://statsapi.mlb.com/api/v1/teams",
            params={"sportId": 1, "season": season},
            timeout=30,
        )
        teams_response.raise_for_status()
        teams = teams_response.json().get("teams", [])
    except Exception:
        logger.exception("Failed to fetch MLB teams")
        return lookup

    for team in teams:
        team_id = team.get("id")
        team_abbr = normalize_team_abbr(team.get("abbreviation") or team.get("teamCode") or team.get("fileCode") or team.get("name") or "")
        if not team_id or team_abbr == "TBD":
            continue
        for roster_type in ("active", "40Man"):
            try:
                roster_response = requests.get(
                    f"https://statsapi.mlb.com/api/v1/teams/{team_id}/roster",
                    params={"season": season, "rosterType": roster_type},
                    timeout=30,
                )
                roster_response.raise_for_status()
                for item in roster_response.json().get("roster", []):
                    person_id = item.get("person", {}).get("id")
                    if not person_id:
                        continue
                    position = item.get("position", {}).get("abbreviation") or ""
                    lookup[int(person_id)] = {"team": team_abbr, "position": str(position)}
            except Exception:
                logger.exception("Failed to fetch %s roster for team %s", roster_type, team_abbr)
    logger.info("MLB roster lookup rows: %d", len(lookup))
    return lookup


def merge_player_row(players: dict[int, dict[str, Any]], row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]], now: str, standard_lookup: Optional[dict[str, pd.Series]] = None, roster_lookup: Optional[dict[int, dict[str, str]]] = None) -> None:
    player_id = safe_player_id(row)
    if player_id is None:
        logger.warning("Skipping row with missing or invalid player_id: %s", row.to_dict())
        return

    metrics = build_metrics(row, player_type, metric_defs, player_id)
    if not metrics:
        return

    if player_id not in players:
        player_name = display_name(row.get("player_name", ""))
        norm_name = _normalize_name(player_name)
        standard_row = standard_lookup.get(norm_name) if standard_lookup else None
        standard_stats: list[dict[str, Any]] = []
        if standard_row is not None:
            stat_defs = PITCHER_STANDARD_STATS if player_type == "pitcher" else HITTER_STANDARD_STATS
            standard_stats = _build_standard_stats(standard_row, stat_defs)

        team = team_from_row(row)
        if team == "TBD" and standard_row is not None:
            team = team_from_row(standard_row)
        if team == "TBD" and roster_lookup and player_id in roster_lookup:
            team = normalize_team_abbr(roster_lookup[player_id].get("team", ""))
        position = position_from_row(row, player_type)
        if position in ("Hitter", "Pitcher") and standard_row is not None:
            position = position_from_row(standard_row, player_type)
        if position in ("Hitter", "Pitcher") and roster_lookup and player_id in roster_lookup:
            position = roster_lookup[player_id].get("position", position)

        players[player_id] = {
            "id": player_id,
            "name": player_name,
            "team": team,
            "position": position,
            "handedness": handedness_from_row(row),
            "image_url": f"https://img.mlbstatic.com/mlb-photos/image/upload/w_180,q_100/v1/people/{player_id}/headshot/67/current",
            "updated_at": now,
            "season": STATCAST_SEASON,
            "player_type": player_type,
            "source": "baseball_savant_percentile_rankings",
            "metrics": metrics,
            "standard_stats": standard_stats,
            "games": [],
        }
        return

    existing = players[player_id]
    existing["position"] = "Two-way"
    existing["player_type"] = "two_way"
    existing["metrics"].extend(metrics)


def chunks(lst: list, n: int) -> Iterator[list]:
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


def build_snapshot_rows() -> list[dict[str, Any]]:
    now = datetime.now(UTC).isoformat()
    players: dict[int, dict[str, Any]] = {}

    logger.info("Fetching batter percentile ranks for season %s", STATCAST_SEASON)
    try:
        batter_rows = statcast_batter_percentile_ranks(STATCAST_SEASON)
        logger.info("Batter rows: %d", len(batter_rows))
        if batter_rows.empty:
            logger.warning("Empty batter DataFrame returned")
    except Exception:
        logger.exception("Failed to fetch batter percentile ranks")
        raise

    logger.info("Fetching pitcher percentile ranks for season %s", STATCAST_SEASON)
    try:
        pitcher_rows = statcast_pitcher_percentile_ranks(STATCAST_SEASON)
        logger.info("Pitcher rows: %d", len(pitcher_rows))
        if pitcher_rows.empty:
            logger.warning("Empty pitcher DataFrame returned")
    except Exception:
        logger.exception("Failed to fetch pitcher percentile ranks")
        raise

    # Log available columns for debugging
    logger.info("Batter columns: %s", list(batter_rows.columns))
    logger.info("Pitcher columns: %s", list(pitcher_rows.columns))

    missing_batter = {m[0] for m in _all_metric_defs("batter")} - set(batter_rows.columns)
    missing_pitcher = {m[0] for m in _all_metric_defs("pitcher")} - set(pitcher_rows.columns)
    if missing_batter:
        logger.warning("Missing batter columns: %s", missing_batter)
    if missing_pitcher:
        logger.warning("Missing pitcher columns: %s", missing_pitcher)

    # Fetch standard stats and build name-keyed lookups
    bat_std, pitch_std = _fetch_standard_stats(STATCAST_SEASON)
    batter_lookup: dict[str, pd.Series] = {}
    pitcher_lookup: dict[str, pd.Series] = {}
    if not bat_std.empty and "Name" in bat_std.columns:
        for _, row in bat_std.iterrows():
            key = _normalize_name(row["Name"])
            batter_lookup[key] = row
    if not pitch_std.empty and "Name" in pitch_std.columns:
        for _, row in pitch_std.iterrows():
            key = _normalize_name(row["Name"])
            pitcher_lookup[key] = row

    logger.info("Standard stat lookups: batters=%d, pitchers=%d", len(batter_lookup), len(pitcher_lookup))
    roster_lookup = _fetch_mlb_roster_lookup(STATCAST_SEASON)

    batter_metrics = _all_metric_defs("batter")
    pitcher_metrics = _all_metric_defs("pitcher")

    skipped = 0
    for _, row in batter_rows.iterrows():
        try:
            merge_player_row(players, row, "batter", batter_metrics, now, batter_lookup, roster_lookup)
        except Exception:
            skipped += 1
            logger.exception("Failed to process batter row")

    for _, row in pitcher_rows.iterrows():
        try:
            merge_player_row(players, row, "pitcher", pitcher_metrics, now, pitcher_lookup, roster_lookup)
        except Exception:
            skipped += 1
            logger.exception("Failed to process pitcher row")

    # For two-way players, try to attach the opposite standard stats if missing
    for p in players.values():
        if p.get("player_type") == "two_way":
            norm = _normalize_name(p["name"])
            if not p.get("standard_stats"):
                # Prefer hitter stats for two-way unless they have only pitching metrics
                if norm in batter_lookup:
                    p["standard_stats"] = _build_standard_stats(batter_lookup[norm], HITTER_STANDARD_STATS)
                elif norm in pitcher_lookup:
                    p["standard_stats"] = _build_standard_stats(pitcher_lookup[norm], PITCHER_STANDARD_STATS)

    two_way = sum(1 for p in players.values() if p.get("player_type") == "two_way")
    with_std = sum(1 for p in players.values() if p.get("standard_stats"))
    logger.info(
        "Total players: %d (batters: %d, pitchers: %d, two-way: %d, skipped rows: %d, with standard stats: %d)",
        len(players),
        sum(1 for p in players.values() if p.get("player_type") == "batter"),
        sum(1 for p in players.values() if p.get("player_type") == "pitcher"),
        two_way,
        skipped,
        with_std,
    )

    return list(players.values())


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    rows = build_snapshot_rows()
    if not rows:
        logger.error("No rows to upsert. Exiting.")
        sys.exit(1)

    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)

    batch_size = 150
    for i, batch in enumerate(chunks(rows, batch_size)):
        logger.info("Upserting batch %d (%d rows)...", i + 1, len(batch))
        try:
            # supabase-py 2.x: upsert(data, on_conflict="column") is the documented API.
            # If postgrest-py changes this shape, the batch will fail loudly and exit non-zero.
            client.table("player_snapshots").upsert(batch, on_conflict="id").execute()
        except Exception:
            logger.exception("Batch %d failed", i + 1)
            sys.exit(1)

    logger.info(
        "Upserted %d Baseball Savant percentile player snapshots for %s",
        len(rows),
        STATCAST_SEASON,
    )


if __name__ == "__main__":
    main()
