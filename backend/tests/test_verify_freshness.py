"""The check that tells a green run apart from a stale one."""

from datetime import date, datetime, timezone

import pytest

import verify_freshness


@pytest.fixture
def frozen_now(monkeypatch):
    """Pin "now" to 2026-07-29, so "yesterday" is the 28th."""

    class FakeDatetime(verify_freshness.datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 7, 29, 12, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(verify_freshness, "datetime", FakeDatetime)


def _tables(monkeypatch, logs, trends, postseason=None):
    """Stub the three dates check() reads: regular-season logs, the rolling
    windows, and (once October arrives) the postseason logs."""
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-role")
    monkeypatch.setattr(verify_freshness, "create_client", lambda url, key: object())

    by_table = {
        "player_game_logs": logs,
        "player_postseason_game_logs": postseason,
        "player_recent_form": trends,
    }
    monkeypatch.setattr(
        verify_freshness,
        "_max_date",
        lambda client, table, column, season: by_table[table],
    )


def test_fresh_when_both_tables_reach_yesterday(monkeypatch, frozen_now):
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 15)
    _tables(monkeypatch, date(2026, 7, 28), date(2026, 7, 28))
    is_fresh, message = verify_freshness.check()
    assert is_fresh
    assert "2026-07-28" in message


def test_stale_when_savant_had_not_published_yesterday(monkeypatch, frozen_now):
    # The 2026-07-29 failure: every step exited 0 and the data still stopped on
    # the 27th, which is what the app was showing all day.
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 15)
    _tables(monkeypatch, date(2026, 7, 27), date(2026, 7, 27))
    is_fresh, message = verify_freshness.check()
    assert not is_fresh
    assert "game logs reach 2026-07-27" in message
    assert "recent-form windows reach 2026-07-27" in message


def test_stale_when_only_the_rollup_lagged(monkeypatch, frozen_now):
    # Logs landed but the rollup died after them, so the Trends board is behind
    # data that is actually sitting in the table.
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 15)
    _tables(monkeypatch, date(2026, 7, 28), date(2026, 7, 27))
    is_fresh, message = verify_freshness.check()
    assert not is_fresh
    assert "recent-form windows" in message
    assert "game logs" not in message


def test_an_off_day_is_not_stale(monkeypatch, frozen_now):
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 0)
    is_fresh, message = verify_freshness.check()
    assert is_fresh
    assert "nothing to be behind on" in message


def test_missing_credentials_is_not_reported_as_stale(monkeypatch, frozen_now):
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 15)
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)
    is_fresh, message = verify_freshness.check()
    assert is_fresh
    assert "skipping" in message


def test_only_the_final_attempt_fails_the_run(monkeypatch, frozen_now, capsys):
    monkeypatch.setattr(verify_freshness, "check", lambda: (False, "Data is behind: …"))

    monkeypatch.delenv("FINAL_ATTEMPT", raising=False)
    verify_freshness.main()
    assert "stale (an earlier attempt" in capsys.readouterr().out

    monkeypatch.setenv("FINAL_ATTEMPT", "true")
    with pytest.raises(SystemExit) as exit_info:
        verify_freshness.main()
    assert exit_info.value.code == 1


def test_october_does_not_call_frozen_windows_stale(monkeypatch):
    """The playoffs are on and the rolling windows have correctly stopped.

    Recent Form is a regular-season board, so its as_of stays on the last day
    of the regular season all October. Holding it to "yesterday" would fail the
    nightly run and open an issue every single night of the postseason.
    """

    class FakeDatetime(verify_freshness.datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(verify_freshness, "datetime", FakeDatetime)
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 2)
    _tables(
        monkeypatch,
        logs=date(2026, 9, 27),
        trends=date(2026, 9, 27),
        postseason=date(2026, 10, 14),
    )
    is_fresh, message = verify_freshness.check()
    assert is_fresh, message


def test_october_still_catches_a_postseason_ingest_that_stalled(monkeypatch):
    """Relaxing the windows must not relax the game logs."""

    class FakeDatetime(verify_freshness.datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(verify_freshness, "datetime", FakeDatetime)
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 2)
    _tables(
        monkeypatch,
        logs=date(2026, 9, 27),
        trends=date(2026, 9, 27),
        postseason=date(2026, 10, 11),
    )
    is_fresh, message = verify_freshness.check()
    assert not is_fresh
    assert "game logs reach 2026-10-11" in message


def test_in_season_a_lagging_rollup_still_fails(monkeypatch, frozen_now):
    """The October relaxation must not leak into the regular season: logs
    current, rollup behind, still stale."""
    monkeypatch.setattr(verify_freshness, "_finished_games", lambda day: 15)
    _tables(monkeypatch, logs=date(2026, 7, 28), trends=date(2026, 7, 27))
    is_fresh, message = verify_freshness.check()
    assert not is_fresh
    assert "recent-form windows reach 2026-07-27" in message
