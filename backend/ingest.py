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


BATTER_METRICS = [
    # Baseball Savant order: expected stats first
    ("xwoba", "xwOBA", "Hitting"),
    ("xba", "xBA", "Hitting"),
    ("xslg", "xSLG", "Hitting"),
    ("xiso", "xISO", "Hitting"),
    ("xobp", "xOBP", "Hitting"),
    # Quality of contact
    ("exit_velocity", "EV", "Hitting"),
    ("brl_percent", "Barrel%", "Hitting"),
    ("hard_hit_percent", "Hard-Hit%", "Hitting"),
    ("launch_angle_sweet_spot", "LA Sweet Spot%", "Hitting"),
    ("max_ev", "Max EV", "Hitting"),
    # Swing characteristics
    ("bat_speed", "Bat Speed", "Hitting"),
    ("squared_up_rate", "Squared-Up%", "Hitting"),
    ("swing_length", "Swing Length", "Hitting"),
    # Plate discipline (Savant order: Chase, Whiff, K, BB)
    ("chase_percent", "Chase%", "Hitting"),
    ("whiff_percent", "Whiff%", "Hitting"),
    ("k_percent", "K%", "Hitting"),
    ("bb_percent", "BB%", "Hitting"),
]

RUNNING_METRICS = [
    ("sprint_speed", "Sprint Speed", "Running"),
]

FIELDING_METRICS = [
    ("oaa", "Range (OAA)", "Fielding"),
    ("arm_value", "Arm Value", "Fielding"),
    ("arm_strength", "Arm Strength", "Fielding"),
]

