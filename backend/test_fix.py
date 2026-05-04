"""
Test script to verify the metric ingestion fixes.

This script tests the build_metrics_with_values function to ensure:
1. Metrics without actual values are skipped
2. Metrics with actual values are included correctly
"""

import logging
import sys
from unittest.mock import MagicMock

import pandas as pd

# Add the backend directory to the path
sys.path.insert(0, '/Users/jackwallner/baseball/backend')

from ingest import build_metrics_with_values, ActualValueStore, percentile_value

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def test_skip_metrics_without_actual_values():
    """Test that metrics without actual values are skipped."""
    
    # Create a mock value store that returns None for some metrics
    mock_store = MagicMock(spec=ActualValueStore)
    
    def mock_get_value(player_id, key, player_type):
        # Return values for some metrics, None for others
        values = {
            "exit_velocity": "92.5 mph",  # Has value
            "brl_percent": None,  # Missing value - should be skipped
            "hard_hit_percent": "45.2%",  # Has value
        }
        return values.get(key)
    
    mock_store.get_value = mock_get_value
    
    # Create a sample row with percentiles for all metrics
    row = pd.Series({
        "exit_velocity": 85,
        "brl_percent": 75,  # Has percentile but no actual value
        "hard_hit_percent": 60,
    })
    
    metric_defs = [
        ("exit_velocity", "EV", "Hitting"),
        ("brl_percent", "Barrel%", "Hitting"),
        ("hard_hit_percent", "Hard-Hit%", "Hitting"),
    ]
    
    # Build metrics
    metrics = build_metrics_with_values(row, "batter", metric_defs, 12345, mock_store)
    
    # Check results
    metric_labels = [m["label"] for m in metrics]
    
    print("\n" + "="*60)
    print("TEST: Skip metrics without actual values")
    print("="*60)
    
    print(f"\nMetrics returned: {metric_labels}")
    
    # EV should be present (has actual value)
    assert "EV" in metric_labels, "EV should be present (has actual value)"
    ev_metric = next(m for m in metrics if m["label"] == "EV")
    assert ev_metric["value"] == "92.5 mph", f"EV value should be '92.5 mph', got {ev_metric['value']}"
    assert "display_value" in ev_metric
    print(f"✅ EV: {ev_metric['display_value']}")
    
    # Barrel% should be skipped (no actual value)
    assert "Barrel%" not in metric_labels, "Barrel% should be skipped (no actual value)"
    print("✅ Barrel% correctly skipped (no actual value)")
    
    # Hard-Hit% should be present (has actual value)
    assert "Hard-Hit%" in metric_labels, "Hard-Hit% should be present (has actual value)"
    hh_metric = next(m for m in metrics if m["label"] == "Hard-Hit%")
    assert hh_metric["value"] == "45.2%", f"Hard-Hit% value should be '45.2%', got {hh_metric['value']}"
    print(f"✅ Hard-Hit%: {hh_metric['display_value']}")
    
    print("\n✅ All tests passed!")
    return True


def test_no_empty_values():
    """Test that no metrics have empty values."""
    
    mock_store = MagicMock(spec=ActualValueStore)
    
    def mock_get_value(player_id, key, player_type):
        # Return some values, empty string for others
        values = {
            "exit_velocity": "92.5 mph",
            "brl_percent": "",  # Empty string - should be treated as missing
        }
        return values.get(key) or None  # Convert empty to None
    
    mock_store.get_value = mock_get_value
    
    row = pd.Series({
        "exit_velocity": 85,
        "brl_percent": 75,
    })
    
    metric_defs = [
        ("exit_velocity", "EV", "Hitting"),
        ("brl_percent", "Barrel%", "Hitting"),
    ]
    
    metrics = build_metrics_with_values(row, "batter", metric_defs, 12345, mock_store)
    
    print("\n" + "="*60)
    print("TEST: No empty values in metrics")
    print("="*60)
    
    # Check no metric has empty value
    for metric in metrics:
        assert metric["value"] != "", f"Metric {metric['label']} has empty value"
        assert metric["value"] is not None, f"Metric {metric['label']} has None value"
        print(f"✅ {metric['label']}: value='{metric['value']}' (not empty)")
    
    # Barrel% should be skipped
    metric_labels = [m["label"] for m in metrics]
    assert "Barrel%" not in metric_labels, "Barrel% should be skipped (empty value)"
    print("✅ Barrel% correctly skipped (empty value)")
    
    print("\n✅ All tests passed!")
    return True


def test_percentile_value_function():
    """Test the percentile_value helper function."""
    
    print("\n" + "="*60)
    print("TEST: percentile_value function")
    print("="*60)
    
    # Valid values
    assert percentile_value(85) == 85, "Integer should return as-is"
    assert percentile_value(85.4) == 85, "Should round to nearest integer"
    assert percentile_value(85.6) == 86, "Should round up"
    print("✅ Valid percentile values handled correctly")
    
    # Edge cases
    assert percentile_value(0) == 0, "Zero should return 0"
    assert percentile_value(100) == 100, "100 should return 100"
    assert percentile_value(-5) == 0, "Negative should clamp to 0"
    assert percentile_value(105) == 100, "Over 100 should clamp to 100"
    print("✅ Edge cases handled correctly")
    
    # Invalid values
    assert percentile_value(None) is None, "None should return None"
    assert percentile_value(float('nan')) is None, "NaN should return None"
    assert percentile_value("") is None, "Empty string should return None"
    print("✅ Invalid values return None")
    
    print("\n✅ All tests passed!")
    return True


def main():
    """Run all tests."""
    print("\n" + "="*70)
    print("TESTING METRIC INGESTION FIXES")
    print("="*70)
    
    all_passed = True
    
    try:
        test_skip_metrics_without_actual_values()
    except AssertionError as e:
        print(f"\n❌ FAILED: {e}")
        all_passed = False
    
    try:
        test_no_empty_values()
    except AssertionError as e:
        print(f"\n❌ FAILED: {e}")
        all_passed = False
    
    try:
        test_percentile_value_function()
    except AssertionError as e:
        print(f"\n❌ FAILED: {e}")
        all_passed = False
    
    print("\n" + "="*70)
    if all_passed:
        print("✅ ALL TESTS PASSED")
    else:
        print("❌ SOME TESTS FAILED")
    print("="*70 + "\n")
    
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
