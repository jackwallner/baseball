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

# --- Pitch-level classification -------------------------------------------
# Whiff% and Chase% are properties of individual pitches, so they can't be
# derived from the terminal-PA frame the rate stats use — they need a second
# pass over every pitch in the chunk.

# Statcast `description` values that represent a swing and miss.
WHIFF_DESCRIPTIONS = frozenset({
    "swinging_strike",
    "swinging_strike_blocked",
    "foul_tip",
    "missed_bunt",
})
# Every description where the batter offered at the pitch.
SWING_DESCRIPTIONS = WHIFF_DESCRIPTIONS | frozenset({
    "foul",
    "foul_bunt",
    "bunt_foul_tip",
    "hit_into_play",
})
# Savant `zone`: 1-9 are the strike-zone thirds, 11-14 the outside quadrants.
OUT_OF_ZONE = frozenset({11, 12, 13, 14})
# Savant's sweet-spot launch-angle band, inclusive.
SWEETSPOT_LA_MIN = 8.0
SWEETSPOT_LA_MAX = 32.0

# --- Traditional counting stats -------------------------------------------
# Derived from the terminal-PA `events` column so recent windows can report a
# real AVG / OBP / SLG rather than only Statcast rates.

HIT_EVENTS = {"single": 1, "double": 2, "triple": 3, "home_run": 4}
# A plate appearance that isn't an at-bat. Walks, hit-by-pitches and sacrifices
# are excluded from AB by rule; truncated_pa is a PA the game ended mid-way
# through, so it isn't one either.
NON_AT_BAT_EVENTS = frozenset({
    "walk",
    "intent_walk",
    "hit_by_pitch",
    "sac_fly",
    "sac_fly_double_play",
    "sac_bunt",
    "sac_bunt_double_play",
    "catcher_interf",
    "truncated_pa",
})
SAC_FLY_EVENTS = frozenset({"sac_fly", "sac_fly_double_play"})
WALK_EVENTS = frozenset({"walk", "intent_walk"})

# Savant reports pitchers' velocity and spin as *fastball* figures. Averaging
# every pitch instead would drag a starter's number down by their changeup and
# curveball, so the app couldn't place it on Savant's Fastball Velo scale.
FASTBALL_PITCH_TYPES = frozenset({"FF", "SI", "FC"})


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


def _round(value: Optional[float], places: int) -> Optional[float]:
    if value is None or pd.isna(value):
        return None
    return round(float(value), places)


def _pitch_aggregates(
    df: pd.DataFrame, id_col: str, include_pitch_shape: bool
) -> dict[tuple, dict]:
    """Per-(player, game) aggregates that need every pitch in the chunk.

    The rate stats aggregate the terminal pitch of each plate appearance, but
    Whiff%, Chase% and the swing/pitch tracking metrics are per-pitch — a
    hitter's whiffs mostly happen on pitches that don't end the PA. Keyed by
    ``(player_id, game_date)`` so the PA-level pass can join against it.

    ``include_pitch_shape`` adds release velocity / spin / extension, which are
    properties of the pitcher, not the batter.
    """
    if df.empty:
        return {}

    work = pd.DataFrame({
        "player": df[id_col],
        "game_date": df["game_date"],
        "is_swing": df["description"].isin(SWING_DESCRIPTIONS),
        "is_whiff": df["description"].isin(WHIFF_DESCRIPTIONS),
        "is_oz": df["zone"].isin(OUT_OF_ZONE),
    })
    work["oz_swing"] = work["is_swing"] & work["is_oz"]

    keys = ["player", "game_date"]
    counts = work.groupby(keys, dropna=True).agg(
        pitches=("is_swing", "size"),
        swings=("is_swing", "sum"),
        whiffs=("is_whiff", "sum"),
        oz_pitches=("is_oz", "sum"),
        oz_swings=("oz_swing", "sum"),
    )

    # Bat tracking is only recorded on swings, so averaging over all pitches
    # would drag the mean toward whichever pitches happened to be taken.
    swing_cols = [c for c in ("bat_speed", "swing_length") if c in df.columns]
    swing_means = pd.DataFrame(index=counts.index)
    if swing_cols:
        swings_only = pd.DataFrame({
            "player": df[id_col],
            "game_date": df["game_date"],
            **{c: df[c] for c in swing_cols},
        })[work["is_swing"].to_numpy()]
        if not swings_only.empty:
            swing_means = swings_only.groupby(keys, dropna=True)[swing_cols].mean()

    shape_means = pd.DataFrame(index=counts.index)
    if include_pitch_shape:
        shape_cols = [
            c for c in ("release_speed", "release_spin_rate", "release_extension")
            if c in df.columns
        ]
        if shape_cols:
            shape = pd.DataFrame({
                "player": df[id_col],
                "game_date": df["game_date"],
                **{c: df[c] for c in shape_cols},
            })
            # Extension is a delivery trait, so it averages over everything;
            # velo and spin are reported as fastball-only to match Savant.
            shape_means = shape.groupby(keys, dropna=True)[shape_cols].mean()
            if "pitch_type" in df.columns:
                fastballs = shape[df["pitch_type"].isin(FASTBALL_PITCH_TYPES).to_numpy()]
                if not fastballs.empty:
                    fb_cols = [c for c in ("release_speed", "release_spin_rate") if c in shape_cols]
                    fb_means = fastballs.groupby(keys, dropna=True)[fb_cols].mean()
                    fb_means.columns = [f"fb_{c}" for c in fb_means.columns]
                    shape_means = shape_means.join(fb_means, how="left")

    merged = counts.join(swing_means, how="left").join(shape_means, how="left")
    return {key: row.to_dict() for key, row in merged.iterrows()}