PITCHER_METRICS = [
    # Expected stats
    ("xera", "xERA", "Pitching"),
    ("xwoba", "xwOBA", "Pitching"),
    ("xba", "xBA", "Pitching"),
    ("xslg", "xSLG", "Pitching"),
    ("xiso", "xISO", "Pitching"),
    ("xobp", "xOBP", "Pitching"),
    # Quality of contact against
    ("brl_percent", "Barrel%", "Pitching"),
    ("exit_velocity", "Avg EV Against", "Pitching"),
    ("hard_hit_percent", "Hard-Hit%", "Pitching"),
    ("max_ev", "Max EV Against", "Pitching"),
    # Plate discipline
    ("k_percent", "K%", "Pitching"),
    ("bb_percent", "BB%", "Pitching"),
    ("whiff_percent", "Whiff%", "Pitching"),
    ("chase_percent", "Chase%", "Pitching"),
    # Pitch characteristics
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

    if key in row:
        val = row[key]
        if pd.notna(val):
            try:
                f = float(val)
                if f != int(f):
                    return str(val)
                if f < 0 or f > 100:
                    return str(val)
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


def _fetch_mlb_standard_stats(player_ids: list[int], season: int) -> dict[int, dict[str, Any]]:
    """Fetch traditional stats from MLB Stats API for a list of player IDs.
    
    Returns a dict mapping player_id to their stats dict with keys like:
    - For hitters: avg, obp, slg, ops, hr, rbi, r, h, doubles, triples, bb, so, sb, cs, pa, ab
    - For pitchers: era, whip, wins, losses, saves, ip, h, r, er, hr, bb, so, k9, bb9, kbb, qs, g, gs
    """
    stats_by_player: dict[int, dict[str, Any]] = {}
    
    # MLB Stats API can handle multiple player IDs in one request
    # Split into batches of 50 to avoid URL length issues
    batch_size = 50
    for i in range(0, len(player_ids), batch_size):
        batch = player_ids[i:i + batch_size]
        ids_param = ",".join(str(pid) for pid in batch)
        
        try:
            # Fetch hitting stats
            hit_url = f"https://statsapi.mlb.com/api/v1/people"
            hit_params = {
                "personIds": ids_param,
                "hydrate": f"stats(type=season,season={season},group=hitting)",
            }
            hit_resp = requests.get(hit_url, params=hit_params, timeout=30)
            hit_resp.raise_for_status()
            hit_data = hit_resp.json()
            
            for person in hit_data.get("people", []):
                pid = person.get("id")
                if not pid:
                    continue
                
                # Extract hitting stats
                stats_list = person.get("stats", [])
                for stat_group in stats_list:
                    group_data = stat_group.get("group", {})
                    if isinstance(group_data, dict) and group_data.get("displayName") == "hitting":
                        for split in stat_group.get("splits", []):
                            stat = split.get("stat", {})
                            if stat:
                                stats_by_player[pid] = {
                                    "avg": stat.get("avg", ""),
                                    "obp": stat.get("obp", ""),
                                    "slg": stat.get("slg", ""),
                                    "ops": stat.get("ops", ""),
                                    "hr": stat.get("homeRuns", 0),
                                    "rbi": stat.get("rbi", 0),
                                    "r": stat.get("runs", 0),
                                    "h": stat.get("hits", 0),
                                    "doubles": stat.get("doubles", 0),
                                    "triples": stat.get("triples", 0),
                                    "bb": stat.get("baseOnBalls", 0),
                                    "so": stat.get("strikeOuts", 0),
                                    "sb": stat.get("stolenBases", 0),
                                    "cs": stat.get("caughtStealing", 0),
                                    "pa": stat.get("plateAppearances", 0),
                                    "ab": stat.get("atBats", 0),
                                    "player_type": "batter",
                                }
            
            # Fetch pitching stats
            pitch_url = f"https://statsapi.mlb.com/api/v1/people"
            pitch_params = {
                "personIds": ids_param,
                "hydrate": f"stats(type=season,season={season},group=pitching)",
            }
            pitch_resp = requests.get(pitch_url, params=pitch_params, timeout=30)
            pitch_resp.raise_for_status()
            pitch_data = pitch_resp.json()
            
            for person in pitch_data.get("people", []):
                pid = person.get("id")
                if not pid:
                    continue
                
                # Extract pitching stats
                stats_list = person.get("stats", [])
                for stat_group in stats_list:
                    group_data = stat_group.get("group", {})
                    if isinstance(group_data, dict) and group_data.get("displayName") == "pitching":
                        for split in stat_group.get("splits", []):
                            stat = split.get("stat", {})
                            if stat:
                                # If player already has hitting stats, they're two-way
                                existing = stats_by_player.get(pid, {})
                                existing.update({
                                    "era": stat.get("era", ""),
                                    "whip": stat.get("whip", ""),
                                    "wins": stat.get("wins", 0),
                                    "losses": stat.get("losses", 0),
                                    "saves": stat.get("saves", 0),
                                    "ip": stat.get("inningsPitched", ""),
                                    "h": stat.get("hits", 0),
                                    "r": stat.get("runs", 0),
                                    "er": stat.get("earnedRuns", 0),
                                    "hr": stat.get("homeRuns", 0),
                                    "bb": stat.get("baseOnBalls", 0),
                                    "so": stat.get("strikeOuts", 0),
                                    "k9": stat.get("strikeoutsPer9Inn", ""),
                                    "bb9": stat.get("walksPer9Inn", ""),
                                    "kbb": stat.get("strikeoutWalkRatio", ""),
                                    "qs": stat.get("qualityStarts", 0),
                                    "g": stat.get("gamesPlayed", 0),
                                    "gs": stat.get("gamesStarted", 0),
                                    "player_type": "two_way" if existing.get("player_type") == "batter" else "pitcher",
                                })
                                stats_by_player[pid] = existing
                                
        except Exception:
            logger.exception("Failed to fetch MLB stats for batch %d", i // batch_size)
            continue
    
    logger.info("Fetched MLB standard stats for %d players", len(stats_by_player))
    return stats_by_player


def _build_standard_stats_from_mlb(stats: dict[str, Any]) -> list[dict[str, str]]:
    """Convert MLB Stats API data to standard_stats JSON format."""
    result: list[dict[str, str]] = []
    
    # Hitting stats
    if stats.get("player_type") in ("batter", "two_way"):
        hitters = [
            ("avg", "AVG"), ("obp", "OBP"), ("slg", "SLG"), ("ops", "OPS"),
            ("hr", "HR"), ("rbi", "RBI"), ("r", "R"), ("h", "H"),
            ("doubles", "2B"), ("triples", "3B"), ("bb", "BB"), ("so", "SO"),
            ("sb", "SB"), ("cs", "CS"), ("pa", "PA"), ("ab", "AB"),
        ]
        for key, label in hitters:
            val = stats.get(key)
            if val is not None and val != "":
                # Format decimals properly
                if key in ("avg", "obp", "slg", "ops") and val != "":
                    try:
                        val_str = f"{float(val):.3f}"
                    except (ValueError, TypeError):
                        val_str = str(val)
                else:
                    val_str = str(int(val)) if isinstance(val, (int, float)) and float(val).is_integer() else str(val)
                result.append({"id": f"std-{label}", "label": label, "value": val_str})
    
    # Pitching stats
    if stats.get("player_type") in ("pitcher", "two_way"):
        pitchers = [
            ("era", "ERA"), ("whip", "WHIP"), ("wins", "W"), ("losses", "L"), ("saves", "SV"),
            ("ip", "IP"), ("h", "H"), ("r", "R"), ("er", "ER"), ("hr", "HR"),
            ("bb", "BB"), ("so", "SO"), ("k9", "K/9"), ("bb9", "BB/9"), ("kbb", "K/BB"),
            ("qs", "QS"), ("g", "G"), ("gs", "GS"),
        ]
        # Avoid duplicates for two-way players
        existing_labels = {s["label"] for s in result}
        for key, label in pitchers:
            if label in existing_labels:
                continue
            val = stats.get(key)
            if val is not None and val != "":
                if key in ("era", "whip"):
                    try:
                        val_str = f"{float(val):.2f}"
                    except (ValueError, TypeError):
                        val_str = str(val)
                elif key in ("k9", "bb9", "kbb"):
                    try:
                        val_str = f"{float(val):.2f}"
                    except (ValueError, TypeError):
                        val_str = str(val)
                else:
                    val_str = str(int(val)) if isinstance(val, (int, float)) and float(val).is_integer() else str(val)
                result.append({"id": f"std-{label}", "label": label, "value": val_str})
    
    return result


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


def merge_player_row(players: dict[int, dict[str, Any]], row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]], now: str, season: int, standard_lookup: Optional[dict[str, pd.Series]] = None, roster_lookup: Optional[dict[int, dict[str, str]]] = None) -> None:
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
            "season": season,
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


