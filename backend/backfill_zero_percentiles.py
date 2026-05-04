"""Backfill K%/BB% percentiles for snapshots affected by the vfix53 bug.

For each season, fetch every player_snapshot row, parse the stored raw K%/BB%
values, compute league-relative percentiles (batters and pitchers separately,
matching the K%-lower-better / BB%-higher-better-for-batters semantics in
ingest.py), and patch the metrics in place. Only rows whose K% or BB% currently
sit at percentile == 0 with a populated raw value are updated.

Usage:
    python3 backfill_zero_percentiles.py --season 2026
    python3 backfill_zero_percentiles.py --from-year 2020 --to-year 2026
    python3 backfill_zero_percentiles.py --season 2026 --dry-run
"""

import argparse
import json
import logging
import os
import sys
from typing import Optional

import pandas as pd
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")


def parse_rate(value) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip().rstrip("%").strip()
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def fetch_season(client, season: int) -> list[dict]:
    rows: list[dict] = []
    batch_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots")
            .select("id,name,season,player_type,metrics")
            .eq("season", season)
            .range(offset, offset + batch_size - 1)
            .execute()
        )
        batch = resp.data or []
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < batch_size:
            break
        offset += batch_size
    return rows


def rank_percentiles(values: dict[int, float], lower_better: bool) -> dict[int, int]:
    if not values:
        return {}
    series = pd.Series(values, dtype=float)
    ranks = series.rank(method="average", ascending=not lower_better, pct=True)
    return {int(pid): max(1, min(100, int(round(pct * 100)))) for pid, pct in ranks.items()}


def backfill_season(client, season: int, dry_run: bool = False) -> dict:
    players = fetch_season(client, season)
    logger.info("Season %s: loaded %d players", season, len(players))

    batter_k: dict[int, float] = {}
    batter_bb: dict[int, float] = {}
    pitcher_k: dict[int, float] = {}
    pitcher_bb: dict[int, float] = {}

    for p in players:
        pid = p["id"]
        ptype = p.get("player_type") or "batter"
        is_pitcher = ptype == "pitcher"
        metrics = p.get("metrics") or []
        if isinstance(metrics, str):
            try:
                metrics = json.loads(metrics)
            except Exception:
                metrics = []

        for m in metrics:
            label = m.get("label")
            if label not in ("K%", "BB%"):
                continue
            rate = parse_rate(m.get("value") or m.get("actual_value"))
            if rate is None:
                continue
            if label == "K%":
                (pitcher_k if is_pitcher else batter_k)[pid] = rate
            else:
                (pitcher_bb if is_pitcher else batter_bb)[pid] = rate

    batter_k_pct = rank_percentiles(batter_k, lower_better=True)
    batter_bb_pct = rank_percentiles(batter_bb, lower_better=False)
    pitcher_k_pct = rank_percentiles(pitcher_k, lower_better=False)
    pitcher_bb_pct = rank_percentiles(pitcher_bb, lower_better=True)

    updates_planned = 0
    rows_updated = 0
    rows_unchanged = 0

    for p in players:
        pid = p["id"]
        ptype = p.get("player_type") or "batter"
        is_pitcher = ptype == "pitcher"
        metrics = p.get("metrics") or []
        if isinstance(metrics, str):
            try:
                metrics = json.loads(metrics)
            except Exception:
                metrics = []

        changed = False
        for m in metrics:
            label = m.get("label")
            if label not in ("K%", "BB%"):
                continue
            rate = parse_rate(m.get("value") or m.get("actual_value"))
            if rate is None:
                continue
            current_pct = m.get("percentile")
            if current_pct not in (None, 0):
                continue  # Trust existing native percentile.

            if label == "K%":
                new_pct = (pitcher_k_pct if is_pitcher else batter_k_pct).get(pid)
            else:
                new_pct = (pitcher_bb_pct if is_pitcher else batter_bb_pct).get(pid)

            if not new_pct:
                continue

            m["percentile"] = new_pct
            value_str = m.get("value") or m.get("actual_value") or f"{rate:.1f}%"
            m["display_value"] = f"{value_str} · {new_pct}th"
            changed = True
            updates_planned += 1

        if changed:
            if dry_run:
                rows_updated += 1
            else:
                client.table("player_snapshots").update({"metrics": metrics}).eq("id", pid).eq("season", season).execute()
                rows_updated += 1
        else:
            rows_unchanged += 1

    summary = {
        "season": season,
        "players": len(players),
        "metrics_patched": updates_planned,
        "rows_updated": rows_updated,
        "rows_unchanged": rows_unchanged,
        "dry_run": dry_run,
    }
    logger.info("Season %s done: %s", season, summary)
    return summary


def main() -> int:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        logger.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing")
        return 1

    parser = argparse.ArgumentParser()
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--from-year", type=int, default=2015)
    parser.add_argument("--to-year", type=int, default=2026)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    seasons = [args.season] if args.season else list(range(args.from_year, args.to_year + 1))
    results = []
    for season in seasons:
        results.append(backfill_season(client, season, dry_run=args.dry_run))

    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
