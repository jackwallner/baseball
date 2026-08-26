"""Postseason values looked up on the regular season's own percentile curve.

Not a percentile we invented: the curve is read back off player_snapshots, so
every bar is answerable to a Savant page the user can open.
"""

import rollup_postseason_percentiles as pp


def _snapshot(pairs):
    """One player's metrics rows, as (label, value, percentile)."""
    return {"metrics": [
        {"label": label, "value": value, "percentile": pct}
        for label, value, pct in pairs
    ]}


class TestNumericParsing:
    def test_strips_the_units_savant_publishes(self):
        assert pp._numeric("94.2 mph") == 94.2
        assert pp._numeric("48.5%") == 48.5
        assert pp._numeric("2,350 rpm") == 2350.0

    def test_a_blank_value_is_not_a_zero(self):
        """The backend emits empty value strings for some rows, and treating
        those as 0.0 would drag the bottom of every curve to the floor."""
        assert pp._numeric("") is None
        assert pp._numeric(None) is None
        assert pp._numeric("  ") is None


class TestCurves:
    def test_builds_one_sorted_curve_per_rankable_metric(self):
        snaps = [
            _snapshot([("EV", "88.0 mph", 10), ("xwOBA", ".310", 50)]),
            _snapshot([("EV", "94.0 mph", 90)]),
        ]
        curves = pp.build_curves(snaps)
        assert curves["ev_avg"] == [(88.0, 10), (94.0, 90)]

    def test_expected_stats_are_never_ranked(self):
        """xwOBA needs hundreds of plate appearances. October never has them,
        so it must not acquire a curve at all."""
        curves = pp.build_curves([_snapshot([("xwOBA", ".310", 50)])])
        assert curves == {}

    def test_rows_with_no_value_are_skipped(self):
        curves = pp.build_curves([_snapshot([("EV", "", 40)])])
        assert curves == {}


class TestLookup:
    curve = [(85.0, 5), (90.0, 50), (95.0, 95)]

    def test_interpolates_between_two_known_points(self):
        assert pp.percentile_for(self.curve, 92.5) == 72

    def test_an_exact_match_takes_its_percentile(self):
        assert pp.percentile_for(self.curve, 90.0) == 50

    def test_clamps_rather_than_extrapolating(self):
        """A postseason value past anything a qualified regular managed lands on
        the end of the curve; the distribution has nothing further to say."""
        assert pp.percentile_for(self.curve, 120.0) == 95
        assert pp.percentile_for(self.curve, 40.0) == 5

    def test_an_empty_curve_yields_nothing(self):
        assert pp.percentile_for([], 90.0) is None


class TestSampleGate:
    curves = {"ev_avg": [(85.0, 5), (95.0, 95)], "whiff_pct": [(20.0, 90), (30.0, 10)]}

    def test_a_thin_batted_ball_sample_is_not_ranked(self):
        """A three-game exit is not a distribution, and a coloured bar would
        claim otherwise."""
        out = pp.build_metrics({"ev_avg": 94.0}, self.curves, batted_balls=4, pitches=500)
        assert out == []

    def test_a_deep_run_is_ranked(self):
        out = pp.build_metrics({"ev_avg": 94.0}, self.curves, batted_balls=40, pitches=500)
        assert len(out) == 1
        assert out[0]["label"] == "EV"
        assert 5 <= out[0]["percentile"] <= 95

    def test_plate_discipline_gates_on_pitches_not_batted_balls(self):
        thin = pp.build_metrics({"whiff_pct": 22.0}, self.curves, batted_balls=0, pitches=20)
        deep = pp.build_metrics({"whiff_pct": 22.0}, self.curves, batted_balls=0, pitches=400)
        assert thin == []
        assert len(deep) == 1

    def test_a_metric_absent_from_the_line_is_skipped(self):
        assert pp.build_metrics({}, self.curves, batted_balls=99, pitches=999) == []
