"""One-shot cleanup for existing player_snapshots rows.

Fixes data quality issues left by older ingestion bugs:
  1. Drops K%/BB% metrics whose actual_value is >100% or <0% (caused by
     dividing pitcher SO/BB by the bogus pitcher-as-batter PA).
  2. Rewrites every display_value string with a correct ordinal suffix
     ("73th" -> "73rd", "1th" -> "1st", etc.).

Run after the ingest.py fixes are deployed; the next nightly ingest will
repopulate dropped rates with correct percentiles from BF.

Usage:
    python3 backfill_data_quality.py [--dry-run] [--season YYYY]
"""

import argparse
import logging
import os
import re
import sys
from typing import Optional

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def ordinal_suffix(n: int) -> str:
    if 10 <= (n % 100) <= 20:
        return "th"
    return {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")


_NUM_RE = re.compile(r"-?\d+\.?\d*")


def _rate_pct(actual_value) -> Optional[float]:
    if not actual_value or not isinstance(actual_value, str):
        return None
    m = _NUM_RE.search(actual_value)
    return float(m.group()) if m else None


RATE_LABELS = {"K%", "BB%"}


def clean_metrics(metrics: list) -> tuple[list, dict]:
    """Return (new_metrics, stats) — stats counts edits and drops."""
    stats = {"dropped_rates": 0, "suffix_fixes": 0}
    out = []
    for m in metrics or []:
        # Drop impossible K%/BB% values
        if m.get("label") in RATE_LABELS:
            v = _rate_pct(m.get("actual_value") or m.get("value"))
            if v is not None and (v < 0 or v > 100):
                stats["dropped_rates"] += 1
                continue

        dv = m.get("display_value") or ""
        if dv:
            # Find <number><suffix> and correct the suffix
            def fix(match):
                n = int(match.group(1))
                got = match.group(2)
                correct = ordinal_suffix(n)
                if got != correct:
                    stats["suffix_fixes"] += 1
                return f"{n}{correct}"

            new_dv = re.sub(r"(\d+)(st|nd|rd|th)\b", fix, dv)
            if new_dv != dv:
                m = {**m, "display_value": new_dv}
        out.append(m)
    return out, stats


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--season", type=int, help="Only process this season")
    parser.add_argument("--limit", type=int, help="Stop after N rows (testing)")
    args = parser.parse_args()

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        sys.exit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
    sb = create_client(url, key)

    page = 1000
    start = 0
    total_rows = 0
    rows_changed = 0
    total_drops = 0
    total_suffix = 0

    while True:
        q = sb.table("player_snapshots").select("id,season,metrics")
        if args.season:
            q = q.eq("season", args.season)
        chunk = q.range(start, start + page - 1).execute().data
        if not chunk:
            break
        for row in chunk:
            total_rows += 1
            new_metrics, stats = clean_metrics(row.get("metrics") or [])
            if stats["dropped_rates"] or stats["suffix_fixes"]:
                rows_changed += 1
                total_drops += stats["dropped_rates"]
                total_suffix += stats["suffix_fixes"]
                if not args.dry_run:
                    sb.table("player_snapshots").update({"metrics": new_metrics}).eq(
                        "id", row["id"]
                    ).eq("season", row["season"]).execute()
            if args.limit and total_rows >= args.limit:
                break
        if args.limit and total_rows >= args.limit:
            break
        if len(chunk) < page:
            break
        start += page
        if total_rows % 2000 == 0:
            logger.info("Processed %d rows...", total_rows)

    logger.info(
        "Done. rows=%d changed=%d dropped_rates=%d suffix_fixes=%d dry_run=%s",
        total_rows, rows_changed, total_drops, total_suffix, args.dry_run,
    )


if __name__ == "__main__":
    main()
