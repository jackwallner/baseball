"""
Enhanced ingest script that fetches both percentile rankings AND actual values.

This version fetches from multiple pybaseball endpoints to get actual stat values
to display alongside percentiles (e.g., "95.4 mph · 100th percentile").
"""

import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

import pandas as pd
import requests
from dotenv import load_dotenv
from pybaseball import (
    statcast_batter_percentile_ranks,
    statcast_pitcher_percentile_ranks,
    statcast_sprint_speed,
    statcast_batter_expected_stats,
    statcast_batter_exitvelo_barrels,
    statcast_pitcher_expected_stats,
    statcast_pitcher_exitvelo_barrels,
    statcast_pitcher_pitch_arsenal,
)
from pybaseball.statcast_fielding import statcast_outs_above_average
from supabase import create_client
from statcast_aggregator import build_complete_player_stats

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

DEFAULT_SEASON = datetime.now(UTC).year if datetime.now(UTC).month >= 4 else datetime.now(UTC).year - 1

MLB_TEAM_WHITELIST: set[str] = {
    "ARI", "ATL", "BAL", "BOS", "CHC", "CWS", "CIN", "CLE", "COL", "DET",
    "HOU", "KC", "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY", "OAK",
    "PHI", "PIT", "SD", "SEA", "SF", "STL", "TB", "TEX", "TOR", "WSH",
}

BATTER_METRICS = [
    ("xwoba", "xwOBA", "Hitting"),
    ("xba", "xBA", "Hitting"),
    ("xslg", "xSLG", "Hitting"),
    ("xiso", "xISO", "Hitting"),
    ("xobp", "xOBP", "Hitting"),
    ("exit_velocity", "EV", "Hitting"),
    ("brl_percent", "Barrel%", "Hitting"),
    ("hard_hit_percent", "Hard-Hit%", "Hitting"),
    ("launch_angle_sweet_spot", "LA Sweet Spot%", "Hitting"),
    ("max_ev", "Max EV", "Hitting"),
    ("bat_speed", "Bat Speed", "Hitting"),
    ("squared_up_rate", "Squared-Up%", "Hitting"),
    ("swing_length", "Swing Length", "Hitting"),
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
    ("xera", "xERA", "Pitching"),
    ("xwoba", "xwOBA", "Pitching"),
    ("xba", "xBA", "Pitching"),
    ("xslg", "xSLG", "Pitching"),
    ("xiso", "xISO", "Pitching"),
    ("xobp", "xOBP", "Pitching"),
    ("brl_percent", "Barrel%", "Pitching"),
    ("exit_velocity", "Avg EV Against", "Pitching"),
    ("hard_hit_percent", "Hard-Hit%", "Pitching"),
    ("max_ev", "Max EV Against", "Pitching"),
    ("k_percent", "K%", "Pitching"),
    ("bb_percent", "BB%", "Pitching"),
    ("whiff_percent", "Whiff%", "Pitching"),
    ("chase_percent", "Chase%", "Pitching"),
    ("fb_velocity", "Fastball Velo", "Pitching"),
    ("fb_spin", "Fastball Spin", "Pitching"),
    ("curve_spin", "Curve Spin", "Pitching"),
]


def _resolve_season() -> int:
    raw = os.environ.get("STATCAST_SEASON")
    if raw is None or raw == "":
        return DEFAULT_SEASON
    try:
        season = int(raw)
    except ValueError:
        return DEFAULT_SEASON
    if season < 2015 or season > DEFAULT_SEASON:
        return DEFAULT_SEASON
    return season


def display_name(player_name: Any) -> str:
    value = str(player_name).strip()
    if "," not in value:
        return value
    parts = [p.strip() for p in value.split(",")]
    if len(parts) == 2:
        return f"{parts[1]} {parts[0]}"
    last = parts[0]
    first_and_suffix = ", ".join(parts[1:])
    return f"{first_and_suffix} {last}"


