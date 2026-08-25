"""Per-game aggregation tests for the Recent Form pipeline.

The subtle cases here are the ones Statcast's column semantics make easy to get
wrong: xBA/xSLG are null on strikeouts and walks, xwOBA has its own denominator
column, and Whiff%/Chase% live on pitches that mostly aren't the final pitch of
a plate appearance.
"""

import pandas as pd
import pytest

from ingest_game_logs import (
    _aggregate_batters,
    _aggregate_pitchers,
    _allowed_game_types,
    _filter_game_types,
)


def _pitch(**overrides):
    """One pitch row with the columns the aggregators read."""
    row = {
        "batter": 1,
        "pitcher": 2,
        "game_date": pd.Timestamp("2026-07-18"),
        "game_year": 2026,
        "game_type": "R",
        "home_team": "KC",
        "away_team": "DET",
        "inning_topbot": "Top",
        "description": "ball",
        "zone": 5,
        "events": None,
        "launch_speed": None,
        "launch_angle": None,
        "launch_speed_angle": None,
        "estimated_woba_using_speedangle": None,
        "estimated_ba_using_speedangle": None,
        "estimated_slg_using_speedangle": None,
        "woba_denom": None,
        "bat_speed": None,
        "swing_length": None,
        "bb_type": None,
        "release_speed": None,
        "release_spin_rate": None,
        "release_extension": None,
        "pitch_type": "FF",
    }
    row.update(overrides)
    return row


def _frame(rows):
    return pd.DataFrame([_pitch(**r) for r in rows])


@pytest.fixture
def strikeout_and_walk_frame():
    """Two plate appearances: one strikeout, one walk, one single.

    Statcast leaves estimated_ba/estimated_slg null on the strikeout and the
    walk, and only the strikeout counts as an at-bat.
    """
    return _frame([
        {
            "description": "swinging_strike",
            "events": "strikeout",
            "estimated_woba_using_speedangle": 0.0,
            "woba_denom": 1,
        },
        {
            "description": "ball",
            "events": "walk",
            "estimated_woba_using_speedangle": 0.69,
            "woba_denom": 1,
        },
        {
            "description": "hit_into_play",
            "events": "single",
            "launch_speed": 100.0,
            "launch_angle": 12.0,
            "estimated_woba_using_speedangle": 0.9,
            "estimated_ba_using_speedangle": 0.6,
            "estimated_slg_using_speedangle": 0.8,
            "woba_denom": 1,
        },
    ])


def test_xba_counts_strikeouts_as_outs_and_excludes_walks(strikeout_and_walk_frame):
    """The trap: a plain mean over non-null xBA would report .600, not .300.

    Savant's denominator is at-bats — the strikeout is an 0-for and the walk
    isn't an at-bat at all.
    """
    metrics = _aggregate_batters(strikeout_and_walk_frame)[0]["metrics"]
    assert metrics["_at_bats"] == 2
    assert metrics["xba"] == pytest.approx(0.300)
    assert metrics["xslg"] == pytest.approx(0.400)
    assert metrics["xiso"] == pytest.approx(0.100)


def test_xwoba_divides_by_woba_denom(strikeout_and_walk_frame):
    """xwOBA includes the walk, so it spans all three plate appearances."""
    metrics = _aggregate_batters(strikeout_and_walk_frame)[0]["metrics"]
    assert metrics["_woba_denom"] == pytest.approx(3.0)
    assert metrics["xwoba"] == pytest.approx((0.0 + 0.69 + 0.9) / 3, abs=1e-3)


def test_sacrifice_bunt_excluded_from_xwoba():
    """woba_denom is 0 on a sac bunt, so it must not dilute the rate."""
    frame = _frame([
        {
            "description": "hit_into_play",
            "events": "single",
            "launch_speed": 95.0,
            "estimated_woba_using_speedangle": 0.9,
            "estimated_ba_using_speedangle": 0.5,
            "estimated_slg_using_speedangle": 0.5,
            "woba_denom": 1,
        },
        {
            "description": "hit_into_play",
            "events": "sac_bunt",
            "launch_speed": 40.0,
            "woba_denom": 0,
        },
    ])
    metrics = _aggregate_batters(frame)[0]["metrics"]
    assert metrics["_woba_denom"] == pytest.approx(1.0)
    assert metrics["xwoba"] == pytest.approx(0.9)


