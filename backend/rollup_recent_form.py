"""Pre-aggregate per-game logs into rolling 7/15/30 day windows.

Reads public.player_game_logs and writes public.player_recent_form: one row per
(player, side of the ball, window length), holding the window ending on the
latest game date, the equal-length window immediately before it, and the delta
between them — the THEN / NOW / delta shape Baseball Savant's rolling
leaderboard uses.

The point is ranking. A league-wide 30-day slice of player_game_logs is ~9,700
rows the client would have to download and aggregate before it could sort
anything; this table is ~1,100 rows per window.

Window rates are recomputed from stored numerator/denominator pairs rather than
averaged from per-game rates, so they're exact rather than approximate. See
WEIGHTS below.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import argparse
import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

WINDOW_DAYS = (7, 15, 30)

# Which stored denominator each metric is a rate of. Aggregating a rate as
# sum(rate * denom) / sum(denom) reproduces sum(numerator) / sum(denominator)
# exactly, so these windows match a from-scratch recompute — unlike weighting
# every metric by plate appearances, which is only an approximation.
WEIGHTS: dict[str, str] = {
    # Expected stats carry their own denominators.
    "xwoba": "_woba_denom",
    "opp_xwoba": "_woba_denom",
    "xba": "_at_bats",
    "xslg": "_at_bats",
    "opp_xba": "_at_bats",
    "opp_xslg": "_at_bats",
    # Batted-ball rates are per batted-ball event.
    "ev_avg": "_bbe",
    "hardhit_pct": "_bbe",
    "barrel_pct": "_bbe",
    "sweetspot_pct": "_bbe",
    "la_avg": "_bbe",
    "opp_ev_avg": "_bbe",
    "opp_hardhit_pct": "_bbe",
    "opp_barrel_pct": "_bbe",
    "gb_pct": "_bbe",
    "fb_pct": "_bbe",
    # Swing-tracking is per swing; chase is per pitch seen outside the zone.
    "whiff_pct": "_swings",
    "bat_speed": "_swings",
    "swing_length": "_swings",
    "chase_pct": "_oz_pitches",
    # Pitch shape is per pitch thrown, except the fastball-only pair Savant
    # reports, which is per fastball.
    "velo_avg": "_pitches",
    "spin_avg": "_pitches",
    "extension_avg": "_pitches",
    "fb_velo_avg": "_fb_pitches",
    "fb_spin_avg": "_fb_pitches",
    # K and BB are per plate appearance / batter faced.
    "k_pct": "_pa",
    "bb_pct": "_pa",
}

# Peaks, not rates: the window value is the single hardest ball struck.
MAX_METRICS = ("ev_max", "opp_ev_max")

# Denominator keys are bookkeeping, never displayed.
COUNT_PREFIX = "_"

# How many decimals each metric rounds to, by suffix convention.
def _places(metric: str) -> int:
    if metric in ("spin_avg", "fb_spin_avg"):
        return 0
    # Traditional counting stats are whole numbers.
    if metric in ("ab", "h", "2b", "3b", "hr", "tb", "bb", "so", "hbp", "sf"):
        return 0
    if metric.endswith(("_pct", "_avg")) or metric in ("bat_speed", "ev_max", "opp_ev_max"):
        return 1
    if metric in ("swing_length", "extension_avg"):
        return 2
    return 3


def _client():
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)
    return create_client(url, key)


def _resolve_season() -> int:
    now = datetime.now(UTC)
    return now.year if now.month >= 4 else now.year - 1


def _fetch_logs(client, season: int, since: date) -> list[dict]:
    """Page through every game log for the season on or after `since`."""
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_game_logs")
            .select("*")
            .eq("season", season)
            .gte("game_date", since.isoformat())
            .order("game_date", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )
        page = resp.data or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def _aggregate(logs: list[dict]) -> dict[str, Any]:
    """Collapse a set of game rows into one window's metrics.

    Rates are rebuilt from numerator/denominator sums; metrics whose
    denominator is zero across the window are omitted rather than reported as 0,
    so the app can tell "no data" from "genuinely zero".
    """
    if not logs:
        return {}

    numerators: dict[str, float] = {}
    denominators: dict[str, float] = {}
    peaks: dict[str, float] = {}

    for log in logs:
        metrics = log.get("metrics") or {}
        # Plate appearances live on the row, not inside the metrics blob.
        counts = {"_pa": float(log.get("plate_appearances") or 0)}
        for key, value in metrics.items():
            if key.startswith(COUNT_PREFIX) and value is not None:
                counts[key] = float(value)

        for metric, value in metrics.items():
            if value is None or metric.startswith(COUNT_PREFIX):
                continue
            if metric in MAX_METRICS:
                peaks[metric] = max(peaks.get(metric, float("-inf")), float(value))
                continue
            weight_key = WEIGHTS.get(metric)
            if weight_key is None:
                continue
            weight = counts.get(weight_key, 0.0)
            if weight <= 0:
                continue
            numerators[metric] = numerators.get(metric, 0.0) + float(value) * weight
            denominators[metric] = denominators.get(metric, 0.0) + weight

    result: dict[str, Any] = {}
    for metric, numer in numerators.items():
        denom = denominators.get(metric, 0.0)
        if denom > 0:
            result[metric] = round(numer / denom, _places(metric))
    for metric, peak in peaks.items():
        result[metric] = round(peak, _places(metric))

    # Traditional stats are counts, so they sum across the window and the rate
    # stats derive from the sums. Averaging per-game batting averages instead
    # would weight an 0-for-1 the same as a 4-for-4.
    totals = _sum_counts(logs)
    result.update(_traditional_rates(totals))

    # xISO is the xSLG - xBA identity; recompute it from the window values so it
    # stays consistent with them rather than being weight-averaged separately.
    for iso, slg, ba in (("xiso", "xslg", "xba"), ("opp_xiso", "opp_xslg", "opp_xba")):
        if slg in result and ba in result:
            result[iso] = round(result[slg] - result[ba], 3)

    return result


COUNTING_KEYS = ("_ab", "_h", "_2b", "_3b", "_hr", "_tb", "_bb", "_so", "_hbp", "_sf")


def _sum_counts(logs: list[dict]) -> dict[str, int]:
    """Total each traditional counting stat across the window."""
    totals: dict[str, int] = {}
    for log in logs:
        metrics = log.get("metrics") or {}
        for key in COUNTING_KEYS:
            value = metrics.get(key)
            if value is not None:
                totals[key] = totals.get(key, 0) + int(value)
    return totals


def _traditional_rates(totals: dict[str, int]) -> dict[str, Any]:
    """AVG / OBP / SLG / OPS from summed counts, plus the counts themselves.

    Each is omitted when its denominator is zero, so a window with no at-bats
    reads as "no data" rather than a .000 average.
    """
    out: dict[str, Any] = {}
    ab = totals.get("_ab", 0)
    bb = totals.get("_bb", 0)
    hbp = totals.get("_hbp", 0)
    sf = totals.get("_sf", 0)
    hits = totals.get("_h", 0)

    if ab > 0:
        out["avg"] = round(hits / ab, 3)
        out["slg"] = round(totals.get("_tb", 0) / ab, 3)
    on_base_denom = ab + bb + hbp + sf
    if on_base_denom > 0:
        out["obp"] = round((hits + bb + hbp) / on_base_denom, 3)
    if "obp" in out and "slg" in out:
        out["ops"] = round(out["obp"] + out["slg"], 3)

    # Surface the counting line too — "6 HR in the last 15 days" is the thing
    # people actually quote, and it can't be recovered from the rates.
    for key in COUNTING_KEYS:
        if key in totals:
            out[key.lstrip("_")] = totals[key]
    return out


def _delta(now: dict[str, Any], then: dict[str, Any]) -> dict[str, Any]:
    """Change from the prior window to the current one, for shared metrics."""
    out: dict[str, Any] = {}
    for metric, value in now.items():
        if metric in then:
            out[metric] = round(float(value) - float(then[metric]), _places(metric))
    return out


def build_rows(logs: list[dict], as_of: date) -> list[dict]:
    """Build every (player, side, window) row from a season's game logs."""
    by_player: dict[tuple[int, str], list[dict]] = {}
    for log in logs:
        key = (log["player_id"], log["player_type"])
        by_player.setdefault(key, []).append(log)

    rows: list[dict] = []
    for (player_id, player_type), player_logs in by_player.items():
        player_logs.sort(key=lambda r: r["game_date"], reverse=True)
        season = player_logs[0]["season"]
        team = player_logs[0].get("team")

        for window in WINDOW_DAYS:
            current_start = as_of - timedelta(days=window - 1)
            prior_start = current_start - timedelta(days=window)

            current = [
                r for r in player_logs
                if date.fromisoformat(r["game_date"]) >= current_start
            ]
            prior = [
                r for r in player_logs
                if prior_start <= date.fromisoformat(r["game_date"]) < current_start
            ]
            if not current:
                continue

            now_metrics = _aggregate(current)
            then_metrics = _aggregate(prior)

            rows.append({
                "player_id": player_id,
                "season": season,
                "player_type": player_type,
                "window_days": window,
                "as_of": as_of.isoformat(),
                "team": team,
                "games": len(current),
                "plate_appearances": sum(int(r.get("plate_appearances") or 0) for r in current),
                "batted_ball_events": sum(int(r.get("batted_ball_events") or 0) for r in current),
                "metrics": now_metrics,
                "prior_metrics": then_metrics,
                "delta": _delta(now_metrics, then_metrics),
                "updated_at": datetime.now(UTC).isoformat(),
            })

    return rows