def build_snapshot_rows(season: int) -> list[dict[str, Any]]:
    now = datetime.now(UTC).isoformat()
    players: dict[int, dict[str, Any]] = {}

    logger.info("Fetching batter percentile ranks for season %s", season)
    try:
        batter_rows = statcast_batter_percentile_ranks(season)
        logger.info("Batter rows: %d", len(batter_rows))
        if batter_rows.empty:
            logger.warning("Empty batter DataFrame returned")
    except Exception:
        logger.exception("Failed to fetch batter percentile ranks")
        raise

    logger.info("Fetching pitcher percentile ranks for season %s", season)
    try:
        pitcher_rows = statcast_pitcher_percentile_ranks(season)
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

    # Fetch roster lookup from MLB API
    roster_lookup = _fetch_mlb_roster_lookup(season)
    
    # Process Statcast data to build player records
    batter_metrics = _all_metric_defs("batter")
    pitcher_metrics = _all_metric_defs("pitcher")
    
    skipped = 0
    for _, row in batter_rows.iterrows():
        try:
            merge_player_row(players, row, "batter", batter_metrics, now, season, None, roster_lookup)
        except Exception:
            skipped += 1
            logger.exception("Failed to process batter row")
    
    for _, row in pitcher_rows.iterrows():
        try:
            merge_player_row(players, row, "pitcher", pitcher_metrics, now, season, None, roster_lookup)
        except Exception:
            skipped += 1
            logger.exception("Failed to process pitcher row")
    
    # Fetch standard stats from MLB Stats API for all players
    all_player_ids = list(players.keys())
    logger.info("Fetching standard stats from MLB Stats API for %d players", len(all_player_ids))
    mlb_stats = _fetch_mlb_standard_stats(all_player_ids, season)
    
    # Attach standard stats to players
    with_std = 0
    for pid, stats in mlb_stats.items():
        if pid in players:
            players[pid]["standard_stats"] = _build_standard_stats_from_mlb(stats)
            with_std += 1
    
    logger.info("Attached standard stats to %d players", with_std)

    two_way = sum(1 for p in players.values() if p.get("player_type") == "two_way")
    logger.info(
        "Total players for %s: %d (batters: %d, pitchers: %d, two-way: %d, skipped rows: %d)",
        season,
        len(players),
        sum(1 for p in players.values() if p.get("player_type") == "batter"),
        sum(1 for p in players.values() if p.get("player_type") == "pitcher"),
        two_way,
        skipped,
    )

    return list(players.values())


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)

    fetch_all = os.environ.get("FETCH_ALL_TIME", "false").lower() == "true"
    end_season = _default_season()
    seasons_to_fetch = list(range(2015, end_season + 1)) if fetch_all else [_resolve_season()]

    for season in seasons_to_fetch:
        logger.info("=== Processing season %s ===", season)
        try:
            rows = build_snapshot_rows(season)
            if not rows:
                logger.error("No rows to upsert for %s.", season)
                continue

            batch_size = 150
            for i, batch in enumerate(chunks(rows, batch_size)):
                logger.info("Upserting batch %d (%d rows) for %s...", i + 1, len(batch), season)
                try:
                    client.table("player_snapshots").upsert(batch, on_conflict="id,season").execute()
                except Exception as e:
                    error_str = str(e)
                    if "no unique or exclusion constraint" in error_str or "ON CONFLICT" in error_str:
                        logger.warning("Upsert failed due to missing constraint, falling back to delete+insert")
                        # Fallback: delete existing rows for these (id, season) pairs, then insert
                        for row in batch:
                            client.table("player_snapshots").delete().eq("id", row["id"]).eq("season", row["season"]).execute()
                        client.table("player_snapshots").insert(batch).execute()
                    else:
                        raise

            logger.info("Successfully upserted %d player snapshots for %s.", len(rows), season)
        except Exception:
            logger.exception("Failed to process season %s", season)
            if not fetch_all:
                sys.exit(1)


if __name__ == "__main__":
    main()