def test_whiff_and_chase_use_every_pitch_not_just_terminal_rows():
    """Two whiffs happen mid-PA; only the third pitch ends it.

    Aggregating the terminal-PA frame alone would report a single swing.
    """
    frame = _frame([
        {"description": "swinging_strike", "zone": 13},   # chase + whiff
        {"description": "foul", "zone": 5},               # in-zone swing
        {"description": "swinging_strike", "zone": 12},   # chase + whiff
        {
            "description": "hit_into_play",
            "zone": 4,
            "events": "field_out",
            "launch_speed": 88.0,
            "estimated_woba_using_speedangle": 0.1,
            "estimated_ba_using_speedangle": 0.1,
            "estimated_slg_using_speedangle": 0.1,
            "woba_denom": 1,
        },
    ])
    metrics = _aggregate_batters(frame)[0]["metrics"]
    assert metrics["_pitches"] == 4
    assert metrics["_swings"] == 4
    assert metrics["_oz_pitches"] == 2
    assert metrics["whiff_pct"] == pytest.approx(50.0)
    assert metrics["chase_pct"] == pytest.approx(100.0)


def test_bat_tracking_averages_swings_only():
    """Taken pitches carry no bat_speed, so they must not enter the mean."""
    frame = _frame([
        {"description": "ball", "zone": 13, "bat_speed": None, "swing_length": None},
        {"description": "foul", "zone": 5, "bat_speed": 70.0, "swing_length": 7.0},
        {
            "description": "hit_into_play",
            "zone": 5,
            "bat_speed": 80.0,
            "swing_length": 7.4,
            "events": "single",
            "launch_speed": 100.0,
            "estimated_woba_using_speedangle": 0.9,
            "estimated_ba_using_speedangle": 0.6,
            "estimated_slg_using_speedangle": 0.8,
            "woba_denom": 1,
        },
    ])
    metrics = _aggregate_batters(frame)[0]["metrics"]
    assert metrics["bat_speed"] == pytest.approx(75.0)
    assert metrics["swing_length"] == pytest.approx(7.2)


def test_sweetspot_uses_launch_angle_band():
    """Savant's sweet spot is a launch angle of 8-32 degrees, inclusive."""
    frame = _frame([
        {
            "description": "hit_into_play", "events": "field_out",
            "launch_speed": 90.0, "launch_angle": 8.0,
            "estimated_woba_using_speedangle": 0.2, "woba_denom": 1,
        },
        {
            "description": "hit_into_play", "events": "field_out",
            "launch_speed": 90.0, "launch_angle": 45.0,
            "estimated_woba_using_speedangle": 0.0, "woba_denom": 1,
        },
    ])
    metrics = _aggregate_batters(frame)[0]["metrics"]
    assert metrics["sweetspot_pct"] == pytest.approx(50.0)
    assert metrics["la_avg"] == pytest.approx(26.5)


def test_fastball_velo_excludes_offspeed():
    """Savant reports velo as a fastball figure; a changeup must not drag it."""
    frame = _frame([
        {
            "description": "hit_into_play", "events": "field_out", "pitch_type": "FF",
            "launch_speed": 95.0, "release_speed": 97.0, "release_spin_rate": 2400.0,
            "estimated_woba_using_speedangle": 0.2, "woba_denom": 1,
        },
        {"description": "ball", "pitch_type": "CH", "release_speed": 85.0, "release_spin_rate": 1600.0},
    ])
    metrics = _aggregate_pitchers(frame)[0]["metrics"]
    assert metrics["fb_velo_avg"] == pytest.approx(97.0)
    assert metrics["fb_spin_avg"] == pytest.approx(2400.0)
    # The all-pitch average still exists and is genuinely lower.
    assert metrics["velo_avg"] == pytest.approx(91.0)


def test_pitcher_row_carries_pitch_shape_and_batted_ball_mix():
    frame = _frame([
        {
            "description": "hit_into_play", "events": "field_out",
            "launch_speed": 95.0, "bb_type": "ground_ball",
            "release_speed": 95.0, "release_spin_rate": 2400.0,
            "release_extension": 6.5,
            "estimated_woba_using_speedangle": 0.2,
            "estimated_ba_using_speedangle": 0.2,
            "estimated_slg_using_speedangle": 0.2,
            "woba_denom": 1,
        },
        {
            "description": "hit_into_play", "events": "field_out",
            "launch_speed": 80.0, "bb_type": "fly_ball",
            "release_speed": 97.0, "release_spin_rate": 2500.0,
            "release_extension": 6.7,
            "estimated_woba_using_speedangle": 0.1,
            "estimated_ba_using_speedangle": 0.1,
            "estimated_slg_using_speedangle": 0.1,
            "woba_denom": 1,
        },
    ])
    metrics = _aggregate_pitchers(frame)[0]["metrics"]
    assert metrics["velo_avg"] == pytest.approx(96.0)
    assert metrics["spin_avg"] == pytest.approx(2450.0)
    assert metrics["extension_avg"] == pytest.approx(6.6)
    assert metrics["gb_pct"] == pytest.approx(50.0)
    assert metrics["fb_pct"] == pytest.approx(50.0)
    assert metrics["opp_xwoba"] == pytest.approx(0.15)


