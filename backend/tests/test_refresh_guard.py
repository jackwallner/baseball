"""The gate that keeps four cron attempts from becoming four updates."""

from datetime import date, datetime, timezone

import pytest

import refresh_guard


@pytest.fixture
def frozen_now(monkeypatch):
    """Pin "now" to 09:00 UTC on 2026-07-28, mid-overnight-window."""

    class FakeDatetime(refresh_guard.datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 7, 28, 9, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(refresh_guard, "datetime", FakeDatetime)


def test_runs_when_yesterday_is_missing(monkeypatch, frozen_now):
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 12)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    should_run, reason = refresh_guard.decide()
    assert should_run
    assert "2026-07-27" in reason


def test_skips_once_an_earlier_attempt_got_there(monkeypatch, frozen_now):
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 12)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: True)
    should_run, reason = refresh_guard.decide()
    assert not should_run
    assert "already ingested" in reason


def test_skips_an_off_day(monkeypatch, frozen_now):
    # No slate means nothing to close out, so every attempt would otherwise
    # re-run a full ingest against unchanged data.
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: 0)
    monkeypatch.setattr(
        refresh_guard, "_already_ingested", lambda season, day: pytest.fail("should not be reached")
    )
    should_run, reason = refresh_guard.decide()
    assert not should_run
    assert "nothing to close out" in reason


def test_unreachable_schedule_does_not_block_the_refresh(monkeypatch, frozen_now):
    # A schedule API blip must not be able to silently stop the data pipeline.
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: -1)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    should_run, _ = refresh_guard.decide()
    assert should_run


def test_yesterday_is_the_target_not_today(monkeypatch, frozen_now):
    seen = {}
    monkeypatch.setattr(refresh_guard, "_games_played", lambda day: seen.setdefault("day", day) and 12)
    monkeypatch.setattr(refresh_guard, "_already_ingested", lambda season, day: False)
    refresh_guard.decide()
    assert seen["day"] == date(2026, 7, 27)
