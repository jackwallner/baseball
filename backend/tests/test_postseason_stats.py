"""Postseason standard lines: the one postseason board that can carry numbers.

Percentiles stop at the regular season because Savant publishes no postseason
percentile leaderboards. Standard stats do not, so these rows are what the
postseason boards actually show.
"""

import ingest_postseason_stats as ps


def _hit(**over):
    stat = {"avg": ".310", "obp": ".390", "slg": ".600", "ops": ".990",
            "homeRuns": 4, "rbi": 9, "runs": 8, "hits": 13, "doubles": 3,
            "triples": 0, "baseOnBalls": 6, "strikeOuts": 11, "stolenBases": 1,
            "caughtStealing": 0, "plateAppearances": 48, "atBats": 42,
            "gamesPlayed": 12}
    stat.update(over)
    return stat


def _pitch(**over):
    stat = {"era": "2.45", "whip": "0.95", "wins": 2, "losses": 1, "saves": 0,
            "inningsPitched": "18.1", "hits": 12, "runs": 5, "earnedRuns": 5,
            "homeRuns": 1, "baseOnBalls": 5, "strikeOuts": 24,
            "gamesPlayed": 3, "gamesStarted": 3, "battersFaced": 70}
    stat.update(over)
    return stat


def _person(name="Player, A", position="CF", stat=None):
    return {"name": name, "position": position, "stat": stat}


class TestBuildRows:
    def test_a_hitter_gets_a_hitting_line(self):
        rows = ps.build_rows(2026, {1: "LAD"}, {1: _person(stat=_hit())}, {})
        assert len(rows) == 1
        row = rows[0]
        assert row["player_type"] == "batter"
        assert row["team"] == "LAD"
        labels = {s["label"]: s["value"] for s in row["standard_stats"]}
        assert labels["HR"] == "4"
        # Same formatting the regular-season rows carry (live rows read
        # "0.333", not ".333"); the app trims the leading zero for display.
        assert labels["AVG"] == "0.310"

    def test_a_pitcher_gets_a_pitching_line(self):
        rows = ps.build_rows(2026, {2: "NYY"}, {}, {2: _person(position="SP", stat=_pitch())})
        assert rows[0]["player_type"] == "pitcher"
        labels = {s["label"] for s in rows[0]["standard_stats"]}
        assert {"ERA", "WHIP", "SO"} <= labels

    def test_a_fielder_gets_a_fielding_line(self):
        rows = ps.build_rows(
            2026,
            {4: "SEA"},
            {},
            {},
            {4: {"name": "Fielder, A", "position": "SS", "stats": {
                "e": 1, "a": 18, "po": 12, "dp": 4, "gf": 3, "fpct": "0.968"
            }}},
        )
        assert rows[0]["player_type"] == "batter"
        labels = {s["label"]: s["value"] for s in rows[0]["standard_stats"]}
        assert labels["E"] == "1"
        assert labels["FLD%"] == "0.968"

    def test_a_two_way_player_keeps_both_lines_apart(self):
        """The bug this namespacing exists for: batting H and hits allowed are
        both labelled H, and only the category tells them apart."""
        rows = ps.build_rows(
            2026, {3: "LAA"},
            {3: _person(stat=_hit(hits=13))},
            {3: _person(stat=_pitch(hits=12))},
        )
        row = rows[0]
        assert row["player_type"] == "two_way"
        hits = {s["category"]: s["value"] for s in row["standard_stats"] if s["label"] == "H"}
        assert hits["hitting"] == "13"
        assert hits["pitching"] == "12"

    def test_a_player_with_no_postseason_line_is_skipped(self):
        """On the roster because he was rostered, but never appeared."""
        rows = ps.build_rows(2026, {4: "SEA"}, {}, {})
        assert rows == []

    def test_the_season_is_stamped_on_every_row(self):
        rows = ps.build_rows(2026, {1: "LAD"}, {1: _person(stat=_hit())}, {})
        assert rows[0]["season"] == 2026

    def test_ingest_leaves_percentiles_for_the_enrichment_step(self):
        """Standard rows land before the separate curve-based enrichment."""
        rows = ps.build_rows(2026, {1: "LAD"}, {1: _person(stat=_hit())}, {})
        assert "metrics" not in rows[0]


class TestRosterFromGameLogs:
    def test_the_newest_team_wins_for_a_midseason_move(self):
        class Q:
            def select(self, *a, **k): return self
            def eq(self, *a, **k): return self
            def order(self, *a, **k): return self
            def range(self, *a, **k): return self

            def execute(self):
                class R:
                    # Date-descending, as the query asks for.
                    data = [
                        {"player_id": 1, "team": "LAD", "game_date": "2026-10-20"},
                        {"player_id": 1, "team": "SD", "game_date": "2026-10-04"},
                    ]
                return R()

        class C:
            def table(self, _name): return Q()

        assert ps._postseason_roster(C(), 2026) == {1: "LAD"}


def test_the_request_asks_for_the_postseason_split():
    """Forgetting gameType=P silently answers with the regular season, which
    would make this whole script a duplicate of ingest.py."""
    assert ps.POSTSEASON_GAME_TYPE == "P"