def normalize_team_abbr(value: Any) -> str:
    raw = str(value).strip()
    if not raw:
        return "TBD"
    upper = raw.upper()
    aliases = {
        "ARIZONA DIAMONDBACKS": "ARI", "AZ": "ARI",
        "ATLANTA BRAVES": "ATL",
        "BALTIMORE ORIOLES": "BAL",
        "BOSTON RED SOX": "BOS",
        "CHICAGO CUBS": "CHC",
        "CHICAGO WHITE SOX": "CWS", "CHW": "CWS", "CHW0": "CWS",
        "CINCINNATI REDS": "CIN",
        "CLEVELAND GUARDIANS": "CLE", "CLEVELAND INDIANS": "CLE",
        "COLORADO ROCKIES": "COL",
        "DETROIT TIGERS": "DET",
        "HOUSTON ASTROS": "HOU",
        "KANSAS CITY ROYALS": "KC", "KCR": "KC",
        "LOS ANGELES ANGELS": "LAA", "ANAHEIM ANGELS": "LAA",
        "LOS ANGELES DODGERS": "LAD",
        "MIAMI MARLINS": "MIA",
        "MILWAUKEE BREWERS": "MIL",
        "MINNESOTA TWINS": "MIN",
        "NEW YORK METS": "NYM",
        "NEW YORK YANKEES": "NYY",
        "OAKLAND ATHLETICS": "OAK",
        "PHILADELPHIA PHILLIES": "PHI",
        "PITTSBURGH PIRATES": "PIT",
        "SAN DIEGO PADRES": "SD", "SDP": "SD",
        "SAN FRANCISCO GIANTS": "SF", "SFG": "SF",
        "SEATTLE MARINERS": "SEA",
        "ST LOUIS CARDINALS": "STL", "ST. LOUIS CARDINALS": "STL",
        "TAMPA BAY RAYS": "TB", "TBR": "TB",
        "TEXAS RANGERS": "TEX",
        "TORONTO BLUE JAYS": "TOR",
        "WASHINGTON NATIONALS": "WSH",
    }
    canonical = aliases.get(upper, upper)
    if canonical not in MLB_TEAM_WHITELIST:
        logger.warning("Unrecognized team string %r — falling back to TBD", value)
        return "TBD"
    return canonical


def percentile_value(value: Any) -> Optional[int]:
    try:
        if pd.isna(value):
            return None
        return max(0, min(100, int(round(float(value)))))
    except (ValueError, TypeError):
        return None


def safe_player_id(row: pd.Series) -> Optional[int]:
    try:
        val = row.get("player_id") or row.get("resp_fielder_id")
        if pd.isna(val):
            return None
        return int(val)
    except (KeyError, ValueError, TypeError):
        return None


def team_from_row(row: pd.Series) -> str:
    for col in ("team", "team_name", "player_team", "Team", "display_team_name"):
        if col in row and pd.notna(row[col]):
            return normalize_team_abbr(str(row[col]))
    return "TBD"


def position_from_row(row: pd.Series) -> str:
    for col in ("position", "primary_pos_formatted", "pos"):
        if col in row and pd.notna(row[col]):
            return str(row[col])
    return ""


