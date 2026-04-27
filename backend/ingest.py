import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

import pandas as pd
from dotenv import load_dotenv
from pybaseball import statcast_batter_percentile_ranks, statcast_pitcher_percentile_ranks
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


STATCAST_SEASON = int(os.environ.get("STATCAST_SEASON", _default_season()))

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

    The percentile-rank DataFrames from pybaseball primarily contain percentiles (0-100).
    Real raw values live in separate leaderboards. For now, return None so the iOS
    client can hide the value label until raw-stat ingestion is added.
    """
    # If a companion raw column exists (e.g. 'xwoba_value'), use it.
    raw_key = f"{key}_value"
    if raw_key in row:
        raw = row[raw_key]
        if pd.notna(raw):
            return str(raw)
    # Also try a column named exactly like the key but that might contain the raw value.
    # In some pybaseball versions the percentile column has a '_percentile' suffix
    # and the bare key is the raw value. If the value is already > 100 or < 0 it's raw.
    if key in row:
        val = row[key]
        if pd.notna(val):
            try:
                f = float(val)
                if f < 0 or f > 100:
                    return str(val)
            except (ValueError, TypeError):
                pass
    return None


def build_metrics(row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]], player_id: int) -> list[dict[str, Any]]:
    metrics: list[dict[str, Any]] = []
    for key, label, category in metric_defs:
        if key not in row:
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
                "direction": "flat",
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
            return str(row[col]).strip().upper()
    return "TBD"


def position_from_row(row: pd.Series, player_type: str) -> str:
    for col in ("position", "player_position", "pos"):
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


def merge_player_row(players: dict[int, dict[str, Any]], row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]], now: str) -> None:
    player_id = safe_player_id(row)
    if player_id is None:
        logger.warning("Skipping row with missing or invalid player_id: %s", row.to_dict())
        return

    metrics = build_metrics(row, player_type, metric_defs, player_id)
    if not metrics:
        return

    if player_id not in players:
        players[player_id] = {
            "id": player_id,
            "name": display_name(row.get("player_name", "")),
            "team": team_from_row(row),
            "position": position_from_row(row, player_type),
            "handedness": handedness_from_row(row),
            "image_url": f"https://img.mlbstatic.com/mlb-photos/image/upload/w_180,q_100/v1/people/{player_id}/headshot/67/current",
            "updated_at": now,
            "season": STATCAST_SEASON,
            "player_type": player_type,
            "source": "baseball_savant_percentile_rankings",
            "metrics": metrics,
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

    batter_metrics = _all_metric_defs("batter")
    pitcher_metrics = _all_metric_defs("pitcher")

    skipped = 0
    for _, row in batter_rows.iterrows():
        try:
            merge_player_row(players, row, "batter", batter_metrics, now)
        except Exception:
            skipped += 1
            logger.exception("Failed to process batter row")

    for _, row in pitcher_rows.iterrows():
        try:
            merge_player_row(players, row, "pitcher", pitcher_metrics, now)
        except Exception:
            skipped += 1
            logger.exception("Failed to process pitcher row")

    two_way = sum(1 for p in players.values() if p.get("player_type") == "two_way")
    logger.info(
        "Total players: %d (batters: %d, pitchers: %d, two-way: %d, skipped rows: %d)",
        len(players),
        sum(1 for p in players.values() if p.get("player_type") == "batter"),
        sum(1 for p in players.values() if p.get("player_type") == "pitcher"),
        two_way,
        skipped,
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
