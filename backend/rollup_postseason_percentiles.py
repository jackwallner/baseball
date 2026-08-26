"""Where a postseason line would rank against the regular-season league.

The app's percentile bars are Savant's, and Savant publishes none for the
postseason. Rather than invent a percentile, this borrows the one Savant
already published: for each metric it reconstructs the regular-season curve
from player_snapshots (every qualified player's value paired with the
percentile Savant gave it), then looks the postseason value up on that curve.

So a 94.2 mph postseason average exit velocity gets the percentile Savant would
assign 94.2 mph. The claim is checkable against a page anyone can open, which a
percentile computed from the postseason field alone would not be.

The reference is the *same* season's regular season, deliberately, not a prior
one. It is complete before the first playoff pitch, so the curve is final, and
it shares the run environment: ball, parks and rules that a previous season's
curve would silently import differently.

Two things this is careful about:

  * Only metrics that stabilise inside a playoff sample are ranked. Exit
    velocity, hard-hit rate and whiff rate settle in tens of batted balls or a
    hundred pitches, which a deep run provides. xwOBA and the other expected
    stats need several hundred plate appearances and would render luck as a
    confident coloured bar.
  * A minimum sample, so a reliever with three clean innings does not arrive
    in the 99th percentile.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

import logging
import os
import sys
from bisect import bisect_left
from datetime import datetime, timezone
from typing import Any, Optional

from dotenv import load_dotenv
from supabase import create_client

from rollup_recent_form import _aggregate
from tables import POSTSEASON_TABLE

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

SNAPSHOTS_TABLE = "player_snapshots"
STATS_TABLE = "player_postseason_stats"

# Metric label in player_snapshots -> key in the aggregated postseason line.
#
# Descriptive only. Every entry here describes what a player did to the ball or
# to a pitch, and settles quickly. The expected-stat family (xwOBA, xBA, xSLG,
# xISO, xERA) is deliberately absent: those are outcome estimates that need
# several hundred plate appearances, and October never supplies one.
RANKABLE: dict[str, str] = {
    "EV": "ev_avg",
    "Max EV": "ev_max",
    "Hard-Hit%": "hardhit_pct",
    "Barrel%": "barrel_pct",
    "Whiff%": "whiff_pct",
    "Chase%": "chase_pct",
    "K%": "k_pct",
    "BB%": "bb_pct",
    "Fastball Velo": "fb_velo_avg",
    "Fastball Spin": "fb_spin_avg",
    "Bat Speed": "bat_speed",
    "Avg EV Against": "opp_ev_avg",
    "Max EV Against": "opp_ev_max",
}

# Below these a percentile is noise wearing a number's clothes. Batted-ball
# metrics are gated on batted balls, plate-discipline ones on pitches seen.
MIN_BATTED_BALLS = 25
MIN_PITCHES = 100
BATTED_BALL_METRICS = {
    "ev_avg", "ev_max", "hardhit_pct", "barrel_pct",
    "opp_ev_avg", "opp_ev_max",
}


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


def _numeric(raw: Any) -> Optional[float]:
    """Savant's published values carry %, mph and rpm; strip to the number."""
    if raw is None:
        return None
    text = str(raw).strip().replace("%", "").replace(",", "")
    for unit in (" mph", " rpm", " ft", " ft/s"):
        text = text.replace(unit, "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def build_curves(snapshots: list[dict]) -> dict[str, list[tuple[float, int]]]:
    """One sorted (value, percentile) curve per rankable metric.

    This is Savant's own mapping, read back off the season's leaderboard rather
    than recomputed, which is what keeps the postseason bar answerable to a
    page the user can open.
    """
    pairs: dict[str, list[tuple[float, int]]] = {}
    for row in snapshots:
        for metric in row.get("metrics") or []:
            label = metric.get("label")
            if label not in RANKABLE:
                continue
            value = _numeric(metric.get("value"))
            percentile = metric.get("percentile")
            if value is None or percentile is None:
                continue
            pairs.setdefault(RANKABLE[label], []).append((value, int(percentile)))

    curves: dict[str, list[tuple[float, int]]] = {}
    for key, points in pairs.items():
        # Two players can share a value and differ by a point of percentile;
        # sorting by value then percentile keeps the curve monotonic enough to
        # interpolate without the order flapping run to run.
        curves[key] = sorted(points)
    return curves


def percentile_for(curve: list[tuple[float, int]], value: float) -> Optional[int]:
    """Linear interpolation onto the regular-season curve, clamped to its ends.

    A postseason value beyond anything a qualified regular did lands on 0 or
    100 rather than extrapolating off the end of a distribution that has no
    more to say.
    """
    if not curve:
        return None
    values = [v for v, _ in curve]
    idx = bisect_left(values, value)
    if idx <= 0:
        return curve[0][1]
    if idx >= len(curve):
        return curve[-1][1]

    low_v, low_p = curve[idx - 1]
    high_v, high_p = curve[idx]
    if high_v == low_v:
        return high_p
    ratio = (value - low_v) / (high_v - low_v)
    return int(round(low_p + ratio * (high_p - low_p)))


def _meets_sample(key: str, batted_balls: int, pitches: int) -> bool:
    if key in BATTED_BALL_METRICS:
        return batted_balls >= MIN_BATTED_BALLS
    return pitches >= MIN_PITCHES


def build_metrics(
    line: dict[str, Any],
    curves: dict[str, list[tuple[float, int]]],
    batted_balls: int,
    pitches: int,
) -> list[dict[str, Any]]:
    """The metric rows one postseason player earns, sample gates applied."""
    out: list[dict[str, Any]] = []
    for label, key in RANKABLE.items():
        value = line.get(key)
        if value is None:
            continue
        if not _meets_sample(key, batted_balls, pitches):
            continue
        ranked = percentile_for(curves.get(key, []), float(value))
        if ranked is None:
            continue
        out.append({
            "id": f"post-{key}",
            "label": label,
            "value": str(value),
            "percentile": ranked,
            "category": "hitting",
        })
    return out


def _fetch_all(client, table: str, select: str, season: int) -> list[dict]:
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table(table)
            .select(select)
            .eq("season", season)
            .range(offset, offset + page_size - 1)
            .execute()
        )
        page = resp.data or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def run() -> None:
    season = _resolve_season()
    client = _client()

    logs = _fetch_all(client, POSTSEASON_TABLE, "*", season)
    if not logs:
        logger.info("No postseason game logs for %s yet; nothing to rank.", season)
        return

    snapshots = _fetch_all(client, SNAPSHOTS_TABLE, "metrics", season)
    curves = build_curves(snapshots)
    if not curves:
        logger.warning("No regular-season curves for %s; skipping.", season)
        return
    logger.info("Built %d regular-season curves", len(curves))

    by_player: dict[int, list[dict]] = {}
    for row in logs:
        by_player.setdefault(row["player_id"], []).append(row)

    updates = 0
    for player_id, player_logs in by_player.items():
        line = _aggregate(player_logs)
        batted_balls = sum(r.get("batted_ball_events") or 0 for r in player_logs)
        pitches = int(line.get("_pitches") or 0)
        metrics = build_metrics(line, curves, batted_balls, pitches)
        if not metrics:
            continue
        try:
            client.table(STATS_TABLE).update({"metrics": metrics}) \
                .eq("id", player_id).eq("season", season).execute()
            updates += 1
        except Exception:
            logger.exception("Failed to write metrics for %s", player_id)

    logger.info("Done. Ranked %d postseason players against the %s league.", updates, season)


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    run()
