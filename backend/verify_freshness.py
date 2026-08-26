"""Checks that the data actually moved, not just that the pipeline exited 0.

On 2026-07-29 every attempt of the nightly refresh reported success while
closing out nothing: Savant hadn't published the 28th yet, so `statcast()`
returned only the 27th, the rollup re-anchored to the 27th, and the app spent
the day saying "Through Jul 27" under a Settings screen that said it had been
updated that morning. A green run and stale data looked identical.

This is what makes them look different. It asks the two questions the app asks:

  * does ``player_game_logs`` have yesterday, and
  * does ``player_recent_form.as_of`` reach yesterday (the rollup can lag the
    logs if it failed after they landed).

A gap is a warning on the early attempts, because the whole point of several
attempts is that the first ones may be too early for Savant. On the final
attempt of the day (``FINAL_ATTEMPT=true``) it exits 1, which is what opens the
issue: by then a gap means the day genuinely didn't land and needs a human.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FINAL_ATTEMPT (optional).
"""

import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Optional

import requests
from dotenv import load_dotenv
from supabase import create_client

from tables import POSTSEASON_TABLE, REGULAR_SEASON_TABLE

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

MLB_SCHEDULE_URL = "https://statsapi.mlb.com/api/v1/schedule"
FINAL_STATES = {"Final", "Game Over", "Completed Early"}


def _resolve_season() -> int:
    now = datetime.now(UTC)
    return now.year if now.month >= 4 else now.year - 1


def _finished_games(day: date) -> int:
    """Finished MLB games on a date, or -1 if the schedule can't be reached."""
    try:
        response = requests.get(
            MLB_SCHEDULE_URL, params={"sportId": 1, "date": day.isoformat()}, timeout=30
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        logger.warning("Schedule lookup failed (%s)", exc)
        return -1
    return sum(
        1
        for entry in payload.get("dates", [])
        for game in entry.get("games", [])
        if game.get("status", {}).get("detailedState") in FINAL_STATES
    )


def _max_date(client, table: str, column: str, season: int) -> Optional[date]:
    resp = (
        client.table(table)
        .select(column)
        .eq("season", season)
        .order(column, desc=True)
        .limit(1)
        .execute()
    )
    if not resp.data or not resp.data[0].get(column):
        return None
    return datetime.strptime(resp.data[0][column], "%Y-%m-%d").date()


def check() -> tuple[bool, str]:
    """Return (is_fresh, message)."""
    season = _resolve_season()
    yesterday = datetime.now(UTC).date() - timedelta(days=1)

    if _finished_games(yesterday) == 0:
        return True, f"No MLB games finished on {yesterday}; nothing to be behind on."

    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        # Can't verify isn't the same as stale, and a missing secret shouldn't
        # be reported as a data problem.
        return True, "Missing Supabase credentials; skipping the freshness check."

    client = create_client(url, key)

    # Game logs are checked across both phases, because in October the newest
    # game we hold is a playoff game and it lives in the postseason table.
    regular_through = _max_date(client, REGULAR_SEASON_TABLE, "game_date", season)
    post_through = _max_date(client, POSTSEASON_TABLE, "game_date", season)
    logs_through = max((d for d in (regular_through, post_through) if d), default=None)

    trends_through = _max_date(client, "player_recent_form", "as_of", season)

    # The rolling windows are regular-season windows by design, so once the
    # playoffs begin they correctly stop moving, and holding them to
    # "yesterday" would report a frozen-by-design number as stale every night
    # of October and open an issue for it.
    #
    # The relaxation is deliberately narrow: it applies only once a postseason
    # game is newer than any regular-season one, which is the only situation in
    # which the windows are *supposed* to be behind. In season, a lagging
    # rollup is still a lagging rollup and still fails.
    postseason_underway = post_through is not None and (
        regular_through is None or post_through > regular_through
    )
    trends_expected = regular_through if postseason_underway and regular_through else yesterday

    gaps = []
    if logs_through is None or logs_through < yesterday:
        gaps.append(f"game logs reach {logs_through}, expected {yesterday}")
    if trends_through is None or trends_through < trends_expected:
        gaps.append(f"recent-form windows reach {trends_through}, expected {trends_expected}")

    if gaps:
        return False, "Data is behind: " + "; ".join(gaps)
    return True, f"Data covers {yesterday}: logs and rolling windows both current."


def main() -> None:
    is_fresh, message = check()
    final_attempt = os.environ.get("FINAL_ATTEMPT", "").lower() == "true"

    if is_fresh:
        print(f"fresh: {message}")
        return

    if final_attempt:
        print(f"stale (final attempt of the day): {message}")
        sys.exit(1)

    print(f"stale (an earlier attempt, Savant may not have published yet): {message}")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    main()