class ActualValueStore:
    """Pre-fetches and stores all actual values for efficient lookup."""

    def __init__(self, season: int):
        self.season = season
        self._data: dict[str, dict[int, dict[str, Any]]] = {}
        self._prefetch_all()

    def _prefetch_all(self):
        """Prefetch all actual value data from all sources."""
        logger.info("Prefetching all actual value data for season %s...", self.season)

        # Batter expected stats (xwOBA, xBA, xSLG)
        try:
            df = statcast_batter_expected_stats(self.season, minPA=100)
            df["player_id"] = pd.to_numeric(df["player_id"], errors="coerce")
            self._data["batter_expected"] = {}
            for _, row in df.iterrows():
                pid = int(row["player_id"]) if pd.notna(row["player_id"]) else None
                if pid:
                    self._data["batter_expected"][pid] = {
                        "est_woba": row.get("est_woba"),
                        "est_ba": row.get("est_ba"),
                        "est_slg": row.get("est_slg"),
                    }
            logger.info("Loaded %d batter expected stats", len(self._data["batter_expected"]))
        except Exception as e:
            logger.warning("Failed to load batter expected stats: %s", e)
            self._data["batter_expected"] = {}

        # Batter exit velocity
        try:
            df = statcast_batter_exitvelo_barrels(self.season, minBBE=100)
            df["player_id"] = pd.to_numeric(df["player_id"], errors="coerce")
            self._data["batter_exitvelo"] = {}
            for _, row in df.iterrows():
                pid = int(row["player_id"]) if pd.notna(row["player_id"]) else None
                if pid:
                    self._data["batter_exitvelo"][pid] = {
                        "avg_hit_speed": row.get("avg_hit_speed"),
                        "brl_percent": row.get("brl_percent"),
                        "hard_hit_percent": row.get("ev95percent"),
                        "max_hit_speed": row.get("max_hit_speed"),
                        "anglesweetspotpercent": row.get("anglesweetspotpercent"),
                    }
            logger.info("Loaded %d batter exit velo stats", len(self._data["batter_exitvelo"]))
        except Exception as e:
            logger.warning("Failed to load batter exit velo: %s", e)
            self._data["batter_exitvelo"] = {}

        # Sprint speed
        try:
            df = statcast_sprint_speed(self.season, min_opp=25)
            df["player_id"] = pd.to_numeric(df["player_id"], errors="coerce")
            self._data["sprint_speed"] = {}
            for _, row in df.iterrows():
                pid = int(row["player_id"]) if pd.notna(row["player_id"]) else None
                if pid:
                    self._data["sprint_speed"][pid] = {
                        "sprint_speed": row.get("sprint_speed"),
                        "hp_to_1b": row.get("hp_to_1b"),
                    }
            logger.info("Loaded %d sprint speed stats", len(self._data["sprint_speed"]))
        except Exception as e:
            logger.warning("Failed to load sprint speed: %s", e)
            self._data["sprint_speed"] = {}

        # Outs above average (fielding)
        try:
            df = statcast_outs_above_average(self.season, pos="all", min_att=25)
            df["player_id"] = pd.to_numeric(df["player_id"], errors="coerce")
            self._data["oaa"] = {}
            for _, row in df.iterrows():
                pid = int(row["player_id"]) if pd.notna(row["player_id"]) else None
                if pid:
                    self._data["oaa"][pid] = {
                        "outs_above_average": row.get("outs_above_average"),
                        "fielding_runs_prevented": row.get("fielding_runs_prevented"),
                    }
            logger.info("Loaded %d OAA stats", len(self._data["oaa"]))
        except Exception as e:
            logger.warning("Failed to load OAA: %s", e)
            self._data["oaa"] = {}

        # Pitcher expected stats
        try:
            df = statcast_pitcher_expected_stats(self.season, minPA=50)
            df["player_id"] = pd.to_numeric(df["player_id"], errors="coerce")
            self._data["pitcher_expected"] = {}
            for _, row in df.iterrows():
                pid = int(row["player_id"]) if pd.notna(row["player_id"]) else None
                if pid:
                    self._data["pitcher_expected"][pid] = {
                        "xera": row.get("xera"),
                        "est_woba": row.get("est_woba"),
                        "est_ba": row.get("est_ba"),
                        "est_slg": row.get("est_slg"),
                    }
            logger.info("Loaded %d pitcher expected stats", len(self._data["pitcher_expected"]))
        except Exception as e:
            logger.warning("Failed to load pitcher expected stats: %s", e)
            self._data["pitcher_expected"] = {}

        # Pitcher exit velocity against
        try:
            df = statcast_pitcher_exitvelo_barrels(self.season, minBBE=50)
            df["player_id"] = pd.to_numeric(df["player_id"], errors="coerce")
            self._data["pitcher_exitvelo"] = {}
            for _, row in df.iterrows():
                pid = int(row["player_id"]) if pd.notna(row["player_id"]) else None
                if pid:
                    self._data["pitcher_exitvelo"][pid] = {
                        "avg_hit_speed": row.get("avg_hit_speed"),
                        "brl_percent": row.get("brl_percent"),
                        "ev95percent": row.get("ev95percent"),
                        "max_hit_speed": row.get("max_hit_speed"),
                    }
            logger.info("Loaded %d pitcher exit velo stats", len(self._data["pitcher_exitvelo"]))
        except Exception as e:
            logger.warning("Failed to load pitcher exit velo: %s", e)
            self._data["pitcher_exitvelo"] = {}

        # Pitcher arsenal
        try:
            df = statcast_pitcher_pitch_arsenal(self.season, minP=100)
            df["pitcher"] = pd.to_numeric(df["pitcher"], errors="coerce")
            self._data["pitcher_arsenal"] = {}
            for _, row in df.iterrows():
                pid = int(row["pitcher"]) if pd.notna(row["pitcher"]) else None
                if pid:
                    self._data["pitcher_arsenal"][pid] = {
                        "ff_avg_speed": row.get("ff_avg_speed"),
                    }
            logger.info("Loaded %d pitcher arsenal stats", len(self._data["pitcher_arsenal"]))
        except Exception as e:
            logger.warning("Failed to load pitcher arsenal: %s", e)
            self._data["pitcher_arsenal"] = {}

        # Fetch aggregated statcast data (bat speed, swing length, plate discipline, spin rates)
        try:
            logger.info("Fetching aggregated Statcast data (this may take a few minutes)...")
            batter_agg, pitcher_agg = build_complete_player_stats(self.season)

            # Store batter aggregated stats
            self._data["batter_agg"] = {}
            if not batter_agg.empty:
                for _, row in batter_agg.iterrows():
                    pid = int(row["player_id"])
                    self._data["batter_agg"][pid] = {
                        "bat_speed": row.get("bat_speed"),
                        "swing_length": row.get("swing_length"),
                        "whiff_percent": row.get("whiff_percent"),
                        "chase_percent": row.get("chase_percent"),
                    }
                logger.info("Loaded %d batter aggregated stats", len(self._data["batter_agg"]))

            # Store pitcher aggregated stats
            self._data["pitcher_agg"] = {}
            if not pitcher_agg.empty:
                for _, row in pitcher_agg.iterrows():
                    pid = int(row["player_id"])
                    self._data["pitcher_agg"][pid] = {
                        "avg_spin_rate": row.get("avg_spin_rate"),
                        "fastball_spin": row.get("fastball_spin"),
                        "breaking_spin": row.get("breaking_spin"),
                        "offspeed_spin": row.get("offspeed_spin"),
                    }
                logger.info("Loaded %d pitcher aggregated stats", len(self._data["pitcher_agg"]))
        except Exception as e:
            logger.warning("Failed to load aggregated Statcast data: %s", e)
            self._data["batter_agg"] = {}
            self._data["pitcher_agg"] = {}

    def get_value(self, player_id: int, metric_key: str, player_type: str) -> Optional[str]:
        """Get formatted actual value for a metric."""
        value = None
        unit = ""

        try:
            if metric_key == "xwoba":
                src = self._data["batter_expected"] if player_type == "batter" else self._data["pitcher_expected"]
                if player_id in src:
                    v = src[player_id].get("est_woba")
                    if pd.notna(v):
                        value = f"{v:.3f}"

            elif metric_key == "xba":
                src = self._data["batter_expected"] if player_type == "batter" else self._data["pitcher_expected"]
                if player_id in src:
                    v = src[player_id].get("est_ba")
                    if pd.notna(v):
                        value = f"{v:.3f}"

            elif metric_key == "xslg":
                src = self._data["batter_expected"] if player_type == "batter" else self._data["pitcher_expected"]
                if player_id in src:
                    v = src[player_id].get("est_slg")
                    if pd.notna(v):
                        value = f"{v:.3f}"

            elif metric_key == "exit_velocity":
                src = self._data["batter_exitvelo"] if player_type == "batter" else self._data["pitcher_exitvelo"]
                if player_id in src:
                    v = src[player_id].get("avg_hit_speed")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = " mph"

            elif metric_key == "brl_percent":
                src = self._data["batter_exitvelo"] if player_type == "batter" else self._data["pitcher_exitvelo"]
                if player_id in src:
                    v = src[player_id].get("brl_percent")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = "%"

            elif metric_key == "hard_hit_percent":
                src = self._data["batter_exitvelo"] if player_type == "batter" else self._data["pitcher_exitvelo"]
                if player_id in src:
                    v = src[player_id].get("ev95percent")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = "%"

            elif metric_key == "max_ev":
                src = self._data["batter_exitvelo"] if player_type == "batter" else self._data["pitcher_exitvelo"]
                if player_id in src:
                    v = src[player_id].get("max_hit_speed")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = " mph"

            elif metric_key == "launch_angle_sweet_spot":
                if player_id in self._data["batter_exitvelo"]:
                    v = self._data["batter_exitvelo"][player_id].get("anglesweetspotpercent")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = "%"

            elif metric_key == "sprint_speed":
                if player_id in self._data["sprint_speed"]:
                    v = self._data["sprint_speed"][player_id].get("sprint_speed")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = " ft/s"

            elif metric_key == "oaa":
                if player_id in self._data["oaa"]:
                    v = self._data["oaa"][player_id].get("outs_above_average")
                    if pd.notna(v):
                        value = f"{int(v):+d}"

            elif metric_key == "xera":
                if player_id in self._data["pitcher_expected"]:
                    v = self._data["pitcher_expected"][player_id].get("xera")
                    if pd.notna(v):
                        value = f"{v:.2f}"

            elif metric_key == "fb_velocity":
                if player_id in self._data["pitcher_arsenal"]:
                    v = self._data["pitcher_arsenal"][player_id].get("ff_avg_speed")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = " mph"

            elif metric_key == "bat_speed":
                if player_id in self._data.get("batter_agg", {}):
                    v = self._data["batter_agg"][player_id].get("bat_speed")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = " mph"

            elif metric_key == "swing_length":
                if player_id in self._data.get("batter_agg", {}):
                    v = self._data["batter_agg"][player_id].get("swing_length")
                    if pd.notna(v):
                        value = f"{v:.2f}"
                        unit = " ft"

            elif metric_key == "whiff_percent":
                if player_id in self._data.get("batter_agg", {}):
                    v = self._data["batter_agg"][player_id].get("whiff_percent")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = "%"

            elif metric_key == "chase_percent":
                if player_id in self._data.get("batter_agg", {}):
                    v = self._data["batter_agg"][player_id].get("chase_percent")
                    if pd.notna(v):
                        value = f"{v:.1f}"
                        unit = "%"

            elif metric_key == "fb_spin":
                if player_id in self._data.get("pitcher_agg", {}):
                    v = self._data["pitcher_agg"][player_id].get("fastball_spin")
                    if pd.notna(v):
                        value = f"{int(v)}"
                        unit = " rpm"

            elif metric_key == "curve_spin":
                if player_id in self._data.get("pitcher_agg", {}):
                    v = self._data["pitcher_agg"][player_id].get("breaking_spin")
                    if pd.notna(v):
                        value = f"{int(v)}"
                        unit = " rpm"

        except Exception as e:
            logger.debug("Error getting value for %s/%s: %s", player_id, metric_key, e)

        if value:
            return value + unit
        return None


