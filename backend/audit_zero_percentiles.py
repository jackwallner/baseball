"""Audit script for the percentile-zero bug (vfix53).

Scans player_snapshots for K% / BB% metrics with percentile == 0 alongside a
populated raw value. Counts hits per season so we can verify the fix has
eradicated the hardcoded-zero fallback.

Usage:
    python3 audit_zero_percentiles.py [--season 2026] [--limit 20]
"""

import argparse
import json
import logging
import os
import sys
from collections import defaultdict

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

TARGET_LABELS = {"K%", "BB%"}


def fetch_season(client, season: int) -> list[dict]:
    rows: list[dict] = []
    batch_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots")
            .select("id,name,team,season,player_type,metrics")
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


def audit_season(client, season: int, sample_limit: int = 20) -> dict:
    players = fetch_season(client, season)
    total_metrics_seen = 0
    zero_pct_with_value = 0
    zero_pct_total = 0
    samples = []

    for p in players:
        metrics = p.get("metrics") or []
        if isinstance(metrics, str):
            try:
                metrics = json.loads(metrics)
            except Exception:
                metrics = []
        for m in metrics:
            if m.get("label") not in TARGET_LABELS:
                continue
            total_metrics_seen += 1
            pct = m.get("percentile")
            value = m.get("value") or m.get("actual_value") or ""
            if pct == 0:
                zero_pct_total += 1
                if value and str(value).strip():
                    zero_pct_with_value += 1
                    if len(samples) < sample_limit:
                        samples.append({
                            "id": p.get("id"),
                            "name": p.get("name"),
                            "team": p.get("team"),
                            "label": m.get("label"),
                            "value": value,
                        })

    return {
        "season": season,
        "players": len(players),
        "k_bb_metrics": total_metrics_seen,
        "zero_percentile_total": zero_pct_total,
        "zero_percentile_with_raw_value": zero_pct_with_value,
        "samples": samples,
    }


def main() -> int:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        logger.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing")
        return 1

    parser = argparse.ArgumentParser()
    parser.add_argument("--season", type=int, default=None, help="Audit a single season")
    parser.add_argument("--from-year", type=int, default=2015)
    parser.add_argument("--to-year", type=int, default=2026)
    parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args()

    client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    seasons = [args.season] if args.season else list(range(args.from_year, args.to_year + 1))
    summary = []
    for season in seasons:
        logger.info("Auditing season %s", season)
        result = audit_season(client, season, sample_limit=args.limit)
        summary.append(result)
        logger.info(
            "Season %s: players=%d k/bb_metrics=%d zero_pct=%d zero_pct_with_value=%d",
            result["season"],
            result["players"],
            result["k_bb_metrics"],
            result["zero_percentile_total"],
            result["zero_percentile_with_raw_value"],
        )
        if result["samples"]:
            logger.info("  Samples (first %d): %s", len(result["samples"]), result["samples"][:5])

    print(json.dumps(summary, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
