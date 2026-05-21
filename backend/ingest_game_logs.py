"""
Per-player-per-game Statcast ingest. Powers the Recent Form card
(last 7 / 15 / 30 day windows) on the iOS player profile.

Pulls pitch-level data from Baseball Savant via pybaseball.statcast(),
aggregates to per-player-per-game (separate rows for batter / pitcher
contributions), and upserts into Supabase public.player_game_logs.

Incremental by default: starts from the day after the latest game_date
already in the DB for the season. Pass --full to re-ingest the whole
season.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import argparse
import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

import pandas as pd
from dotenv import load_dotenv
from pybaseball import statcast
from supabase import create_client

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Season window. MLB regular season runs late-March → early-October; spring
# training Statcast data exists but we don't want it polluting trends.
SEASON_START = date(2026, 3, 20)
SEASON_END = date(2026, 11, 5)

# Pull pitch-level data in chunks. Wider = fewer HTTP calls but more memory
# and a higher chance of a Savant timeout. 7 days is a reasonable middle.
CHUNK_DAYS = 7

# Below this PA count we still record the row but the iOS layer flags it as
# small-sample. We don't filter here so the trend windows have a complete
# picture even if a player only had 1 PA in a given game.
MIN_PA_TO_RECORD = 1


def _resolve_season() -> int:
    now = datetime.now(UTC)
    return now.year if now.month >= 4 else now.year - 1


def _latest_game_date(client, season: int) -> Optional[date]:
    """Return the max game_date already in the table for this season, or None."""
    resp = (
        client.table("player_game_logs")
        .select("game_date")
        .eq("season", season)
        .order("game_date", desc=True)
        .limit(1)
        .execute()
    )
    if not resp.data:
        return None
    raw = resp.data[0]["game_date"]
    return datetime.strptime(raw, "%Y-%m-%d").date()


def _date_chunks(start: date, end: date, days: int):
    cur = start
    while cur <= end:
        chunk_end = min(cur + timedelta(days=days - 1), end)
        yield cur, chunk_end
        cur = chunk_end + timedelta(days=1)


def _pct(numer: float, denom: float) -> Optional[float]:
    if denom <= 0:
        return None
    return round(100.0 * numer / denom, 2)


def _mean(series: pd.Series) -> Optional[float]:
    s = series.dropna()
    if s.empty:
        return None
    return round(float(s.mean()), 3)


def _team_for_side(row: pd.Series, side: str) -> str:
    """Resolve team abbr for a player on a given side ('batter' or 'pitcher').

    inning_topbot=='Top' means away team is batting (so pitcher is home).
    inning_topbot=='Bot' means home team is batting (so pitcher is away).
    """
    top = row.get("inning_topbot") == "Top"
    if side == "batter":
        return row["away_team"] if top else row["home_team"]
    else:
        return row["home_team"] if top else row["away_team"]


def _aggregate_batters(df: pd.DataFrame) -> list[dict]:
    """Aggregate a pitch-level chunk to per-batter-per-game rows."""
    if df.empty:
        return []

    # Terminal-PA rows: anything with a non-null events column is the final
    # pitch of a plate appearance.
    pa_df = df[df["events"].notna()].copy()
    if pa_df.empty:
        return []

    pa_df["batter_team"] = pa_df.apply(lambda r: _team_for_side(r, "batter"), axis=1)
    pa_df["pitcher_team"] = pa_df.apply(lambda r: _team_for_side(r, "pitcher"), axis=1)

    rows: list[dict] = []
    grouped = pa_df.groupby(["batter", "game_date"], dropna=True)
    for (batter_id, game_date), grp in grouped:
        if pd.isna(batter_id):
            continue
        pa = len(grp)
        if pa < MIN_PA_TO_RECORD:
            continue

        bbe_mask = grp["launch_speed"].notna()
        bbe_count = int(bbe_mask.sum())
        bbe = grp[bbe_mask]

        events = grp["events"].fillna("")
        k_count = int((events.str.contains("strikeout", na=False)).sum())
        # walk events: 'walk' or 'intent_walk' (intentional walk). Both count.
        bb_count = int((events.isin(["walk", "intent_walk"])).sum())
        hardhit_count = int((bbe["launch_speed"] >= 95).sum())
        # launch_speed_angle code 6 == Barrel in Statcast classification.
        barrel_count = int((bbe.get("launch_speed_angle", pd.Series(dtype=float)) == 6).sum())

        metrics = {
            "xwoba": _mean(grp.get("estimated_woba_using_speedangle", pd.Series(dtype=float))),
            "ev_avg": _mean(bbe["launch_speed"]) if bbe_count else None,
            "ev_max": (round(float(bbe["launch_speed"].max()), 1) if bbe_count else None),
            "hardhit_pct": _pct(hardhit_count, bbe_count),
            "barrel_pct": _pct(barrel_count, bbe_count),
            "k_pct": _pct(k_count, pa),
            "bb_pct": _pct(bb_count, pa),
        }

        team = grp["batter_team"].mode().iat[0] if not grp["batter_team"].mode().empty else None
        opp = grp["pitcher_team"].mode().iat[0] if not grp["pitcher_team"].mode().empty else None

        rows.append({
            "player_id": int(batter_id),
            "season": int(grp["game_year"].iat[0]) if "game_year" in grp.columns else _resolve_season(),
            "game_date": str(game_date),
            "player_type": "batter",
            "team": team,
            "opponent": opp,
            "plate_appearances": pa,
            "batted_ball_events": bbe_count,
            "metrics": metrics,
        })

    return rows


def _aggregate_pitchers(df: pd.DataFrame) -> list[dict]:
    """Aggregate a pitch-level chunk to per-pitcher-per-game rows."""
    if df.empty:
        return []

    pa_df = df[df["events"].notna()].copy()
    if pa_df.empty:
        return []

    pa_df["batter_team"] = pa_df.apply(lambda r: _team_for_side(r, "batter"), axis=1)
    pa_df["pitcher_team"] = pa_df.apply(lambda r: _team_for_side(r, "pitcher"), axis=1)

    rows: list[dict] = []
    grouped = pa_df.groupby(["pitcher", "game_date"], dropna=True)
    for (pitcher_id, game_date), grp in grouped:
        if pd.isna(pitcher_id):
            continue
        bf = len(grp)
        if bf < MIN_PA_TO_RECORD:
            continue

        bbe_mask = grp["launch_speed"].notna()
        bbe_count = int(bbe_mask.sum())
        bbe = grp[bbe_mask]

        events = grp["events"].fillna("")
        k_count = int((events.str.contains("strikeout", na=False)).sum())
        bb_count = int((events.isin(["walk", "intent_walk"])).sum())
        hardhit_count = int((bbe["launch_speed"] >= 95).sum())
        barrel_count = int((bbe.get("launch_speed_angle", pd.Series(dtype=float)) == 6).sum())

        metrics = {
            "opp_xwoba": _mean(grp.get("estimated_woba_using_speedangle", pd.Series(dtype=float))),
            "opp_ev_avg": _mean(bbe["launch_speed"]) if bbe_count else None,
            "opp_hardhit_pct": _pct(hardhit_count, bbe_count),
            "opp_barrel_pct": _pct(barrel_count, bbe_count),
            "k_pct": _pct(k_count, bf),
            "bb_pct": _pct(bb_count, bf),
        }

        team = grp["pitcher_team"].mode().iat[0] if not grp["pitcher_team"].mode().empty else None
        opp = grp["batter_team"].mode().iat[0] if not grp["batter_team"].mode().empty else None

        rows.append({
            "player_id": int(pitcher_id),
            "season": int(grp["game_year"].iat[0]) if "game_year" in grp.columns else _resolve_season(),
            "game_date": str(game_date),
            "player_type": "pitcher",
            "team": team,
            "opponent": opp,
            "plate_appearances": bf,
            "batted_ball_events": bbe_count,
            "metrics": metrics,
        })

    return rows


def _upsert(client, rows: list[dict]) -> None:
    if not rows:
        return
    batch_size = 200
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        try:
            client.table("player_game_logs").upsert(
                batch,
                on_conflict="player_id,season,game_date,player_type",
            ).execute()
        except Exception:
            logger.exception("Upsert failed for batch starting at %d", i)
            raise


def run(full: bool = False) -> None:
    season = _resolve_season()
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)

    client = create_client(url, key)

    if full:
        start = SEASON_START
    else:
        latest = _latest_game_date(client, season)
        # Re-ingest the latest known day too — that day may have had late
        # games whose final state wasn't in Savant yet on the prior run.
        start = latest if latest else SEASON_START

    today = datetime.now(UTC).date()
    end = min(today, SEASON_END)

    if start > end:
        logger.info("Nothing to ingest: start=%s end=%s", start, end)
        return

    logger.info("Ingesting game logs for season %s from %s to %s", season, start, end)

    total_batter_rows = 0
    total_pitcher_rows = 0

    for chunk_start, chunk_end in _date_chunks(start, end, CHUNK_DAYS):
        logger.info("Fetching %s → %s", chunk_start, chunk_end)
        try:
            df = statcast(start_dt=chunk_start.isoformat(), end_dt=chunk_end.isoformat())
        except Exception:
            logger.exception("statcast() failed for %s → %s; skipping chunk", chunk_start, chunk_end)
            continue

        if df is None or df.empty:
            logger.info("No rows for %s → %s", chunk_start, chunk_end)
            continue

        batter_rows = _aggregate_batters(df)
        pitcher_rows = _aggregate_pitchers(df)
        logger.info("  batter rows=%d, pitcher rows=%d", len(batter_rows), len(pitcher_rows))

        _upsert(client, batter_rows)
        _upsert(client, pitcher_rows)
        total_batter_rows += len(batter_rows)
        total_pitcher_rows += len(pitcher_rows)

    logger.info(
        "Done. Total upserts — batter=%d, pitcher=%d", total_batter_rows, total_pitcher_rows
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="Re-ingest from season start, not incremental.")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    args = _parse_args()
    run(full=args.full)
