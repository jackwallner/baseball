import os
from datetime import datetime, timezone
UTC = timezone.utc
from typing import Any, Optional

import pandas as pd
from dotenv import load_dotenv
from pybaseball import statcast_batter_percentile_ranks, statcast_pitcher_percentile_ranks
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
STATCAST_SEASON = int(os.environ.get("STATCAST_SEASON", datetime.now(UTC).year))

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
    ("sprint_speed", "Sprint Speed", "Running"),
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


def display_name(player_name: Any) -> str:
    value = str(player_name).strip()
    if "," not in value:
        return value
    last_name, first_name = value.split(",", 1)
    return f"{first_name.strip()} {last_name.strip()}".strip()


def percentile_value(value: Any) -> Optional[int]:
    if pd.isna(value):
        return None
    return max(0, min(100, int(round(float(value)))))


def build_metrics(row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]]) -> list[dict[str, Any]]:
    metrics: list[dict[str, Any]] = []
    player_id = int(row["player_id"])
    for key, label, category in metric_defs:
        if key not in row:
            continue
        percentile = percentile_value(row[key])
        if percentile is None:
            continue
        metrics.append(
            {
                "id": f"{player_type}-{player_id}-{key}",
                "label": label,
                "value": f"{percentile} PCTL",
                "percentile": percentile,
                "direction": "flat",
                "category": category,
            }
        )
    return metrics


def merge_player_row(players: dict[int, dict[str, Any]], row: pd.Series, player_type: str, metric_defs: list[tuple[str, str, str]], now: str) -> None:
    player_id = int(row["player_id"])
    metrics = build_metrics(row, player_type, metric_defs)
    if not metrics:
        return

    if player_id not in players:
        players[player_id] = {
            "id": player_id,
            "name": display_name(row["player_name"]),
            "team": "MLB",
            "position": "Hitter" if player_type == "batter" else "Pitcher",
            "handedness": "",
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


def build_snapshot_rows() -> list[dict[str, Any]]:
    now = datetime.now(UTC).isoformat()
    players: dict[int, dict[str, Any]] = {}

    batter_rows = statcast_batter_percentile_ranks(STATCAST_SEASON)
    pitcher_rows = statcast_pitcher_percentile_ranks(STATCAST_SEASON)

    for _, row in batter_rows.iterrows():
        merge_player_row(players, row, "batter", BATTER_METRICS, now)

    for _, row in pitcher_rows.iterrows():
        merge_player_row(players, row, "pitcher", PITCHER_METRICS, now)

    return list(players.values())


def main() -> None:
    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    rows = build_snapshot_rows()
    client.table("player_snapshots").upsert(rows, on_conflict="id").execute()
    print(f"Upserted {len(rows)} Baseball Savant percentile player snapshots for {STATCAST_SEASON} at {datetime.now(UTC).isoformat()}")


if __name__ == "__main__":
    main()
