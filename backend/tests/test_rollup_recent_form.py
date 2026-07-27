"""Rolling-window rollup tests.

The claim worth pinning down is exactness: aggregating per-game rates weighted
by their own stored denominator has to reproduce a from-scratch recompute, not
approximate it. The old client-side path weighted everything by plate
appearances, which quietly skewed any metric whose denominator wasn't PA.
"""

from datetime import date

import pytest

from rollup_recent_form import _aggregate, _delta, build_rows


def _log(game_date, metrics, pa=4, bbe=0, player_id=1, player_type="batter"):
    return {
        "player_id": player_id,
        "season": 2026,
        "game_date": game_date,
        "player_type": player_type,
        "team": "KC",
        "plate_appearances": pa,
        "batted_ball_events": bbe,
        "metrics": metrics,
    }


def test_rate_aggregation_is_exact_not_pa_weighted():
    """Two games: 1 whiff of 2 swings, then 6 whiffs of 18 swings.

    True Whiff% is 7/20 = 35%. Weighting the per-game rates by plate
    appearances instead would give ~41.7% — the error this table exists to
    remove.
    """
    logs = [
        _log("2026-07-20", {"whiff_pct": 50.0, "_swings": 2}, pa=4),
        _log("2026-07-19", {"whiff_pct": 33.33, "_swings": 18}, pa=4),
    ]
    assert _aggregate(logs)["whiff_pct"] == pytest.approx(35.0, abs=0.05)


def test_xwoba_weights_by_woba_denom_not_plate_appearances():
    """A game with a sac bunt has fewer wOBA-charged PAs than PAs."""
    logs = [
        _log("2026-07-20", {"xwoba": 0.900, "_woba_denom": 1}, pa=2),
        _log("2026-07-19", {"xwoba": 0.100, "_woba_denom": 9}, pa=9),
    ]
    assert _aggregate(logs)["xwoba"] == pytest.approx((0.9 * 1 + 0.1 * 9) / 10)


def test_metric_with_no_denominator_is_omitted_not_zeroed():
    """A player who never put a ball in play has no Barrel%, not 0% Barrel%."""
    logs = [_log("2026-07-20", {"barrel_pct": None, "_bbe": 0, "k_pct": 25.0}, pa=4)]
    result = _aggregate(logs)
    assert "barrel_pct" not in result
    assert result["k_pct"] == pytest.approx(25.0)


def test_max_metrics_take_the_peak():
    logs = [
        _log("2026-07-20", {"ev_max": 104.6, "_bbe": 3}, bbe=3),
        _log("2026-07-19", {"ev_max": 112.1, "_bbe": 2}, bbe=2),
    ]
    assert _aggregate(logs)["ev_max"] == pytest.approx(112.1)


def test_fastball_velo_survives_the_rollup():
    """Regression: fastball velo and spin had no entry in WEIGHTS, so every
    metric the rollup couldn't find a denominator for was silently dropped and
    the pitcher's Recent view had a permanently empty Fastball Velo row.

    Weighted by fastballs thrown, not total pitches: 20 fastballs at 95.0 and
    5 at 91.0 is 94.2, whereas weighting by every pitch thrown would let a
    heavy off-speed night distort a number that never involved those pitches.
    """
    logs = [
        _log("2026-07-20", {"fb_velo_avg": 95.0, "_fb_pitches": 20, "_pitches": 90},
             player_type="pitcher"),
        _log("2026-07-15", {"fb_velo_avg": 91.0, "_fb_pitches": 5, "_pitches": 95},
             player_type="pitcher"),
    ]
    assert _aggregate(logs)["fb_velo_avg"] == pytest.approx(94.2, abs=0.05)


def test_xiso_derives_from_window_values():
    logs = [
        _log("2026-07-20", {"xba": 0.300, "xslg": 0.600, "_at_bats": 4}),
    ]
    result = _aggregate(logs)
    assert result["xiso"] == pytest.approx(0.300)


