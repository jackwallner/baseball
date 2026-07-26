import os
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

import ingest


def test_display_name_with_suffix():
    assert ingest.display_name("De La Cruz, Elly, Jr.") == "Elly, Jr. De La Cruz"
    assert ingest.display_name("Judge, Aaron") == "Aaron Judge"
    assert ingest.display_name("Ohtani, Shohei") == "Shohei Ohtani"


def test_percentile_value_with_na_string():
    assert ingest.percentile_value("N/A") is None
    assert ingest.percentile_value("—") is None
    assert ingest.percentile_value(95.0) == 95


def test_percentile_value_with_non_numeric():
    assert ingest.percentile_value("abc") is None
    assert ingest.percentile_value(None) is None
    assert ingest.percentile_value(float("nan")) is None


def make_mock_value_store():
    store = MagicMock(spec=ingest.ActualValueStore)
    store.get_value.return_value = None
    return store


def test_build_metrics_with_values_skips_missing_columns():
    row = pd.Series({"player_id": 1, "player_name": "Test", "xwoba": 90})
    store = make_mock_value_store()
    store.get_value.return_value = "0.450"  # Provide actual value so metric is included
    metrics = ingest.build_metrics_with_values(row, "batter", ingest.BATTER_METRICS, 1, store)
    labels = [m["label"] for m in metrics]
    assert "xwOBA" in labels
    assert "Sprint Speed" not in labels


def test_build_metrics_with_values_uses_actual_value_when_available():
    row = pd.Series({"player_id": 1, "player_name": "Test", "exit_velocity": 92})
    store = MagicMock(spec=ingest.ActualValueStore)
    store.get_value.return_value = "94.5 mph"
    metrics = ingest.build_metrics_with_values(row, "batter", ingest.BATTER_METRICS, 1, store)
    ev = [m for m in metrics if m["label"] == "EV"]
    assert len(ev) == 1
    assert ev[0]["value"] == "94.5 mph"
    assert ev[0]["percentile"] == 92


def test_metrics_omit_the_duplicate_value_fields():
    """actual_value duplicated value and display_value was derivable from it.

    The app never read either — Metric decodes id/label/value/percentile/
    category — and together they were ~16% of every cold-launch payload.
    """
    row = pd.Series({"player_id": 1, "player_name": "Test", "exit_velocity": 92})
    store = MagicMock(spec=ingest.ActualValueStore)
    store.get_value.return_value = "94.5 mph"
    metrics = ingest.build_metrics_with_values(row, "batter", ingest.BATTER_METRICS, 1, store)
    for metric in metrics:
        assert "actual_value" not in metric
        assert "display_value" not in metric


def test_merge_player_row_maps_team(sample_batter_row):
    players = {}
    store = make_mock_value_store()
    now = datetime(2026, 4, 26, tzinfo=timezone.utc)
    ingest.merge_player_row(players, sample_batter_row, "batter", ingest.BATTER_METRICS, now, 2026, store)
    assert players[592450]["team"] == "NYY"


def test_merge_player_row_defaults_team_to_tbd():
    row = pd.Series({"player_id": 1, "player_name": "Test", "xwoba": 90})
    players = {}
    store = make_mock_value_store()
    now = datetime(2026, 4, 26, tzinfo=timezone.utc)
    ingest.merge_player_row(players, row, "batter", ingest.BATTER_METRICS, now, 2026, store)
    assert players[1]["team"] == "TBD"


def test_merge_player_row_uses_roster_lookup_when_other_team_sources_missing():
    row = pd.Series({"player_id": 592450, "player_name": "Judge, Aaron", "xwoba": 90})
    roster_lookup = {592450: {"team": "NYY", "position": "RF"}}
    players = {}
    store = make_mock_value_store()
    now = datetime(2026, 4, 26, tzinfo=timezone.utc)
    ingest.merge_player_row(players, row, "batter", ingest.BATTER_METRICS, now, 2026, store, roster_lookup=roster_lookup)
    assert players[592450]["team"] == "NYY"
    assert players[592450]["position"] == "RF"


def test_normalize_team_abbr_aliases():
    assert ingest.normalize_team_abbr("AZ") == "ARI"
    assert ingest.normalize_team_abbr("Chicago White Sox") == "CWS"
    assert ingest.normalize_team_abbr("CHW") == "CWS"
    assert ingest.normalize_team_abbr("KCR") == "KC"


def test_normalize_team_abbr_unknown_falls_back_to_tbd():
    assert ingest.normalize_team_abbr("XYZ") == "TBD"
    assert ingest.normalize_team_abbr("Some Random Garbage") == "TBD"
    assert ingest.normalize_team_abbr("") == "TBD"