def test_game_date_serializes_as_plain_date():
    """The column is a Postgres date; a naive str(Timestamp) adds a time."""
    frame = _frame([
        {
            "description": "hit_into_play", "events": "single",
            "launch_speed": 95.0,
            "estimated_woba_using_speedangle": 0.9,
            "estimated_ba_using_speedangle": 0.6,
            "estimated_slg_using_speedangle": 0.8,
            "woba_denom": 1,
        },
    ])
    assert _aggregate_batters(frame)[0]["game_date"] == "2026-07-18"


def test_empty_frame_yields_no_rows():
    assert _aggregate_batters(pd.DataFrame()) == []
    assert _aggregate_pitchers(pd.DataFrame()) == []


class TestIngestWindow:
    """The refresh closes out finished days only.

    Today's slate is either unplayed or half-played. A half-played day upserted
    into the game logs drags every rolling window and the team form card built
    on them toward a partial line until the next night overwrites it.
    """

    def _window(self, monkeypatch, latest_in_db, now):
        import ingest_game_logs as gl

        captured = {}

        monkeypatch.setattr(gl, "create_client", lambda url, key: object())
        monkeypatch.setattr(gl, "_latest_game_date", lambda client, season: latest_in_db)
        monkeypatch.setattr(gl, "SUPABASE_URL", "https://example.supabase.co")
        monkeypatch.setattr(gl, "SUPABASE_SERVICE_ROLE_KEY", "key")

        class FakeDatetime(gl.datetime):
            @classmethod
            def now(cls, tz=None):
                return now

        monkeypatch.setattr(gl, "datetime", FakeDatetime)

        def fake_statcast(start_dt, end_dt):
            captured.setdefault("chunks", []).append((start_dt, end_dt))
            return pd.DataFrame()

        monkeypatch.setattr(gl, "statcast", fake_statcast)
        gl.run()
        return captured.get("chunks", [])

    def test_never_fetches_today(self, monkeypatch):
        from datetime import date, datetime as dt, timezone

        chunks = self._window(
            monkeypatch,
            latest_in_db=date(2026, 7, 25),
            now=dt(2026, 7, 28, 9, 0, tzinfo=timezone.utc),
        )
        assert chunks, "expected at least one chunk"
        assert chunks[0][0] == "2026-07-25"
        assert max(end for _, end in chunks) == "2026-07-27"

    def test_nothing_to_do_when_yesterday_is_already_in(self, monkeypatch):
        from datetime import date, datetime as dt, timezone

        chunks = self._window(
            monkeypatch,
            latest_in_db=date(2026, 7, 27),
            now=dt(2026, 7, 28, 9, 0, tzinfo=timezone.utc),
        )
        # start == end == yesterday: the last known day is re-read once in case
        # it had late games, but nothing beyond it is touched.
        assert chunks == [("2026-07-27", "2026-07-27")]


class TestGameTypeFilter:
    """Postseason and spring pitches must never reach player_game_logs.

    pybaseball 2.2.7's statcast() requests hfGT=R|PO|S, so every date-range
    pull carries all three, and SEASON_END reaches past the World Series. A
    postseason game is just a new game_date, so unfiltered rows upsert cleanly
    and invisibly, and the Recent Form / Trends windows for any club still
    playing in October become postseason-only under a regular-season heading.
    """

    def test_drops_postseason_and_spring_by_default(self):
        df = _frame([
            {"batter": 1, "events": "single", "game_type": "R"},
            {"batter": 2, "events": "single", "game_type": "F"},
            {"batter": 3, "events": "single", "game_type": "D"},
            {"batter": 4, "events": "single", "game_type": "L"},
            {"batter": 5, "events": "single", "game_type": "W"},
            {"batter": 6, "events": "single", "game_type": "S"},
        ])
        kept = _filter_game_types(df, _allowed_game_types())
        assert list(kept["batter"]) == [1]

    def test_widening_lets_the_postseason_through(self, monkeypatch):
        monkeypatch.setenv("STATCAST_GAME_TYPES", "R,F,D,L,W")
        df = _frame([
            {"batter": 1, "events": "single", "game_type": "R"},
            {"batter": 2, "events": "single", "game_type": "W"},
            {"batter": 3, "events": "single", "game_type": "S"},
        ])
        kept = _filter_game_types(df, _allowed_game_types())
        assert sorted(kept["batter"]) == [1, 2]

    def test_a_frame_without_the_column_is_left_alone(self):
        """Legacy or hand-built frames aren't data we can classify, so we keep
        them rather than silently dropping a whole chunk."""
        df = _frame([{"batter": 1, "events": "single"}]).drop(columns=["game_type"])
        kept = _filter_game_types(df, {"R"})
        assert len(kept) == 1

    def test_null_game_type_counts_as_regular_season(self):
        df = _frame([{"batter": 1, "events": "single", "game_type": None}])
        assert len(_filter_game_types(df, {"R"})) == 1

    def test_allowed_defaults_to_regular_season_only(self, monkeypatch):
        monkeypatch.delenv("STATCAST_GAME_TYPES", raising=False)
        assert _allowed_game_types() == {"R"}

    def test_blank_override_falls_back_to_regular_season(self, monkeypatch):
        monkeypatch.setenv("STATCAST_GAME_TYPES", "  ,  ")
        assert _allowed_game_types() == {"R"}

    def test_override_is_case_and_space_insensitive(self, monkeypatch):
        monkeypatch.setenv("STATCAST_GAME_TYPES", " r , w ")
        assert _allowed_game_types() == {"R", "W"}