def test_prior_window_is_equal_length_and_does_not_overlap():
    """as_of 2026-07-20, window 7: current is Jul 14-20, prior is Jul 7-13."""
    logs = [
        _log("2026-07-20", {"k_pct": 10.0}),   # current
        _log("2026-07-14", {"k_pct": 10.0}),   # current, first day
        _log("2026-07-13", {"k_pct": 40.0}),   # prior, last day
        _log("2026-07-07", {"k_pct": 40.0}),   # prior, first day
        _log("2026-07-06", {"k_pct": 99.0}),   # outside both
    ]
    rows = {r["window_days"]: r for r in build_rows(logs, date(2026, 7, 20))}
    week = rows[7]
    assert week["games"] == 2
    assert week["metrics"]["k_pct"] == pytest.approx(10.0)
    assert week["prior_metrics"]["k_pct"] == pytest.approx(40.0)
    assert week["delta"]["k_pct"] == pytest.approx(-30.0)


def test_delta_only_covers_metrics_present_in_both_windows():
    now = {"k_pct": 20.0, "barrel_pct": 10.0}
    then = {"k_pct": 30.0}
    assert _delta(now, then) == {"k_pct": -10.0}


def test_player_with_no_games_in_window_is_skipped():
    """Only the 30-day window should exist for someone who last played 20 days ago."""
    logs = [_log("2026-06-30", {"k_pct": 25.0})]
    windows = {r["window_days"] for r in build_rows(logs, date(2026, 7, 20))}
    assert windows == {30}


def test_batter_and_pitcher_rows_stay_separate():
    """A two-way player contributes to both pools independently."""
    logs = [
        _log("2026-07-20", {"k_pct": 10.0}, player_id=660271, player_type="batter"),
        _log("2026-07-20", {"k_pct": 40.0}, player_id=660271, player_type="pitcher"),
    ]
    rows = build_rows(logs, date(2026, 7, 20))
    by_type = {(r["player_type"], r["window_days"]): r for r in rows}
    assert by_type[("batter", 7)]["metrics"]["k_pct"] == pytest.approx(10.0)
    assert by_type[("pitcher", 7)]["metrics"]["k_pct"] == pytest.approx(40.0)


def test_as_of_and_totals_are_recorded():
    logs = [
        _log("2026-07-20", {"k_pct": 10.0, "_bbe": 2}, pa=5, bbe=2),
        _log("2026-07-19", {"k_pct": 10.0, "_bbe": 1}, pa=3, bbe=1),
    ]
    week = next(r for r in build_rows(logs, date(2026, 7, 20)) if r["window_days"] == 7)
    assert week["as_of"] == "2026-07-20"
    assert week["plate_appearances"] == 8
    assert week["batted_ball_events"] == 3
    assert week["team"] == "KC"


def test_empty_input_produces_nothing():
    assert _aggregate([]) == {}
    assert build_rows([], date(2026, 7, 20)) == []


def test_traditional_rates_derive_from_summed_counts():
    """A 4-for-4 game and an 0-for-1 make a .800 window, not a .500 one.

    Averaging the two per-game averages (1.000 and .000) would say .500 —
    which is why the counting stats sum rather than weight-average.
    """
    logs = [
        _log("2026-07-20", {"_ab": 4, "_h": 4, "_tb": 7, "_bb": 0, "_hbp": 0, "_sf": 0}),
        _log("2026-07-19", {"_ab": 1, "_h": 0, "_tb": 0, "_bb": 0, "_hbp": 0, "_sf": 0}),
    ]
    result = _aggregate(logs)
    assert result["avg"] == pytest.approx(0.800)
    assert result["slg"] == pytest.approx(1.400)
    assert result["ab"] == 5
    assert result["h"] == 4


def test_obp_denominator_includes_walks_hbp_and_sac_flies():
    logs = [
        _log("2026-07-20", {"_ab": 3, "_h": 1, "_tb": 1, "_bb": 1, "_hbp": 1, "_sf": 1}),
    ]
    result = _aggregate(logs)
    # (1 + 1 + 1) / (3 + 1 + 1 + 1)
    assert result["obp"] == pytest.approx(0.500)
    assert result["ops"] == pytest.approx(0.500 + 1 / 3, abs=1e-3)


def test_window_with_no_at_bats_omits_average():
    """An all-walks window has no AVG, rather than a .000 one."""
    logs = [_log("2026-07-20", {"_ab": 0, "_h": 0, "_tb": 0, "_bb": 2, "_hbp": 0, "_sf": 0})]
    result = _aggregate(logs)
    assert "avg" not in result
    assert "slg" not in result
    assert result["obp"] == pytest.approx(1.0)
