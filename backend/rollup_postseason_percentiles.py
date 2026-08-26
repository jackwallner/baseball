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

Every metric is ranked and every player is ranked. The postseason is a small
sample by construction, and gating on sample size would empty the board of the
players the board exists for: a team that goes out in the wild-card round
contributes three games or nothing at all. The samples are what they are, and a
reader who has opened a postseason board knows that.

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

# Metric label in player_snapshots -> key in the aggregated postseason line,
# per side of the ball.
#
# The split is not cosmetic. A pitcher's xwOBA is the xwOBA he allowed, and his
# percentile runs the other way: 0.325 allowed sits at the 31st percentile,
# where a hitter posting 0.325 sits far higher. One merged curve would rank
# every pitcher as though he were batting.
BATTER_METRICS: dict[str, str] = {
    "xwOBA": "xwoba",
    "xBA": "xba",
    "xSLG": "xslg",
    "xISO": "xiso",
    "Barrel%": "barrel_pct",
    "Hard-Hit%": "hardhit_pct",
    "EV": "ev_avg",
    "Max EV": "ev_max",
    "Whiff%": "whiff_pct",
    "Chase%": "chase_pct",
    "K%": "k_pct",
    "BB%": "bb_pct",
    "Bat Speed": "bat_speed",
}

PITCHER_METRICS: dict[str, str] = {
    "xwOBA": "opp_xwoba",
    "xBA": "opp_xba",
    "xSLG": "opp_xslg",
    "Barrel%": "opp_barrel_pct",
    "Hard-Hit%": "opp_hardhit_pct",
    "Avg EV Against": "opp_ev_avg",
    "Max EV Against": "opp_ev_max",
    "Whiff%": "whiff_pct",
    "Chase%": "chase_pct",
    "K%": "k_pct",
    "BB%": "bb_pct",
    "Fastball Velo": "fb_velo_avg",
    "Fastball Spin": "fb_spin_avg",
}

METRICS_BY_TYPE: dict[str, dict[str, str]] = {
    "batter": BATTER_METRICS,
    "pitcher": PITCHER_METRICS,
}

CATEGORY_BY_TYPE = {"batter": "hitting", "pitcher": "pitching"}


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


def build_curves(snapshots: list[dict]) -> dict[tuple[str, str], list[tuple[float, int]]]:
    """One sorted (value, percentile) curve per side of the ball and metric.

    This is Savant's own mapping, read back off the season's leaderboard rather
    than recomputed, which is what keeps the postseason bar answerable to a page
    the user can open.

    Keyed by player type because the two sides disagree about which direction is
    good: a pitcher's curve falls as the value rises. Two-way players are left
    out of the curves entirely rather than counted on a side they only half
    belong to; they are still ranked, once per side, against everyone else's.
    """
    pairs: dict[tuple[str, str], list[tuple[float, int]]] = {}
    for row in snapshots:
        player_type = row.get("player_type")
        metric_map = METRICS_BY_TYPE.get(player_type)
        if metric_map is None:
            continue
        for metric in row.get("metrics") or []:
            label = metric.get("label")
            if label not in metric_map:
                continue
            value = _numeric(metric.get("value"))
            percentile = metric.get("percentile")
            if value is None or percentile is None:
                continue
            pairs.setdefault((player_type, metric_map[label]), []).append(
                (value, int(percentile))
            )

    # Two players can share a value and differ by a point of percentile;
    # sorting by value then percentile keeps the curve monotonic enough to
    # interpolate without the order flapping run to run.
    return {key: sorted(points) for key, points in pairs.items()}


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


def build_metrics(
    line: dict[str, Any],
    curves: dict[tuple[str, str], list[tuple[float, int]]],
    player_type: str,
) -> list[dict[str, Any]]:
    """Every metric this side has a value for, ranked against its own curve.

    No sample gate. The postseason is a small sample by construction, and a
    threshold would empty the board of the players it exists for: a wild-card
    exit is three games, and a metric hidden for everyone but the two teams
    still playing in late October is a metric nobody sees.
    """
    metric_map = METRICS_BY_TYPE.get(player_type)
    if metric_map is None:
        return []

    out: list[dict[str, Any]] = []
    for label, key in metric_map.items():
        value = line.get(key)
        if value is None:
            continue
        ranked = percentile_for(curves.get((player_type, key), []), float(value))
        if ranked is None:
            continue
        out.append({
            # Namespaced by side, so a two-way player's xwOBA posted and xwOBA
            # allowed do not collapse into one row.
            "id": f"post-{player_type}-{key}",
            "label": label,
            "value": str(value),
            "percentile": ranked,
            "category": CATEGORY_BY_TYPE[player_type],
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

    # Keyed by side as well as player, because a two-way player has separate
    # batter and pitcher rows and collapsing them would aggregate the balls he
    # hit together with the balls he gave up.
    by_side: dict[tuple[int, str], list[dict]] = {}
    for row in logs:
        by_side.setdefault((row["player_id"], row.get("player_type") or "batter"), []).append(row)

    metrics_by_player: dict[int, list[dict]] = {}
    for (player_id, player_type), side_logs in by_side.items():
        line = _aggregate(side_logs)
        metrics = build_metrics(line, curves, player_type)
        if metrics:
            metrics_by_player.setdefault(player_id, []).extend(metrics)

    updates = 0
    for player_id, metrics in metrics_by_player.items():
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