def build_metrics_with_values(
    row: pd.Series,
    player_type: str,
    metric_defs: list[tuple[str, str, str]],
    player_id: int,
    value_store: ActualValueStore,
) -> list[dict[str, Any]]:
    """Build metrics with both percentile and actual values."""
    metrics: list[dict[str, Any]] = []

    for key, label, category in metric_defs:
        if key not in row:
            continue

        percentile = percentile_value(row[key])
        if percentile is None:
            continue

        actual_value = value_store.get_value(player_id, key, player_type)

        metric = {
            "id": f"{player_type}-{player_id}-{key}",
            "label": label,
            "value": actual_value if actual_value else "",
            "percentile": percentile,
            "category": category,
        }

        if actual_value:
            metric["actual_value"] = actual_value
            metric["display_value"] = f"{actual_value} · {percentile}th"
        else:
            metric["display_value"] = f"{percentile}th percentile"

        metrics.append(metric)

    return metrics


def build_roster_lookup(season: int) -> dict[int, dict[str, str]]:
    """Build a lookup of player_id -> {team, position} from MLB Stats API rosters."""
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


def merge_player_row(
    players: dict[int, dict],
    row: pd.Series,
    player_type: str,
    metric_defs: list[tuple[str, str, str]],
    now: datetime,
    season: int,
    value_store: ActualValueStore,
    roster_lookup: Optional[dict[int, dict[str, str]]] = None,
) -> None:
    """Merge a data row into the players dictionary with actual values."""
    pid = safe_player_id(row)
    if pid is None:
        return

    name = display_name(row.get("last_name, first_name") or row.get("player_name", ""))
    team = team_from_row(row)
    if team == "TBD" and roster_lookup and pid in roster_lookup:
        team = normalize_team_abbr(roster_lookup[pid].get("team", ""))
    position = position_from_row(row)
    if not position and roster_lookup and pid in roster_lookup:
        position = roster_lookup[pid].get("position", "")

    now_str = now.isoformat()

    if pid not in players:
        players[pid] = {
            "id": pid,
            "name": name,
            "team": team,
            "position": position,
            "handedness": "",
            "image_url": None,
            "player_type": player_type,
            "season": season,
            "source": "baseball_savant_enhanced",
            "metrics": [],
            "standard_stats": [],
            "games": [],
            "updated_at": now_str,
        }
    else:
        if players[pid]["name"] in ("", "Unknown") and name:
            players[pid]["name"] = name
        if players[pid]["team"] in ("", "TBD") and team:
            players[pid]["team"] = team
        if not players[pid]["position"] and position:
            players[pid]["position"] = position
        existing_type = players[pid].get("player_type")
        if existing_type and existing_type != player_type:
            players[pid]["player_type"] = "two_way"
        players[pid]["updated_at"] = now_str

    metrics = build_metrics_with_values(row, player_type, metric_defs, pid, value_store)

    existing_ids = {m["id"] for m in players[pid]["metrics"]}
    for m in metrics:
        if m["id"] not in existing_ids:
            players[pid]["metrics"].append(m)


