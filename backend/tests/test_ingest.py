import os
from types import SimpleNamespace
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


def test_build_metrics_keeps_published_percentile_without_actual_value():
    row = pd.Series({"player_id": 1, "player_name": "Test", "hard_hit_percent": 97})
    store = make_mock_value_store()

    metrics = ingest.build_metrics_with_values(row, "batter", ingest.BATTER_METRICS, 1, store)

    assert metrics == [{
        "id": "batter-1-hard_hit_percent",
        "label": "Hard-Hit%",
        "value": "",
        "percentile": 97,
        "category": "Hitting",
    }]


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


class TestExpectedOnBasePercentage:
    """xOBP is reconstructed, not read — see _add_expected_obp.

    Savant publishes an xOBP percentile but no xOBP column, and what used to
    fill the gap was xwOBA averaged over batted balls (xwOBACON). That put
    hitters at .580 and left the printed value disagreeing with the percentile
    bar beside it, which is exactly what a user reported.
    """

    @staticmethod
    def _player(metrics, standard):
        return {
            "metrics": metrics,
            "standard_stats": [
                {"id": f"std-{k}", "label": k, "value": v} for k, v in standard.items()
            ],
        }

    def test_reconstructs_batter_xobp_from_expected_hits_and_walks(self):
        # (.278 x 409 + 82) / 498 = .393 — Wood's real OBP that season was .396.
        players = {
            1: self._player(
                [{"id": "batter-1-xobp", "label": "xOBP", "value": "", "percentile": 99,
                  "category": "Hitting"}],
                {"PA": "498", "AB": "409", "BB": "82"},
            )
        }
        store = SimpleNamespace(expected_stat=lambda pid, col, kind: 0.278)

        ingest._add_expected_obp(players, store)

        assert players[1]["metrics"][0]["value"] == "0.393"

    def test_pitcher_xobp_uses_batters_faced(self):
        # (.240 x (600 - 50) + 50) / 600 = .303
        players = {
            2: self._player(
                [{"id": "pitcher-2-xobp", "label": "xOBP", "value": "", "percentile": 70,
                  "category": "Pitching"}],
                {"BF": "600", "BB": "50"},
            )
        }
        store = SimpleNamespace(expected_stat=lambda pid, col, kind: 0.240)

        ingest._add_expected_obp(players, store)

        assert players[2]["metrics"][0]["value"] == "0.303"

    def test_two_way_pitcher_xobp_uses_pitching_walks(self):
        player = self._player(
            [{"id": "pitcher-2-xobp", "label": "xOBP", "value": "", "percentile": 70,
              "category": "Pitching"}],
            {},
        )
        player["standard_stats"] = [
            {"label": "BB", "value": "90", "category": "hitting"},
            {"label": "BB", "value": "30", "category": "pitching"},
            {"label": "BF", "value": "600", "category": "pitching"},
        ]
        store = SimpleNamespace(expected_stat=lambda pid, col, kind: 0.240)

        ingest._add_expected_obp({2: player}, store)

        assert player["metrics"][0]["value"] == "0.278"

    def test_keeps_the_percentile_when_inputs_are_missing(self):
        players = {
            3: self._player(
                [{"id": "batter-3-xobp", "label": "xOBP", "value": "", "percentile": 55,
                  "category": "Hitting"},
                 {"id": "batter-3-xba", "label": "xBA", "value": "0.270", "percentile": 81,
                  "category": "Hitting"}],
                {"PA": "300"},
            )
        }
        store = SimpleNamespace(expected_stat=lambda pid, col, kind: 0.270)

        ingest._add_expected_obp(players, store)

        assert [m["label"] for m in players[3]["metrics"]] == ["xOBP", "xBA"]
        assert players[3]["metrics"][0]["value"] == ""

    def test_leaves_an_already_valued_metric_alone(self):
        players = {
            4: self._player(
                [{"id": "batter-4-xobp", "label": "xOBP", "value": "0.350", "percentile": 88,
                  "category": "Hitting"}],
                {"PA": "500", "AB": "450", "BB": "50"},
            )
        }
        store = SimpleNamespace(expected_stat=lambda pid, col, kind: 0.999)

        ingest._add_expected_obp(players, store)

        assert players[4]["metrics"][0]["value"] == "0.350"


# --- standard_stats: two-way players carry two lines, not one merged one ---


