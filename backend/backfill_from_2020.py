"""
Backfill remaining years (2020-2024) with enhanced actual values.
"""

import logging
import os
import sys
from datetime import datetime, timezone

from supabase import create_client
from ingest_v2 import build_snapshot_rows, chunks, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def main():
    url = SUPABASE_URL or os.environ.get("SUPABASE_URL", "")
    key = SUPABASE_SERVICE_ROLE_KEY or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase URL or service role key.")
        sys.exit(1)
    
    client = create_client(url, key)
    
    # Years remaining (2020-2024)
    years = [2020, 2021, 2022, 2023, 2024]
    
    logger.info("=" * 70)
    logger.info("BACKFILLING REMAINING YEARS: %s", years)
    logger.info("=" * 70)
    
    total_players = 0
    failed_years = []
    
    for season in years:
        logger.info("")
        logger.info("=" * 70)
        logger.info("PROCESSING SEASON %s", season)
        logger.info("=" * 70)
        
        try:
            os.environ["STATCAST_SEASON"] = str(season)
            rows = build_snapshot_rows(season)
            if not rows:
                logger.warning("No rows to upsert for %s, skipping.", season)
                failed_years.append(season)
                continue
            
            batch_size = 150
            for i, batch in enumerate(chunks(rows, batch_size)):
                logger.info("Upserting batch %d (%d rows) for %s...", i + 1, len(batch), season)
                try:
                    client.table("player_snapshots").upsert(batch, on_conflict="id,season").execute()
                except Exception as e:
                    error_str = str(e)
                    if "no unique or exclusion constraint" in error_str or "ON CONFLICT" in error_str:
                        logger.warning("Upsert failed, falling back to delete+insert")
                        for row in batch:
                            client.table("player_snapshots").delete().eq("id", row["id"]).eq("season", row["season"]).execute()
                        client.table("player_snapshots").insert(batch).execute()
                    else:
                        raise
            
            logger.info("Successfully upserted %d player snapshots for %s.", len(rows), season)
            total_players += len(rows)
            
        except Exception as e:
            logger.exception("Failed to process season %s: %s", season, e)
            failed_years.append(season)
            continue
    
    logger.info("")
    logger.info("=" * 70)
    logger.info("BACKFILL COMPLETE")
    logger.info("=" * 70)
    logger.info("Total players across remaining years: %d", total_players)
    logger.info("Successfully processed years: %s", [y for y in years if y not in failed_years])
    if failed_years:
        logger.warning("Failed years: %s", failed_years)


if __name__ == "__main__":
    main()