def _add_calculated_rates(players: dict[int, dict]) -> None:
    """Calculate K% and BB% from standard stats and update existing metrics."""
    for pid, player in players.items():
        pa = None
        so = None
        bb = None
        bf = None

        for s in player.get("standard_stats", []):
            label = s["label"]
            try:
                if label == "PA":
                    pa = int(s["value"])
                elif label == "SO":
                    so = int(s["value"])
                elif label == "BB":
                    bb = int(s["value"])
                elif label == "BF":
                    bf = int(s["value"])
            except (ValueError, TypeError):
                pass

        if pa is None and bf is not None:
            pa = bf

        if pa is None or pa <= 0:
            continue

        player_type = player.get("player_type", "batter")
        is_pitcher = player_type == "pitcher" or (player_type == "two_way" and bf is not None)
        prefix = "pitcher" if is_pitcher else "batter"
        category = "Pitching" if is_pitcher else "Hitting"

        existing_metrics = {m["label"]: m for m in player.get("metrics", [])}

        if so is not None:
            k_rate = (so / pa) * 100
            k_value = f"{k_rate:.1f}%"

            if "K%" in existing_metrics:
                existing_metrics["K%"]["value"] = k_value
                existing_metrics["K%"]["actual_value"] = k_value
                if existing_metrics["K%"].get("percentile"):
                    existing_metrics["K%"]["display_value"] = f"{k_value} · {existing_metrics['K%']['percentile']}th"
            else:
                player["metrics"].append({
                    "id": f"{prefix}-{pid}-k_percent",
                    "label": "K%",
                    "value": k_value,
                    "actual_value": k_value,
                    "percentile": 0,
                    "category": category,
                })

        if bb is not None:
            bb_rate = (bb / pa) * 100
            bb_value = f"{bb_rate:.1f}%"

            if "BB%" in existing_metrics:
                existing_metrics["BB%"]["value"] = bb_value
                existing_metrics["BB%"]["actual_value"] = bb_value
                if existing_metrics["BB%"].get("percentile"):
                    existing_metrics["BB%"]["display_value"] = f"{bb_value} · {existing_metrics['BB%']['percentile']}th"
            else:
                player["metrics"].append({
                    "id": f"{prefix}-{pid}-bb_percent",
                    "label": "BB%",
                    "value": bb_value,
                    "actual_value": bb_value,
                    "percentile": 0,
                    "category": category,
                })