class TestGameTypeOnRows:
    """Rows carry their own phase, so nothing downstream has to infer it."""

    def test_batter_rows_carry_game_type(self):
        df = _frame([{"batter": 1, "events": "single", "game_type": "R"}])
        rows = _aggregate_batters(df)
        assert rows and all(row["game_type"] == "R" for row in rows)

    def test_pitcher_rows_carry_game_type(self):
        df = _frame([{"pitcher": 2, "events": "single", "game_type": "R"}])
        rows = _aggregate_pitchers(df)
        assert rows and all(row["game_type"] == "R" for row in rows)

    def test_postseason_rows_are_labelled_when_widened(self):
        df = _frame([{"batter": 1, "events": "single", "game_type": "W"}])
        rows = _aggregate_batters(_filter_game_types(df, {"R", "W"}))
        assert rows and rows[0]["game_type"] == "W"

    def test_a_frame_without_the_column_still_aggregates(self):
        df = _frame([{"batter": 1, "events": "single"}]).drop(columns=["game_type"])
        rows = _aggregate_batters(df)
        assert rows and rows[0]["game_type"] == "R"


class TestOctoberRegression:
    """The specific failure this all exists to prevent."""

    def test_a_mixed_october_day_yields_only_regular_season_games(self):
        """A late-season day can hold both: the last regular-season makeup game
        and a Wild Card game. Only the first may be stored."""
        df = _frame([
            {"batter": 1, "events": "single", "game_date": pd.Timestamp("2026-09-28"),
             "game_type": "R"},
            {"batter": 1, "events": "home_run", "game_date": pd.Timestamp("2026-10-01"),
             "game_type": "F"},
            {"batter": 1, "events": "double", "game_date": pd.Timestamp("2026-10-08"),
             "game_type": "D"},
        ])
        rows = _aggregate_batters(_filter_game_types(df, _allowed_game_types()))
        assert [row["game_date"] for row in rows] == ["2026-09-28"]


class TestOctoberWindowCap:
    """A regular-season-only run must not walk into October.

    SEASON_END reaches past the World Series, and `_latest_game_date` can never
    advance past a day the ingest refuses to write. Without a cap the nightly
    job would re-pull every October week from Savant and discard all of it,
    forever.
    """

    def _window(self, monkeypatch, latest_in_db, now):
        import ingest_game_logs as gl

        captured: dict = {}
        monkeypatch.setattr(gl, "create_client", lambda url, key: object())
        monkeypatch.setattr(gl, "_latest_game_date", lambda client, season: latest_in_db)
        monkeypatch.setattr(gl, "SUPABASE_URL", "https://example.supabase.co")
        monkeypatch.setattr(gl, "SUPABASE_SERVICE_ROLE_KEY", "key")

        class FakeDatetime(gl.datetime):
            @classmethod
            def now(cls, tz=None):
                return now

        monkeypatch.setattr(gl, "datetime", FakeDatetime)

        def fake_statcast(start_dt, end_dt):
            captured.setdefault("chunks", []).append((start_dt, end_dt))
            return pd.DataFrame()

        monkeypatch.setattr(gl, "statcast", fake_statcast)
        gl.run()
        return captured.get("chunks", [])

    def test_stops_at_the_last_regular_season_day(self, monkeypatch):
        from datetime import date, datetime as dt, timezone

        monkeypatch.delenv("STATCAST_GAME_TYPES", raising=False)
        chunks = self._window(
            monkeypatch,
            latest_in_db=date(2026, 9, 27),
            now=dt(2026, 10, 20, 9, 0, tzinfo=timezone.utc),
        )
        assert chunks == [("2026-09-27", "2026-09-27")]

    def test_widening_lets_the_run_reach_the_postseason(self, monkeypatch):
        from datetime import date, datetime as dt, timezone

        monkeypatch.setenv("STATCAST_GAME_TYPES", "R,F,D,L,W")
        chunks = self._window(
            monkeypatch,
            latest_in_db=date(2026, 9, 27),
            now=dt(2026, 10, 20, 9, 0, tzinfo=timezone.utc),
        )
        assert max(end for _, end in chunks) == "2026-10-19"
