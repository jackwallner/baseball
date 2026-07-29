"""Decides whether tonight's refresh still has work to do.

The nightly workflow fires several times inside the overnight window because a
GitHub cron is not a promise: a scheduled run routinely lands one to three
hours late, and under load one can be dropped entirely. Several attempts make
the window reliable. This guard is what keeps them from turning into several
*updates*: the app is meant to close out yesterday once, overnight, and then
hold still. A second pass later in the day would fold partial in-progress games
into the season line.

Exits 0 always. Writes two decisions to $GITHUB_OUTPUT, and prints the reason:

``run``
    The season snapshot (percentiles, standard stats). Overnight only. Running
    this mid-afternoon folds in-progress games into the season line, so the
    window closes at ``SEASON_WINDOW_END_HOUR_UTC`` and the day waits for the
    next night.

``run_trends``
    The per-game logs and rolling windows behind the Trends board. Safe at any
    hour because ``ingest_game_logs.py`` never reaches past yesterday, so a
    complete day can be caught up whenever Savant finally publishes it. This is
    what left the app reading "Through Jul 27" all day on 2026-07-29: Savant
    hadn't published the 28th by the time the last overnight attempt ran, and
    nothing looked again.

Both skip when:
  * MLB played no games yesterday (nothing to close out), or
  * yesterday's games are already in ``player_game_logs`` (an earlier attempt
    got there first).

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
"""

import logging
import os
import sys
from datetime import datetime, timedelta, timezone

import requests
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

MLB_SCHEDULE_URL = "https://statsapi.mlb.com/api/v1/schedule"
# The season snapshot is an all-day-still number, so it only ever gets written
# inside the overnight window. 13:00 UTC is 6am PT, which leaves room for a cron
# that fires up to three hours late and still lands before anyone is reading.
SEASON_WINDOW_END_HOUR_UTC = 13
# A game that hasn't finished isn't in Savant's export yet, so it can't be
# what we're waiting to ingest.
FINAL_STATES = {"Final", "Game Over", "Completed Early"}


def _resolve_season() -> int:
    now = datetime.now(UTC)
    return now.year if now.month >= 4 else now.year - 1


def _games_played(day) -> int:
    """Finished MLB games on a date, or -1 if the schedule can't be reached."""
    try:
        response = requests.get(
            MLB_SCHEDULE_URL,
            params={"sportId": 1, "date": day.isoformat()},
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        logger.warning("Schedule lookup failed (%s); assuming there was a slate", exc)
        return -1
    return sum(
        1
        for date_entry in payload.get("dates", [])
        for game in date_entry.get("games", [])
        if game.get("status", {}).get("detailedState") in FINAL_STATES
    )


def _already_ingested(season: int, day) -> bool:
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        logger.error("Missing Supabase credentials; letting the run proceed.")
        return False
    client = create_client(url, key)
    resp = (
        client.table("player_game_logs")
        .select("game_date")
        .eq("season", season)
        .order("game_date", desc=True)
        .limit(1)
        .execute()
    )
    if not resp.data:
        return False
    latest = datetime.strptime(resp.data[0]["game_date"], "%Y-%m-%d").date()
    return latest >= day


def decide() -> tuple[bool, bool, str]:
    """Return (run_season, run_trends, reason)."""
    season = _resolve_season()
    now = datetime.now(UTC)
    yesterday = now.date() - timedelta(days=1)

    played = _games_played(yesterday)
    if played == 0:
        return False, False, f"No MLB games finished on {yesterday}; nothing to close out."

    if _already_ingested(season, yesterday):
        return False, False, f"{yesterday} is already ingested; tonight's refresh is done."

    in_window = now.hour < SEASON_WINDOW_END_HOUR_UTC
    if not in_window:
        return (
            False,
            True,
            f"{yesterday} ({played} games) is not ingested yet, and it is past "
            f"{SEASON_WINDOW_END_HOUR_UTC:02d}:00 UTC: catching up trends only, "
            "season line waits for tonight.",
        )

    return True, True, f"{yesterday} ({played} games) is not ingested yet."


def main() -> None:
    run_season, run_trends, reason = decide()
    print(f"run={run_season} run_trends={run_trends}: {reason}")
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"run={'true' if run_season else 'false'}\n")
            handle.write(f"run_trends={'true' if run_trends else 'false'}\n")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    main()
    sys.exit(0)