def build_snapshot_rows(season: int) -> list[dict]:
    """Build snapshot rows with both percentiles and actual values."""
    logger.info("Building snapshot rows for season %s with actual values...", season)

    now = datetime.now(UTC)
    players: dict[int, dict] = {}

    value_store = ActualValueStore(season)

    logger.info("Fetching MLB roster lookup...")
    roster_lookup = build_roster_lookup(season)

    logger.info("Fetching percentile rankings...")
    batter_rows = statcast_batter_percentile_ranks(season)
    pitcher_rows = statcast_pitcher_percentile_ranks(season)

    logger.info("Batter percentile rows: %d", len(batter_rows))
    logger.info("Pitcher percentile rows: %d", len(pitcher_rows))

    batter_metrics = BATTER_METRICS + RUNNING_METRICS + FIELDING_METRICS
    skipped = 0
    for _, row in batter_rows.iterrows():
        try:
            merge_player_row(players, row, "batter", batter_metrics, now, season, value_store, roster_lookup)
        except Exception:
            skipped += 1
            logger.exception("Failed to process batter row")

    pitcher_metrics = PITCHER_METRICS
    for _, row in pitcher_rows.iterrows():
        try:
            merge_player_row(players, row, "pitcher", pitcher_metrics, now, season, value_store, roster_lookup)
        except Exception:
            skipped += 1
            logger.exception("Failed to process pitcher row")

    logger.info(
        "Total players: %d (batters: %d, pitchers: %d, two-way: %d, skipped: %d)",
        len(players),
        sum(1 for p in players.values() if p.get("player_type") == "batter"),
        sum(1 for p in players.values() if p.get("player_type") == "pitcher"),
        sum(1 for p in players.values() if p.get("player_type") == "two_way"),
        skipped,
    )

    all_player_ids = list(players.keys())
    logger.info("Fetching standard stats from MLB Stats API for %d players...", len(all_player_ids))
    mlb_stats = _fetch_mlb_standard_stats(all_player_ids, season)

    with_std = 0
    for pid, stats in mlb_stats.items():
        if pid in players:
            players[pid]["standard_stats"] = _build_standard_stats_from_mlb(stats)
            with_std += 1

    logger.info("Attached standard stats to %d players", with_std)

    _add_calculated_rates(players)

    return list(players.values())