def _counting_stats(grp: pd.DataFrame) -> dict[str, int]:
    """Traditional counting line for one player-game, from terminal-PA events.

    Stored underscore-prefixed so the rollup sums them rather than treating
    them as rates; the window's AVG / OBP / SLG are then derived from the sums,
    which is the only way to get those right — averaging per-game batting
    averages would weight an 0-for-1 the same as a 4-for-4.

    RBI, runs, stolen bases and caught stealing aren't recoverable from
    pitch-level data and stay season-only.
    """
    events = grp["events"].fillna("")
    counts = events.value_counts()

    singles = int(counts.get("single", 0))
    doubles = int(counts.get("double", 0))
    triples = int(counts.get("triple", 0))
    homers = int(counts.get("home_run", 0))
    hits = singles + doubles + triples + homers

    at_bats = int((~events.isin(NON_AT_BAT_EVENTS)).sum())
    walks = int(events.isin(WALK_EVENTS).sum())
    hbp = int(counts.get("hit_by_pitch", 0))
    sac_flies = int(events.isin(SAC_FLY_EVENTS).sum())
    strikeouts = int(events.str.contains("strikeout", na=False).sum())
    total_bases = singles + 2 * doubles + 3 * triples + 4 * homers

    return {
        "_ab": at_bats,
        "_h": hits,
        "_2b": doubles,
        "_3b": triples,
        "_hr": homers,
        "_tb": total_bases,
        "_bb": walks,
        "_so": strikeouts,
        "_hbp": hbp,
        "_sf": sac_flies,
    }


def _expected_stat(grp: pd.DataFrame, column: str) -> tuple[Optional[float], int]:
    """Savant-style xBA / xSLG over a plate-appearance group.

    Statcast populates ``estimated_ba_using_speedangle`` and its xSLG twin only
    on batted balls — they are null on strikeouts, walks, hit-by-pitches and
    sacrifices. A plain mean would therefore drop strikeouts and inflate the
    result. Savant's denominator is at-bats, so strikeouts count as an 0-for and
    walks / HBP / sacrifices are excluded entirely.

    Returns ``(value, at_bats)``; value is None when the group has no at-bats.
    """
    if column not in grp.columns:
        return None, 0
    values = grp[column]
    is_strikeout = grp["events"].fillna("").str.contains("strikeout", na=False)
    at_bat = values.notna() | is_strikeout
    denom = int(at_bat.sum())
    if denom == 0:
        return None, 0
    total = float(values.where(at_bat).fillna(0.0).sum())
    return total / denom, denom


