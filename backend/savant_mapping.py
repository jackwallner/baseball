"""
Mapping of Baseball Savant percentile stats to their actual value sources.

This module maps each percentile ranking (0-100) to the corresponding
function and column that provides the actual stat value.
"""

from dataclasses import dataclass
from typing import Callable, Optional
import pandas as pd

# Import pybaseball functions
from pybaseball import (
    statcast_sprint_speed,
    statcast_batter_expected_stats,
    statcast_batter_exitvelo_barrels,
    statcast_pitcher_expected_stats,
    statcast_pitcher_exitvelo_barrels,
    statcast_pitcher_pitch_arsenal,
)
from pybaseball.statcast_fielding import statcast_outs_above_average


@dataclass
class ValueSource:
    """Defines where to get actual values for a percentile stat."""
    func: Callable
    column: str
    min_param: str  # Parameter name for minimum qualifier (e.g., 'min_pa', 'min_opp')
    min_value: int  # Default minimum qualifier value
    format_str: str  # How to format the value (e.g., '.3f', '.1f', '.0f', '.1%')
    unit: str  # Unit suffix (e.g., ' ft/s', ' mph', '')


# Mapping of percentile metric key -> ValueSource for actual values
BATTER_VALUE_SOURCES: dict[str, ValueSource] = {
    # Expected stats -> statcast_batter_expected_stats
    "xwoba": ValueSource(
        func=statcast_batter_expected_stats,
        column="est_woba",
        min_param="min_pa",
        min_value=100,
        format_str=".3f",
        unit="",
    ),
    "xba": ValueSource(
        func=statcast_batter_expected_stats,
        column="est_ba",
        min_param="min_pa",
        min_value=100,
        format_str=".3f",
        unit="",
    ),
    "xslg": ValueSource(
        func=statcast_batter_expected_stats,
        column="est_slg",
        min_param="min_pa",
        min_value=100,
        format_str=".3f",
        unit="",
    ),
    "xiso": ValueSource(
        func=statcast_batter_expected_stats,
        column="est_woba",  # No direct xISO, derive from xSLG - xBA or use woba proxy
        min_param="min_pa",
        min_value=100,
        format_str=".3f",
        unit="",
    ),
    "xobp": ValueSource(
        func=statcast_batter_expected_stats,
        column="est_woba",  # No direct xOBP, approximate
        min_param="min_pa",
        min_value=100,
        format_str=".3f",
        unit="",
    ),
    
    # Exit velocity / barrels -> statcast_batter_exitvelo_barrels
    "exit_velocity": ValueSource(
        func=statcast_batter_exitvelo_barrels,
        column="avg_hit_speed",
        min_param="min_angle",
        min_value=100,
        format_str=".1f",
        unit=" mph",
    ),
    "brl_percent": ValueSource(
        func=statcast_batter_exitvelo_barrels,
        column="brl_percent",
        min_param="min_angle",
        min_value=100,
        format_str=".1f",
        unit="%",
    ),
    "hard_hit_percent": ValueSource(
        func=statcast_batter_exitvelo_barrels,
        column="ev95percent",
        min_param="min_angle",
        min_value=100,
        format_str=".1f",
        unit="%",
    ),
    "max_ev": ValueSource(
        func=statcast_batter_exitvelo_barrels,
        column="max_hit_speed",
        min_param="min_angle",
        min_value=100,
        format_str=".1f",
        unit=" mph",
    ),
    # launch_angle_sweet_spot -> anglesweetspotpercent
    "launch_angle_sweet_spot": ValueSource(
        func=statcast_batter_exitvelo_barrels,
        column="anglesweetspotpercent",
        min_param="min_angle",
        min_value=100,
        format_str=".1f",
        unit="%",
    ),
    
    # Sprint speed -> statcast_sprint_speed (separate handling needed)
    "sprint_speed": ValueSource(
        func=statcast_sprint_speed,
        column="sprint_speed",
        min_param="min_opp",
        min_value=25,
        format_str=".1f",
        unit=" ft/s",
    ),
    
    # Fielding -> statcast_outs_above_average
    "oaa": ValueSource(
        func=statcast_outs_above_average,
        column="outs_above_average",
        min_param="min_att",
        min_value=25,
        format_str=".0f",
        unit="",
    ),
    
    # Note: These plate discipline stats only have percentiles in pybaseball
    # No actual value sources available:
    # - bat_speed, squared_up_rate, swing_length (newer tracking stats)
    # - chase_percent, whiff_percent, k_percent, bb_percent
    # - arm_value, arm_strength (no direct source)
}