def _fetch_mlb_standard_stats(player_ids: list[int], season: int) -> dict[int, dict[str, Any]]:
    """Fetch standard stats from MLB Stats API."""
    stats_by_player: dict[int, dict[str, Any]] = {}

    batch_size = 50
    for i in range(0, len(player_ids), batch_size):
        batch = player_ids[i:i + batch_size]
        ids_param = ",".join(str(pid) for pid in batch)

        try:
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

                stats_list = person.get("stats", [])
                for stat_group in stats_list:
                    group_data = stat_group.get("group", {})
                    if isinstance(group_data, dict) and group_data.get("displayName") == "pitching":
                        for split in stat_group.get("splits", []):
                            stat = split.get("stat", {})
                            if stat:
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
                                    "bf": stat.get("battersFaced", 0),
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
                if key in ("avg", "obp", "slg", "ops") and val != "":
                    try:
                        val_str = f"{float(val):.3f}"
                    except (ValueError, TypeError):
                        val_str = str(val)
                else:
                    val_str = str(int(val)) if isinstance(val, (int, float)) and float(val).is_integer() else str(val)
                result.append({"id": f"std-{label}", "label": label, "value": val_str})

    if stats.get("player_type") in ("pitcher", "two_way"):
        pitchers = [
            ("era", "ERA"), ("whip", "WHIP"), ("wins", "W"), ("losses", "L"), ("saves", "SV"),
            ("ip", "IP"), ("h", "H"), ("r", "R"), ("er", "ER"), ("hr", "HR"),
            ("bb", "BB"), ("so", "SO"), ("k9", "K/9"), ("bb9", "BB/9"), ("kbb", "K/BB"),
            ("qs", "QS"), ("g", "G"), ("gs", "GS"), ("bf", "BF"),
        ]
        existing_labels = {s["label"] for s in result}
        for key, label in pitchers:
            if label in existing_labels:
                continue
            val = stats.get(key)
            if val is not None and val != "":
                if key in ("era", "whip", "k9", "bb9", "kbb"):
                    try:
                        val_str = f"{float(val):.2f}"
                    except (ValueError, TypeError):
                        val_str = str(val)
                else:
                    val_str = str(int(val)) if isinstance(val, (int, float)) and float(val).is_integer() else str(val)
                result.append({"id": f"std-{label}", "label": label, "value": val_str})

    return result


def chunks(lst: list, n: int) -> Iterator[list]:
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)
    season = _resolve_season()

    logger.info("=== Processing season %s with actual values ===", season)
    try:
        rows = build_snapshot_rows(season)
        if not rows:
            logger.error("No rows to upsert for %s.", season)
            sys.exit(1)

        batch_size = 150
        for i, batch in enumerate(chunks(rows, batch_size)):
            logger.info("Upserting batch %d (%d rows) for %s...", i + 1, len(batch), season)
            try:
                client.table("player_snapshots").upsert(batch, on_conflict="id,season").execute()
            except Exception as e:
                error_str = str(e)
                if "no unique or exclusion constraint" in error_str or "ON CONFLICT" in error_str:
                    logger.warning("Upsert failed due to missing constraint, falling back to delete+insert")
                    for row in batch:
                        client.table("player_snapshots").delete().eq("id", row["id"]).eq("season", row["season"]).execute()
                    client.table("player_snapshots").insert(batch).execute()
                else:
                    raise

        logger.info("Successfully upserted %d player snapshots with actual values for %s.", len(rows), season)
    except Exception:
        logger.exception("Failed to process season %s", season)
        sys.exit(1)


if __name__ == "__main__":
    main()
