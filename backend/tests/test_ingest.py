import os
import pytest
from unittest.mock import MagicMock, patch
import pandas as pd

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


def test_build_metrics_value_is_raw_not_percentile(sample_batter_row):
    metrics = ingest.build_metrics(sample_batter_row, "batter", ingest.BATTER_METRICS, 592450)
    for m in metrics:
        assert "PCTL" not in m["value"]
        assert m["percentile"] is not None
        assert 0 <= m["percentile"] <= 100


def test_build_metrics_skips_missing_columns():
    row = pd.Series({"player_id": 1, "player_name": "Test", "xwoba": 90})
    metrics = ingest.build_metrics(row, "batter", ingest.BATTER_METRICS, 1)
    labels = [m["label"] for m in metrics]
    assert "xwOBA" in labels
    assert "Sprint Speed" not in labels


def test_merge_player_row_maps_team(sample_batter_row):
    players = {}
    ingest.merge_player_row(players, sample_batter_row, "batter", ingest.BATTER_METRICS, "2026-04-26T00:00:00Z")
    assert players[592450]["team"] == "NYY"


def test_merge_player_row_maps_position_and_handedness(sample_batter_row):
    players = {}
    ingest.merge_player_row(players, sample_batter_row, "batter", ingest.BATTER_METRICS, "2026-04-26T00:00:00Z")
    assert players[592450]["position"] == "RF"
    assert players[592450]["handedness"] == "R/R"


def test_merge_player_row_defaults_team_to_tbd():
    row = pd.Series({"player_id": 1, "player_name": "Test", "xwoba": 90})
    players = {}
    ingest.merge_player_row(players, row, "batter", ingest.BATTER_METRICS, "2026-04-26T00:00:00Z")
    assert players[1]["team"] == "TBD"


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
    ingest.merge_player_row(players, row, "batter", ingest.BATTER_METRICS, "2026-04-26T00:00:00Z")
    ingest.merge_player_row(players, row, "pitcher", ingest.PITCHER_METRICS, "2026-04-26T00:00:00Z")
    assert players[660271]["position"] == "Two-way"
    assert players[660271]["player_type"] == "two_way"


def test_safe_player_id_nan():
    row = pd.Series({"player_id": float("nan"), "player_name": "Bad"})
    assert ingest.safe_player_id(row) is None

    row2 = pd.Series({"player_name": "Bad"})
    assert ingest.safe_player_id(row2) is None


def test_build_snapshot_rows_handles_empty_dataframe():
    with patch("ingest.statcast_batter_percentile_ranks", return_value=pd.DataFrame()):
        with patch("ingest.statcast_pitcher_percentile_ranks", return_value=pd.DataFrame()):
            with patch("ingest._fetch_standard_stats", return_value=(pd.DataFrame(), pd.DataFrame())):
                with pytest.raises(SystemExit):
                    ingest.main()


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
                ingest.main()
    assert mock_table.upsert.call_count == 3
