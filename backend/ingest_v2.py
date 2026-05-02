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
    batting_stats,
    pitching_stats,
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

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

DEFAULT_SEASON = datetime.now(UTC).year if datetime.now(UTC).month >= 4 else datetime.now(UTC).year - 1

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
    return aliases.get(upper, upper[:3] if len(upper) >= 3 else upper)


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
                    v = src[player_id].get("ev95percent") if player_type == "batter" else src[player_id].get("ev95percent")
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
        
        # Get actual value
        actual_value = value_store.get_value(player_id, key, player_type)
        
        metric = {
            "id": f"{player_type}-{player_id}-{key}",
            "label": label,
            "value": actual_value if actual_value else "",
            "percentile": percentile,
            "category": category,
        }
        
        # Add display value combining both
        if actual_value:
            metric["actual_value"] = actual_value
            metric["display_value"] = f"{actual_value} · {percentile}th"
        else:
            metric["display_value"] = f"{percentile}th percentile"
        
        metrics.append(metric)
    
    return metrics


def merge_player_row(
    players: dict[int, dict],
    row: pd.Series,
    player_type: str,
    metric_defs: list[tuple[str, str, str]],
    now: datetime,
    season: int,
    value_store: ActualValueStore,
) -> None:
    """Merge a data row into the players dictionary with actual values."""
    pid = safe_player_id(row)
    if pid is None:
        return
    
    name = display_name(row.get("last_name, first_name") or row.get("player_name", ""))
    team = team_from_row(row)
    position = position_from_row(row)
    
    # Convert datetime to ISO format string for JSON serialization
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
    
    # Build metrics with actual values
    metrics = build_metrics_with_values(row, player_type, metric_defs, pid, value_store)
    
    # Merge with existing metrics (avoid duplicates)
    existing_ids = {m["id"] for m in players[pid]["metrics"]}
    for m in metrics:
        if m["id"] not in existing_ids:
            players[pid]["metrics"].append(m)


def build_snapshot_rows(season: int) -> list[dict]:
    """Build snapshot rows with both percentiles and actual values."""
    logger.info("Building snapshot rows for season %s with actual values...", season)
    
    now = datetime.now(UTC)
    players: dict[int, dict] = {}
    
    # Prefetch all actual value data
    value_store = ActualValueStore(season)
    
    # Fetch percentile rankings
    logger.info("Fetching percentile rankings...")
    batter_rows = statcast_batter_percentile_ranks(season)
    pitcher_rows = statcast_pitcher_percentile_ranks(season)
    
    logger.info("Batter percentile rows: %d", len(batter_rows))
    logger.info("Pitcher percentile rows: %d", len(pitcher_rows))
    
    # Process batters
    batter_metrics = BATTER_METRICS + RUNNING_METRICS + FIELDING_METRICS
    skipped = 0
    for _, row in batter_rows.iterrows():
        try:
            merge_player_row(players, row, "batter", batter_metrics, now, season, value_store)
        except Exception:
            skipped += 1
            logger.exception("Failed to process batter row")
    
    # Process pitchers
    pitcher_metrics = PITCHER_METRICS
    for _, row in pitcher_rows.iterrows():
        try:
            merge_player_row(players, row, "pitcher", pitcher_metrics, now, season, value_store)
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
    
    return list(players.values())


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