def _upsert(client, rows: list[dict]) -> None:
    if not rows:
        return
    batch_size = 500
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        try:
            client.table("player_recent_form").upsert(
                batch,
                on_conflict="player_id,season,player_type,window_days",
            ).execute()
        except Exception:
            logger.exception("Upsert failed for batch starting at %d", i)
            raise


def _table_exists(client) -> bool:
    """True once the player_recent_form migration has been applied.

    Between shipping this script and running `supabase db push`, the table
    legitimately doesn't exist yet. Failing the whole nightly for that would
    also fail the snapshot ingest that shares the job and would open a spurious
    issue, so this one condition is a warn-and-skip. Every other error still
    fails loudly.
    """
    try:
        client.table("player_recent_form").select("player_id").limit(1).execute()
        return True
    except Exception as exc:  # noqa: BLE001 — inspecting the provider's message
        message = str(exc)
        if "player_recent_form" in message and (
            "PGRST205" in message
            or "does not exist" in message
            or "schema cache" in message
        ):
            return False
        raise


def run(season: Optional[int] = None) -> None:
    season = season or _resolve_season()
    client = _client()

    if not _table_exists(client):
        logger.warning(
            "public.player_recent_form is missing — run `supabase db push` to apply "
            "supabase/migrations/20260725000000_create_player_recent_form.sql. "
            "Skipping the rollup so the rest of the nightly still completes."
        )
        return

    # The longest window needs its own span plus the equal-length window before
    # it, so pull twice the widest window (with a little slack for off-days).
    lookback = max(WINDOW_DAYS) * 2 + 5
    since = date.today() - timedelta(days=lookback)

    logger.info("Fetching game logs for %d since %s…", season, since)
    logs = _fetch_logs(client, season, since)
    logger.info("  %d game-log rows", len(logs))

    if not logs:
        logger.warning("No game logs in range — nothing to roll up.")
        return

    # Anchor the windows to the latest game actually played, not to today. If
    # the pipeline is a day late, "last 7 days" should still mean seven days of
    # baseball rather than silently shrinking to six.
    as_of = max(date.fromisoformat(r["game_date"]) for r in logs)
    logger.info("Anchoring windows to %s", as_of)

    rows = build_rows(logs, as_of)
    logger.info("Built %d recent-form rows", len(rows))

    _upsert(client, rows)
    logger.info("Done.")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="Season to roll up (default: current).")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    args = _parse_args()
    run(season=args.season)
