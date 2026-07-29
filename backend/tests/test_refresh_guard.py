"""The gate that keeps many cron attempts from becoming many updates."""

from datetime import date, datetime, timezone

import pytest

import refresh_guard


@pytest.fixture
def frozen_now(monkeypatch):
    """Pin "now" to 09:00 UTC on 2026-07-28, mid-overnight-window."""

    _freeze(monkeypatch, hour=9)


def _freeze(monkeypatch, hour: int):
    """Pin "now" to `hour`:00 UTC on 2026-07-28."""

    class FakeDatetime(refresh_guard.datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 7, 28, hour, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(refresh_guard, "datetime", FakeDatetime)


def test_runs_when_yesterday_is_missing(monkeypatch, frozen_now):
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 12)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    run_season, run_trends, reason = refresh_guard.decide()
    assert run_season
    assert run_trends
    assert "2026-07-27" in reason


def test_skips_once_an_earlier_attempt_got_there(monkeypatch, frozen_now):
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 12)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: True)
    run_season, run_trends, reason = refresh_guard.decide()
    assert not run_season
    assert not run_trends
    assert "already ingested" in reason


def test_skips_an_off_day(monkeypatch, frozen_now):
    # No slate means nothing to close out, so every attempt would otherwise
    # re-run a full ingest against unchanged data.
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 0)
    monkeypatch.setattr(
        refresh_guard, "_already_ingested", lambda season, day: pytest.fail("should not be reached")
    )
    run_season, run_trends, reason = refresh_guard.decide()
    assert not run_season
    assert not run_trends
    assert "nothing to close out" in reason


def test_unreachable_schedule_does_not_block_the_refresh(monkeypatch, frozen_now):
    # A schedule API blip must not be able to silently stop the data pipeline.
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: -1)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    run_season, run_trends, _ = refresh_guard.decide()
    assert run_season
    assert run_trends


def test_yesterday_is_the_target_not_today(monkeypatch, frozen_now):
    seen = {}
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: seen.setdefault("day", day) and 12)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    refresh_guard.decide()
    assert seen["day"] == date(2026, 7, 27)


def test_daytime_attempt_catches_up_trends_but_not_the_season_line(monkeypatch):
    # Savant published yesterday's slate late, so the overnight window closed
    # with nothing ingested. The rolling windows can still be caught up (they
    # never reach past yesterday); the season line would fold today's
    # in-progress games in, so it waits for tonight.
    _freeze(monkeypatch, hour=17)
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 15)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    run_season, run_trends, reason = refresh_guard.decide()
    assert not run_season
    assert run_trends
    assert "trends only" in reason


def test_daytime_attempt_is_a_full_no_op_once_yesterday_landed(monkeypatch):
    _freeze(monkeypatch, hour=20)
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 15)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: True)
    run_season, run_trends, _ = refresh_guard.decide()
    assert not run_season
    assert not run_trends


def test_the_last_overnight_hour_still_writes_the_season_line(monkeypatch):
    # A 10:00 UTC cron that fires three hours late must still count as overnight.
    _freeze(monkeypatch, hour=12)
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 15)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    run_season, run_trends, _ = refresh_guard.decide()
    assert run_season
    assert run_trends