def _two_way_stats():
    """Ohtani-shaped input: a real batting line plus a real pitching line.

    The five labels that exist on both sides (H, R, HR, BB, SO) arrive
    namespaced from the fetchers so the pitching side can't overwrite the
    batting side, which is exactly the bug this guards.
    """
    return {
        "player_type": "two_way",
        # batting
        "avg": "0.282", "obp": "0.387", "slg": "0.520", "ops": "0.907",
        "hr": 46, "rbi": 61, "r": 103, "h": 105, "doubles": 19, "triples": 2,
        "bb": 96, "so": 189, "sb": 6, "cs": 2, "pa": 447, "ab": 373,
        "g_bat": 114,
        # pitching
        "era": "1.79", "whip": "0.95", "wins": 8, "losses": 2, "saves": 0,
        "ip": "85.2", "er": 17, "p_h": 55, "p_r": 21, "p_hr": 4,
        "p_bb": 26, "p_so": 95, "qs": 0, "g": 14, "gs": 14, "bf": 340,
    }


def _by_category(rows, category):
    return {r["label"]: r["value"] for r in rows if r["category"] == category}


def test_two_way_batting_line_survives_the_pitching_line():
    rows = ingest._build_standard_stats_from_mlb(_two_way_stats())
    hitting = _by_category(rows, "hitting")
    pitching = _by_category(rows, "pitching")

    # The regression: these five used to hold the pitching values.
    assert hitting["H"] == "105"
    assert hitting["HR"] == "46"
    assert hitting["R"] == "103"
    assert hitting["BB"] == "96"
    assert hitting["SO"] == "189"

    # And the pitching side keeps its own, distinct values.
    assert pitching["H"] == "55"
    assert pitching["HR"] == "4"
    assert pitching["BB"] == "26"
    assert pitching["SO"] == "95"


def test_two_way_batting_line_is_internally_consistent():
    """AVG x AB should land on H. It didn't when H held hits allowed."""
    hitting = _by_category(ingest._build_standard_stats_from_mlb(_two_way_stats()), "hitting")
    expected_hits = float(hitting["AVG"]) * float(hitting["AB"])
    assert abs(expected_hits - float(hitting["H"])) < 1.0
    # A batter cannot strike out more often than he bats.
    assert float(hitting["SO"]) <= float(hitting["AB"])


def test_two_way_pitching_line_is_internally_consistent():
    """(H + BB) / IP should land on WHIP."""
    pitching = _by_category(ingest._build_standard_stats_from_mlb(_two_way_stats()), "pitching")
    innings = 85.0 + 2.0 / 3.0  # 85.2 is 85 and two thirds
    whip = (float(pitching["H"]) + float(pitching["BB"])) / innings
    assert abs(whip - float(pitching["WHIP"])) < 0.02


def test_two_way_games_played_stays_per_side():
    """G means "games batted" on one line and "games pitched" on the other.

    The batting side is namespaced `g_bat` upstream precisely because the
    pitching block updates the same dict; an unprefixed key would have given
    Ohtani 14 games as a hitter. The client leaderboards gate on this number, so
    a collision here silently drops every regular from the AVG board.
    """
    rows = ingest._build_standard_stats_from_mlb(_two_way_stats())
    assert _by_category(rows, "hitting")["G"] == "114"
    assert _by_category(rows, "pitching")["G"] == "14"


def test_pure_batter_carries_games_played():
    rows = ingest._build_standard_stats_from_mlb({
        "player_type": "batter",
        "avg": "0.300", "pa": 500, "ab": 450, "h": 135, "g_bat": 111,
    })
    assert _by_category(rows, "hitting")["G"] == "111"


def test_two_way_colliding_labels_get_distinct_ids():
    rows = ingest._build_standard_stats_from_mlb(_two_way_stats())
    ids = [r["id"] for r in rows]
    assert len(ids) == len(set(ids)), "duplicate ids would collapse in an Identifiable list"
    assert "std-hit-H" in ids and "std-pit-H" in ids


def test_pure_pitcher_still_reads_unprefixed_keys():
    """emit() falls back to the bare key, so a legacy dict still builds."""
    rows = ingest._build_standard_stats_from_mlb({
        "player_type": "pitcher",
        "era": "2.82", "whip": "1.01", "ip": "120.0",
        "h": 88, "r": 40, "hr": 11, "bb": 33, "so": 145,
    })
    pitching = _by_category(rows, "pitching")
    assert pitching["H"] == "88"
    assert pitching["SO"] == "145"
    assert all(r["category"] == "pitching" for r in rows)


