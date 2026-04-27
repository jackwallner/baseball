import pytest
import pandas as pd


@pytest.fixture
def sample_batter_row():
    return pd.Series(
        {
            "player_id": 592450,
            "player_name": "Judge, Aaron",
            "team": "NYY",
            "position": "RF",
            "bats": "R",
            "throws": "R",
            "xwoba": 100,
            "xba": 99,
            "exit_velocity": 96.2,
        }
    )


@pytest.fixture
def sample_pitcher_row():
    return pd.Series(
        {
            "player_id": 694973,
            "player_name": "Skenes, Paul",
            "team": "PIT",
            "position": "SP",
            "bats": "R",
            "throws": "R",
            "xera": 99,
            "xwoba": 98,
        }
    )


@pytest.fixture
def empty_dataframe():
    return pd.DataFrame()
