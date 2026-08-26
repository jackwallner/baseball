"""Postseason values looked up on the regular season's own percentile curve.

Not a percentile we invented: the curve is read back off player_snapshots, so
every bar is answerable to a Savant page the user can open.
"""

import rollup_postseason_percentiles as pp


def _snapshot(player_type, pairs):
    return {
        "player_type": player_type,
        "metrics": [
            {"label": label, "value": value, "percentile": pct}
            for label, value, pct in pairs
        ],
    }


class TestNumericParsing:
    def test_strips_the_units_savant_publishes(self):
        assert pp._numeric("94.2 mph") == 94.2
        assert pp._numeric("48.5%") == 48.5
        assert pp._numeric("2,350 rpm") == 2350.0

    def test_a_blank_value_is_not_a_zero(self):
        """Treating an empty value string as 0.0 would drag the bottom of every
        curve to the floor."""
        assert pp._numeric("") is None
        assert pp._numeric(None) is None
        assert pp._numeric("  ") is None


class TestCurves:
    def test_builds_a_curve_per_side_and_metric(self):
        curves = pp.build_curves([
            _snapshot("batter", [("EV", "88.0 mph", 10)]),
            _snapshot("batter", [("EV", "94.0 mph", 90)]),
        ])
        assert curves[("batter", "ev_avg")] == [(88.0, 10), (94.0, 90)]

    def test_pitchers_and_batters_never_share_a_curve(self):
        """A pitcher's xwOBA is the xwOBA he allowed and his percentile runs the
        other way. One merged curve would rank every pitcher as if batting."""
        curves = pp.build_curves([
            _snapshot("batter", [("xwOBA", "0.400", 95)]),
            _snapshot("pitcher", [("xwOBA", "0.325", 31)]),
        ])
        assert curves[("batter", "xwoba")] == [(0.400, 95)]
        assert curves[("pitcher", "opp_xwoba")] == [(0.325, 31)]

    def test_expected_stats_are_ranked_like_everything_else(self):
        """The postseason is a small sample throughout; xwOBA is not singled
        out for it."""
        curves = pp.build_curves([_snapshot("batter", [("xwOBA", "0.310", 50)])])
        assert ("batter", "xwoba") in curves

    def test_two_way_players_do_not_pollute_either_curve(self):
        assert pp.build_curves([_snapshot("two_way", [("EV", "94.0 mph", 90)])]) == {}

    def test_rows_with_no_value_are_skipped(self):
        assert pp.build_curves([_snapshot("batter", [("EV", "", 40)])]) == {}


class TestLookup:
    curve = [(85.0, 5), (90.0, 50), (95.0, 95)]

    def test_interpolates_between_two_known_points(self):
        assert pp.percentile_for(self.curve, 92.5) == 72

    def test_an_exact_match_takes_its_percentile(self):
        assert pp.percentile_for(self.curve, 90.0) == 50

    def test_clamps_rather_than_extrapolating(self):
        assert pp.percentile_for(self.curve, 120.0) == 95
        assert pp.percentile_for(self.curve, 40.0) == 5

    def test_a_descending_pitcher_curve_reads_correctly(self):
        """Lower allowed is better, so the curve falls as the value rises."""
        descending = [(0.250, 90), (0.325, 31), (0.400, 5)]
        assert pp.percentile_for(descending, 0.250) == 90
        assert pp.percentile_for(descending, 0.400) == 5

    def test_an_empty_curve_yields_nothing(self):
        assert pp.percentile_for([], 90.0) is None


class TestBuildMetrics:
    curves = {
        ("batter", "ev_avg"): [(85.0, 5), (95.0, 95)],
        ("batter", "xwoba"): [(0.250, 5), (0.400, 95)],
        ("pitcher", "opp_xwoba"): [(0.250, 95), (0.400, 5)],
    }

    def test_a_three_game_sample_is_still_ranked(self):
        """No sample gate, by decision. A wild-card exit is three games, and a
        metric hidden for everyone but the last two teams is one nobody sees."""
        out = pp.build_metrics({"ev_avg": 94.0}, self.curves, "batter")
        assert len(out) == 1
        assert out[0]["label"] == "EV"

    def test_expected_stats_come_through(self):
        out = pp.build_metrics({"xwoba": 0.400}, self.curves, "batter")
        assert [m["label"] for m in out] == ["xwOBA"]
        assert out[0]["percentile"] == 95

    def test_a_pitcher_is_ranked_on_the_pitcher_curve(self):
        out = pp.build_metrics({"opp_xwoba": 0.250}, self.curves, "pitcher")
        assert out[0]["percentile"] == 95
        assert out[0]["category"] == "pitching"

    def test_the_two_sides_of_a_two_way_player_stay_apart(self):
        """Same label, two rows, and only the id and category tell them
        apart."""
        batting = pp.build_metrics({"xwoba": 0.400}, self.curves, "batter")
        pitching = pp.build_metrics({"opp_xwoba": 0.250}, self.curves, "pitcher")
        assert batting[0]["label"] == pitching[0]["label"] == "xwOBA"
        assert batting[0]["id"] != pitching[0]["id"]

    def test_a_metric_absent_from_the_line_is_skipped(self):
        assert pp.build_metrics({}, self.curves, "batter") == []

    def test_an_unknown_side_ranks_nothing(self):
        assert pp.build_metrics({"ev_avg": 94.0}, self.curves, "two_way") == []