def test_resolve_season_invalid_input_falls_back():
    with patch.dict(os.environ, {"STATCAST_SEASON": "2099"}):
        assert ingest._resolve_season() == ingest.DEFAULT_SEASON
    with patch.dict(os.environ, {"STATCAST_SEASON": "abc"}):
        assert ingest._resolve_season() == ingest.DEFAULT_SEASON
    with patch.dict(os.environ, {"STATCAST_SEASON": "1999"}):
        assert ingest._resolve_season() == ingest.DEFAULT_SEASON


def test_merge_player_row_two_way():
    row = pd.Series(
        {
            "player_id": 660271,
            "player_name": "Ohtani, Shohei",
            "team": "LAD",
            "position": "DH",
            "bats": "L",
            "throws": "R",
            "xwoba": 100,
            "xera": 99,
        }
    )
    players = {}
    store = make_mock_value_store()
    now = datetime(2026, 4, 26, tzinfo=timezone.utc)
    ingest.merge_player_row(players, row, "batter", ingest.BATTER_METRICS, now, 2026, store)
    ingest.merge_player_row(players, row, "pitcher", ingest.PITCHER_METRICS, now, 2026, store)
    assert players[660271]["position"] == "DH"
    assert players[660271]["player_type"] == "two_way"


def test_safe_player_id_nan():
    row = pd.Series({"player_id": float("nan"), "player_name": "Bad"})
    assert ingest.safe_player_id(row) is None

    row2 = pd.Series({"player_name": "Bad"})
    assert ingest.safe_player_id(row2) is None