PITCHER_VALUE_SOURCES: dict[str, ValueSource] = {
    # Expected stats -> statcast_pitcher_expected_stats
    "xera": ValueSource(
        func=statcast_pitcher_expected_stats,
        column="xera",
        min_param="min_pa",
        min_value=25,
        format_str=".2f",
        unit="",
    ),
    "xwoba": ValueSource(
        func=statcast_pitcher_expected_stats,
        column="est_woba",
        min_param="min_pa",
        min_value=25,
        format_str=".3f",
        unit="",
    ),
    "xba": ValueSource(
        func=statcast_pitcher_expected_stats,
        column="est_ba",
        min_param="min_pa",
        min_value=25,
        format_str=".3f",
        unit="",
    ),
    "xslg": ValueSource(
        func=statcast_pitcher_expected_stats,
        column="est_slg",
        min_param="min_pa",
        min_value=25,
        format_str=".3f",
        unit="",
    ),
    "xiso": ValueSource(
        func=statcast_pitcher_expected_stats,
        column="est_slg",  # Approximate
        min_param="min_pa",
        min_value=25,
        format_str=".3f",
        unit="",
    ),
    "xobp": ValueSource(
        func=statcast_pitcher_expected_stats,
        column="est_woba",  # Approximate
        min_param="min_pa",
        min_value=25,
        format_str=".3f",
        unit="",
    ),
    
    # Exit velocity against -> statcast_pitcher_exitvelo_barrels
    "exit_velocity": ValueSource(
        func=statcast_pitcher_exitvelo_barrels,
        column="avg_hit_speed",
        min_param="min_angle",
        min_value=25,
        format_str=".1f",
        unit=" mph",
    ),
    "brl_percent": ValueSource(
        func=statcast_pitcher_exitvelo_barrels,
        column="brl_percent",
        min_param="min_angle",
        min_value=25,
        format_str=".1f",
        unit="%",
    ),
    "hard_hit_percent": ValueSource(
        func=statcast_pitcher_exitvelo_barrels,
        column="ev95percent",
        min_param="min_angle",
        min_value=25,
        format_str=".1f",
        unit="%",
    ),
    "max_ev": ValueSource(
        func=statcast_pitcher_exitvelo_barrels,
        column="max_hit_speed",
        min_param="min_angle",
        min_value=25,
        format_str=".1f",
        unit=" mph",
    ),
    
    # Pitch arsenal -> statcast_pitcher_pitch_arsenal
    "fb_velocity": ValueSource(
        func=statcast_pitcher_pitch_arsenal,
        column="ff_avg_speed",
        min_param="min_p",
        min_value=50,
        format_str=".1f",
        unit=" mph",
    ),
    "fb_spin": ValueSource(
        func=statcast_pitcher_pitch_arsenal,
        column="ff_avg_spin",  # May not exist, check
        min_param="min_p",
        min_value=50,
        format_str=".0f",
        unit=" rpm",
    ),
    # Note: curve_spin exists but pybaseball may not return it directly
    
    # Note: Plate discipline stats only have percentiles
    # - k_percent, bb_percent, whiff_percent, chase_percent
}


def format_value(value: float, source: ValueSource) -> str:
    """Format a numeric value according to the source specification."""
    if pd.isna(value):
        return ""
    try:
        formatted = f"{value:{source.format_str}}"
        return formatted + source.unit
    except (ValueError, TypeError):
        return str(value)


def get_all_value_sources(player_type: str) -> dict[str, ValueSource]:
    """Get all value sources for a player type."""
    if player_type == "batter":
        return BATTER_VALUE_SOURCES
    return PITCHER_VALUE_SOURCES