def test_pure_batter_line_is_unchanged_apart_from_category():
    rows = ingest._build_standard_stats_from_mlb({
        "player_type": "batter",
        "avg": "0.311", "obp": "0.398", "slg": "0.601", "ops": "0.999",
        "hr": 53, "rbi": 144, "r": 122, "h": 180, "bb": 133, "so": 171,
        "pa": 704, "ab": 579,
    })
    assert all(r["category"] == "hitting" for r in rows)
    hitting = _by_category(rows, "hitting")
    assert hitting["H"] == "180"
    assert hitting["AVG"] == "0.311"


def test_fielding_line_is_its_own_category():
    rows = ingest._build_standard_stats_from_mlb({
        "player_type": "two_way",
        "avg": "0.282", "ab": 373, "h": 105,
        "era": "1.79", "ip": "85.2", "p_h": 55,
        "e": 1, "a": 8, "po": 11, "dp": 0, "fpct": "0.950", "gf": 14,
    })
    fielding = _by_category(rows, "fielding")
    assert fielding["E"] == "1"
    assert fielding["FLD%"] == "0.950"


class TestValueSourcesForPercentileOnlyMetrics:
    """The metrics that used to ship a ranking with no number beside it.

    Each of these rendered as a bare "PERCENTILE" cell on the comparison
    screen and as a column of dashes on its own leaderboard.
    """

    def _store(self, data):
        store = ingest.ActualValueStore.__new__(ingest.ActualValueStore)
        store.season = 2026
        store._data = data
        return store

    def test_batter_hard_hit_reads_savants_own_column_name(self):
        # The prefetch stored ev95percent under a renamed key while the reader
        # asked for the raw name, so every batter came back blank.
        store = self._store({"batter_exitvelo": {592450: {"ev95percent": 57.3}}})
        assert store.get_value(592450, "hard_hit_percent", "batter") == "57.3%"

    def test_squared_up_is_scaled_from_savants_zero_to_one_rate(self):
        store = self._store({"bat_tracking": {691406: {"squared_up_per_swing": 0.24174}}})
        assert store.get_value(691406, "squared_up_rate", "batter") == "24.2%"

    def test_arm_strength_uses_average_not_max_throw(self):
        store = self._store({"arm_strength": {695506: {"arm_overall": 98.5}}})
        assert store.get_value(695506, "arm_strength", "batter") == "98.5 mph"

    def test_plate_discipline_resolves_per_side(self):
        store = self._store({
            "batter_agg": {592450: {"whiff_percent": 28.4, "chase_percent": 21.1}},
            "pitcher_agg": {694973: {"whiff_percent": 34.2, "chase_percent": 32.8}},
        })
        assert store.get_value(592450, "whiff_percent", "batter") == "28.4%"
        assert store.get_value(694973, "whiff_percent", "pitcher") == "34.2%"
        assert store.get_value(694973, "chase_percent", "pitcher") == "32.8%"

    def test_backfill_never_overwrites_a_qualified_row(self):
        store = self._store({"sprint_speed": {1: {"sprint_speed": 28.8}}})
        added = store._backfill(
            "sprint_speed",
            pd.DataFrame([
                {"player_id": 1, "sprint_speed": 99.9, "hp_to_1b": 4.0},
                {"player_id": 2, "sprint_speed": 26.1, "hp_to_1b": 4.5},
            ]),
            "player_id",
            {"sprint_speed": "sprint_speed", "hp_to_1b": "hp_to_1b"},
        )
        assert added == 1
        assert store._data["sprint_speed"][1]["sprint_speed"] == 28.8
        assert store.get_value(2, "sprint_speed", "batter") == "26.1 ft/s"


class TestPitcherPlateDiscipline:
    def test_whiff_and_chase_are_computed_for_pitchers(self):
        from statcast_aggregator import compute_pitcher_stats

        # Four pitches to one pitcher: a swinging strike in the zone, a foul in
        # the zone, a chase out of the zone, and a take out of the zone.
        df = pd.DataFrame([
            {"pitcher": 1, "description": "swinging_strike", "zone": 5,
             "pitch_name": "4-Seam Fastball", "release_spin_rate": 2400},
            {"pitcher": 1, "description": "foul", "zone": 5,
             "pitch_name": "4-Seam Fastball", "release_spin_rate": 2400},
            {"pitcher": 1, "description": "foul", "zone": 13,
             "pitch_name": "Slider", "release_spin_rate": 2600},
            {"pitcher": 1, "description": "ball", "zone": 13,
             "pitch_name": "Slider", "release_spin_rate": 2600},
        ])
        row = compute_pitcher_stats(df).iloc[0]
        # One whiff on three swings; one chase on two pitches outside.
        assert row["whiff_percent"] == pytest.approx(33.3, abs=0.1)
        assert row["chase_percent"] == pytest.approx(50.0)