def test_build_snapshot_rows_handles_empty_dataframe():
    with patch("ingest.statcast_batter_percentile_ranks", return_value=pd.DataFrame()):
        with patch("ingest.statcast_pitcher_percentile_ranks", return_value=pd.DataFrame()):
            with patch("ingest.ActualValueStore"):
                with patch("ingest.build_roster_lookup", return_value={}):
                    with patch("ingest._fetch_mlb_standard_stats", return_value={}):
                        with patch.dict(os.environ, {"SUPABASE_URL": "https://test.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "test-key"}):
                            with patch("ingest.create_client"):
                                with pytest.raises(SystemExit) as exc_info:
                                    ingest.main()
                                assert exc_info.value.code == 1


def test_batching():
    rows = [{"id": i} for i in range(350)]
    batches = list(ingest.chunks(rows, 150))
    assert len(batches) == 3
    assert len(batches[0]) == 150
    assert len(batches[1]) == 150
    assert len(batches[2]) == 50


def test_main_batched_upsert():
    rows = [{"id": i} for i in range(350)]
    mock_client = MagicMock()
    mock_table = MagicMock()
    mock_client.table.return_value = mock_table
    mock_table.upsert.return_value = mock_table
    with patch.dict(os.environ, {"SUPABASE_URL": "https://test.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "test-key"}):
        with patch("ingest.create_client", return_value=mock_client):
            with patch("ingest.build_snapshot_rows", return_value=rows):
                with patch("ingest._resolve_season", return_value=2026):
                    ingest.main()
    assert mock_table.upsert.call_count == 3


def test_add_calculated_rates_from_standard_stats():
    player = {
        "player_type": "batter",
        "standard_stats": [
            {"label": "PA", "value": "600"},
            {"label": "SO", "value": "150"},
            {"label": "BB", "value": "60"},
        ],
        "metrics": [],
    }
    players = {1: player}
    ingest._add_calculated_rates(players, set(players))
    labels = {m["label"] for m in player["metrics"]}
    assert "K%" in labels
    assert "BB%" in labels
    k = next(m for m in player["metrics"] if m["label"] == "K%")
    assert k["value"] == "25.0%"
    bb = next(m for m in player["metrics"] if m["label"] == "BB%")
    assert bb["value"] == "10.0%"


def _make_batter(pid: int, pa: int, so: int, bb: int) -> dict:
    return {
        "player_type": "batter",
        "standard_stats": [
            {"label": "PA", "value": str(pa)},
            {"label": "SO", "value": str(so)},
            {"label": "BB", "value": str(bb)},
        ],
        "metrics": [],
    }


def test_add_calculated_rates_assigns_true_percentiles():
    # Three batters: best, mid, worst K% / BB%.
    # K% (lower better for batters): pid 1 has 10%, pid 2 has 20%, pid 3 has 30%
    # BB% (higher better for batters): pid 1 has 5%, pid 2 has 10%, pid 3 has 15%
    players = {
        1: _make_batter(1, 500, 50, 25),
        2: _make_batter(2, 500, 100, 50),
        3: _make_batter(3, 500, 150, 75),
    }
    ingest._add_calculated_rates(players, set(players))

    by_pid_k = {pid: next(m for m in p["metrics"] if m["label"] == "K%") for pid, p in players.items()}
    by_pid_bb = {pid: next(m for m in p["metrics"] if m["label"] == "BB%") for pid, p in players.items()}

    # Best K% (10%) should yield top percentile, worst (30%) the bottom.
    assert by_pid_k[1]["percentile"] > by_pid_k[2]["percentile"] > by_pid_k[3]["percentile"]
    # Best BB% (15%) should yield top percentile.
    assert by_pid_bb[3]["percentile"] > by_pid_bb[2]["percentile"] > by_pid_bb[1]["percentile"]

    # No hardcoded zeros — all should be > 0.
    for m in list(by_pid_k.values()) + list(by_pid_bb.values()):
        assert m["percentile"] > 0
        # display_value is no longer stored — see
        # test_metrics_omit_the_duplicate_value_fields.
        assert "display_value" not in m


def test_ordinal_suffix():
    # 11-13 always 'th'
    for n in (11, 12, 13, 111, 112, 113):
        assert ingest.ordinal_suffix(n) == "th"
    assert ingest.ordinal_suffix(1) == "st"
    assert ingest.ordinal_suffix(21) == "st"
    assert ingest.ordinal_suffix(91) == "st"
    assert ingest.ordinal_suffix(2) == "nd"
    assert ingest.ordinal_suffix(22) == "nd"
    assert ingest.ordinal_suffix(92) == "nd"
    assert ingest.ordinal_suffix(3) == "rd"
    assert ingest.ordinal_suffix(23) == "rd"
    assert ingest.ordinal_suffix(73) == "rd"
    for n in (4, 5, 6, 7, 8, 9, 10, 20, 100):
        assert ingest.ordinal_suffix(n) == "th"


def test_add_calculated_rates_uses_bf_for_pitchers():
    # Regression: pitching_stats_bref sometimes returns a tiny pitcher-as-hitter
    # PA (e.g. 2) alongside the real BF (e.g. 527). The old code divided by PA
    # and produced rates like K%=7100%. Must use BF for pitchers.
    player = {
        "player_type": "pitcher",
        "standard_stats": [
            {"label": "PA", "value": "2"},      # bogus pitcher-as-batter PA
            {"label": "BF", "value": "527"},    # correct denominator
            {"label": "SO", "value": "142"},
            {"label": "BB", "value": "50"},
        ],
        "metrics": [],
    }
    ingest._add_calculated_rates({1: player}, {1})
    k = next(m for m in player["metrics"] if m["label"] == "K%")
    bb = next(m for m in player["metrics"] if m["label"] == "BB%")
    # 142/527 = 26.9%, 50/527 = 9.5% — both well under 100%
    assert k["value"] == "26.9%"
    assert bb["value"] == "9.5%"


def test_add_calculated_rates_skips_impossible_rates():
    # If upstream data is corrupt (SO > BF), don't emit a >100% rate.
    player = {
        "player_type": "pitcher",
        "standard_stats": [
            {"label": "BF", "value": "5"},
            {"label": "SO", "value": "13"},
            {"label": "BB", "value": "10"},
        ],
        "metrics": [],
    }
    ingest._add_calculated_rates({1: player}, {1})
    labels = {m["label"] for m in player["metrics"]}
    assert "K%" not in labels
    assert "BB%" not in labels


def test_add_calculated_rates_skips_unqualified_players():
    # Sub-qualifier player (not in qualified_pids): Savant shows no K%/BB%
    # bar for them, so we must not fabricate one from a tiny sample.
    sub = _make_batter(99, pa=18, so=0, bb=0)   # 0 K in 18 PA -> would be 99th
    qualified = _make_batter(1, pa=500, so=100, bb=50)
    players = {99: sub, 1: qualified}
    ingest._add_calculated_rates(players, {1})
    assert sub["metrics"] == []
    assert {m["label"] for m in qualified["metrics"]} == {"K%", "BB%"}


def test_add_calculated_rates_preserves_native_percentile():
    # If the metric already exists with a real percentile, don't overwrite it.
    player = {
        "player_type": "batter",
        "standard_stats": [
            {"label": "PA", "value": "600"},
            {"label": "SO", "value": "150"},
            {"label": "BB", "value": "60"},
        ],
        "metrics": [
            {"id": "batter-1-k_percent", "label": "K%", "value": "25.0%", "percentile": 42, "category": "Hitting"},
        ],
    }
    ingest._add_calculated_rates({1: player}, {1})
    k = next(m for m in player["metrics"] if m["label"] == "K%")
    assert k["percentile"] == 42
