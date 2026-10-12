"""Books the next refresh attempt for the self-scheduling timer chain.

GitHub's cron is best effort. In October 2026 the attempts landed three to four
hours late, and after the schedule was edited on 2026-10-12 none of them fired
for eight hours, so the app went a day without the previous night's game. Each
refresh run now books its own successor through `refresh-timer.yml`, the same
chain the football, hockey and basketball apps use. The crons stay as a backup
that restarts a broken chain.

The slots are the old cron times. `refresh_guard.py` still decides what each
attempt does, so an extra or early wake-up costs a few seconds and writes
nothing.

Stdlib only: this runs on the runner's own python3 before any setup.
"""

import argparse
from datetime import datetime, timedelta, timezone

UTC = timezone.utc

# (hour, minute) in UTC. 07:23-10:23 are the overnight season attempts,
# 14:23-20:23 the daytime Trends sweeps. Minute 23 dodges GitHub's top-of-hour
# queue for the backup crons; the chain keeps it so both agree on the slots.
SLOTS = ((7, 23), (8, 23), (9, 23), (10, 23), (14, 23), (17, 23), (20, 23))

# A woken timer that lands within this long after a slot counts as that slot's
# attempt. Anything else is a hop: the timer job sleeps at most ~5.7 hours, so
# the overnight gap from 20:23 to 07:23 takes two jumps.
SLOT_GRACE = timedelta(minutes=90)

# The last daytime sweep. Only its freshness check may fail the run and open an
# issue; an earlier gap is still expected to close later in the day.
FINAL_SLOT_HOUR = 20


def _slot_times(now: datetime) -> list[datetime]:
    days = (now.date() - timedelta(days=1), now.date(), now.date() + timedelta(days=1))
    return [
        datetime(d.year, d.month, d.day, hour, minute, tzinfo=UTC)
        for d in days
        for hour, minute in SLOTS
    ]


def next_wait_seconds(now: datetime) -> int:
    """Seconds from `now` until the next slot, at least a minute away."""
    earliest = now + timedelta(minutes=1)
    upcoming = min(t for t in _slot_times(now) if t >= earliest)
    return max(60, int((upcoming - now).total_seconds()))


def current_slot(now: datetime):
    """The slot this run is the attempt for, or None for a hop."""
    for slot in reversed(_slot_times(now)):
        if slot <= now < slot + SLOT_GRACE:
            return slot
    return None


def is_final_attempt(now: datetime) -> bool:
    slot = current_slot(now)
    return slot is not None and slot.hour == FINAL_SLOT_HOUR


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-output", help="Append outputs to this GITHUB_OUTPUT file")
    args = parser.parse_args()

    now = datetime.now(UTC)
    wait = next_wait_seconds(now)
    slot = current_slot(now)
    lines = [
        f"wait_seconds={wait}",
        f"attempt={'true' if slot else 'false'}",
        f"final_attempt={'true' if is_final_attempt(now) else 'false'}",
    ]
    label = slot.strftime("%H:%M") if slot else "none (hop)"
    print(f"Slot {label}; next attempt in {wait}s")
    print("\n".join(lines))
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