def _weighted_expected_woba(grp: pd.DataFrame) -> tuple[Optional[float], float]:
    """xwOBA as Savant defines it: sum(xwOBA value) / sum(wOBA denominator).

    ``woba_denom`` is 0 for events that don't count against wOBA (sacrifice
    bunts), so dividing by it rather than taking a plain mean keeps those plate
    appearances from diluting the rate.
    """
    if "estimated_woba_using_speedangle" not in grp.columns:
        return None, 0.0
    denom = float(grp.get("woba_denom", pd.Series(dtype=float)).fillna(0).sum())
    if denom <= 0:
        return None, 0.0
    total = float(grp["estimated_woba_using_speedangle"].fillna(0.0).sum())
    return total / denom, denom


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

    pitch_agg = _pitch_aggregates(df, "batter", include_pitch_shape=False)

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
        launch_angles = bbe["launch_angle"].dropna() if "launch_angle" in bbe.columns else pd.Series(dtype=float)
        sweetspot_count = int(
            ((launch_angles >= SWEETSPOT_LA_MIN) & (launch_angles <= SWEETSPOT_LA_MAX)).sum()
        )

        xwoba, woba_denom = _weighted_expected_woba(grp)
        xba, at_bats = _expected_stat(grp, "estimated_ba_using_speedangle")
        xslg, _ = _expected_stat(grp, "estimated_slg_using_speedangle")
        pitches = pitch_agg.get((batter_id, game_date), {})
        swings = int(pitches.get("swings") or 0)
        oz_pitches = int(pitches.get("oz_pitches") or 0)

        metrics = {
            "xwoba": _round(xwoba, 3),
            "xba": _round(xba, 3),
            "xslg": _round(xslg, 3),
            # xISO is the identity xSLG - xBA, so it only exists when both do.
            "xiso": _round(xslg - xba, 3) if (xslg is not None and xba is not None) else None,
            "ev_avg": _mean(bbe["launch_speed"]) if bbe_count else None,
            "ev_max": (round(float(bbe["launch_speed"].max()), 1) if bbe_count else None),
            "hardhit_pct": _pct(hardhit_count, bbe_count),
            "barrel_pct": _pct(barrel_count, bbe_count),
            "sweetspot_pct": _pct(sweetspot_count, len(launch_angles)),
            "la_avg": _round(launch_angles.mean(), 1) if len(launch_angles) else None,
            "k_pct": _pct(k_count, pa),
            "bb_pct": _pct(bb_count, pa),
            "whiff_pct": _pct(int(pitches.get("whiffs") or 0), swings),
            "chase_pct": _pct(int(pitches.get("oz_swings") or 0), oz_pitches),
            "bat_speed": _round(pitches.get("bat_speed"), 1),
            "swing_length": _round(pitches.get("swing_length"), 2),
            # Denominators, underscore-prefixed so the app can tell them apart
            # from displayable metrics. Storing them lets any rolling window be
            # recomputed exactly instead of PA-weighting per-game rates.
            "_pitches": int(pitches.get("pitches") or 0),
            "_swings": swings,
            "_oz_pitches": oz_pitches,
            "_bbe": bbe_count,
            "_at_bats": at_bats,
            "_woba_denom": _round(woba_denom, 1),
        }
        metrics.update(_counting_stats(grp))

        team = grp["batter_team"].mode().iat[0] if not grp["batter_team"].mode().empty else None
        opp = grp["pitcher_team"].mode().iat[0] if not grp["pitcher_team"].mode().empty else None

        rows.append({
            "player_id": int(batter_id),
            "season": int(grp["game_year"].iat[0]) if "game_year" in grp.columns else _resolve_season(),
            "game_date": pd.Timestamp(game_date).strftime("%Y-%m-%d"),
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

    pitch_agg = _pitch_aggregates(df, "pitcher", include_pitch_shape=True)

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
        bb_types = bbe["bb_type"].fillna("") if "bb_type" in bbe.columns else pd.Series(dtype=str)

        opp_xwoba, woba_denom = _weighted_expected_woba(grp)
        opp_xba, at_bats = _expected_stat(grp, "estimated_ba_using_speedangle")
        opp_xslg, _ = _expected_stat(grp, "estimated_slg_using_speedangle")
        pitches = pitch_agg.get((pitcher_id, game_date), {})
        swings = int(pitches.get("swings") or 0)
        oz_pitches = int(pitches.get("oz_pitches") or 0)

        metrics = {
            "opp_xwoba": _round(opp_xwoba, 3),
            "opp_xba": _round(opp_xba, 3),
            "opp_xslg": _round(opp_xslg, 3),
            "opp_ev_avg": _mean(bbe["launch_speed"]) if bbe_count else None,
            "opp_ev_max": (round(float(bbe["launch_speed"].max()), 1) if bbe_count else None),
            "opp_hardhit_pct": _pct(hardhit_count, bbe_count),
            "opp_barrel_pct": _pct(barrel_count, bbe_count),
            "k_pct": _pct(k_count, bf),
            "bb_pct": _pct(bb_count, bf),
            "whiff_pct": _pct(int(pitches.get("whiffs") or 0), swings),
            "chase_pct": _pct(int(pitches.get("oz_swings") or 0), oz_pitches),
            "gb_pct": _pct(int((bb_types == "ground_ball").sum()), bbe_count),
            "fb_pct": _pct(int((bb_types == "fly_ball").sum()), bbe_count),
            "velo_avg": _round(pitches.get("release_speed"), 1),
            "spin_avg": _round(pitches.get("release_spin_rate"), 0),
            "extension_avg": _round(pitches.get("release_extension"), 2),
            "fb_velo_avg": _round(pitches.get("fb_release_speed"), 1),
            "fb_spin_avg": _round(pitches.get("fb_release_spin_rate"), 0),
            # See the batter aggregator — denominators for exact window recompute.
            "_pitches": int(pitches.get("pitches") or 0),
            "_swings": swings,
            "_oz_pitches": oz_pitches,
            "_bbe": bbe_count,
            "_at_bats": at_bats,
            "_woba_denom": _round(woba_denom, 1),
        }
        # Same counting line, read as "allowed" on a pitcher's row.
        metrics.update(_counting_stats(grp))

        team = grp["pitcher_team"].mode().iat[0] if not grp["pitcher_team"].mode().empty else None
        opp = grp["batter_team"].mode().iat[0] if not grp["batter_team"].mode().empty else None

        rows.append({
            "player_id": int(pitcher_id),
            "season": int(grp["game_year"].iat[0]) if "game_year" in grp.columns else _resolve_season(),
            "game_date": pd.Timestamp(game_date).strftime("%Y-%m-%d"),
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
