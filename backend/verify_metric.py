"""
Verify that a specific player's metric has both percentile and actual value.

Usage:
    python verify_metric.py --player "Mike Trout" --metric "Barrel%"
    python verify_metric.py --player "Mike Trout" --metric "xwOBA" --season 2026
    python verify_metric.py --id 545361 --metric "Barrel%"
"""

import argparse
import os
import sys
from supabase import create_client


def get_env_or_creds():
    """Get Supabase credentials from env or ~/.baseball_credentials."""
    url = os.getenv('SUPABASE_URL')
    key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')
    
    if not url or not key:
        creds_file = os.path.expanduser('~/.baseball_credentials')
        if os.path.exists(creds_file):
            with open(creds_file) as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        if k == 'SUPABASE_URL':
                            url = v
                        elif k == 'SUPABASE_SERVICE_ROLE_KEY':
                            key = v
    
    return url, key


def verify_metric(identifier: str, metric_label: str, season: int = 2026, use_id: bool = False):
    """Verify a specific metric has both percentile and actual value."""
    
    url, key = get_env_or_creds()
    if not url or not key:
        print("❌ Error: Could not find Supabase credentials")
        sys.exit(1)
    
    supabase = create_client(url, key)
    
    # Fetch player
    if use_id:
        result = supabase.table('player_snapshots').select('*').eq('season', season).eq('id', int(identifier)).execute()
    else:
        result = supabase.table('player_snapshots').select('*').eq('season', season).ilike('name', f'%{identifier}%').execute()
    
    players = result.data
    
    if not players:
        print(f"❌ No player found matching '{identifier}' for season {season}")
        sys.exit(1)
    
    if len(players) > 1:
        print(f"⚠️  Found {len(players)} players matching '{identifier}':")
        for p in players:
            print(f"   - {p['name']} ({p['team']}, ID: {p['id']})")
        print(f"\nUsing first match: {players[0]['name']}")
    
    player = players[0]
    
    print(f"\n{'='*60}")
    print(f"VERIFICATION: {player['name']} (Season {season})")
    print(f"{'='*60}")
    print(f"Player ID: {player['id']}")
    print(f"Team: {player['team']}")
    print(f"Type: {player['player_type']}")
    print(f"Position: {player.get('position', 'N/A')}")
    print()
    
    # Find the specific metric
    metrics = player.get('metrics', [])
    target_metric = None
    
    for m in metrics:
        if m.get('label', '').lower() == metric_label.lower():
            target_metric = m
            break
    
    if not target_metric:
        print(f"🔴 METRIC NOT FOUND: '{metric_label}'")
        print(f"\nAvailable metrics for this player:")
        for m in metrics:
            label = m.get('label', 'Unknown')
            has_value = '✅' if m.get('value') else '❌'
            has_percentile = '✅' if m.get('percentile') is not None else '❌'
            print(f"   {has_value} {has_percentile} {label}")
        sys.exit(1)
    
    # Analyze the metric
    label = target_metric.get('label', 'Unknown')
    value = target_metric.get('value')
    percentile = target_metric.get('percentile')
    display_value = target_metric.get('display_value', 'N/A')
    
    print(f"📊 METRIC: {label}")
    print(f"{'-'*60}")
    print(f"  Actual Value:    {value if value else '❌ MISSING'}")
    print(f"  Percentile:      {percentile if percentile is not None else '❌ MISSING'}")
    print(f"  Display Value:   {display_value}")
    print()
    
    # Verification status
    has_actual = value is not None and str(value).strip() != ''
    has_percentile = percentile is not None
    
    if has_actual and has_percentile:
        print(f"✅ VERIFIED: Both actual value and percentile present")
        print(f"   The metric is complete and will display correctly.")
        return True
    elif has_percentile and not has_actual:
        print(f"🔴 ERROR: Percentile present but actual value is missing!")
        print(f"   This metric would show empty value in the app.")
        return False
    elif has_actual and not has_percentile:
        print(f"⚠️  WARNING: Actual value present but percentile is missing")
        print(f"   Metric will show but without percentile ranking.")
        return False
    else:
        print(f"🔴 ERROR: Both actual value and percentile are missing")
        return False


def main():
    parser = argparse.ArgumentParser(description='Verify player metric has both value and percentile')
    parser.add_argument('--player', '-p', help='Player name (partial match allowed)')
    parser.add_argument('--id', '-i', type=int, help='Player ID')
    parser.add_argument('--metric', '-m', required=True, help='Metric label (e.g., "Barrel%", "xwOBA", "EV")')
    parser.add_argument('--season', '-s', type=int, default=2026, help='Season year (default: 2026)')
    
    args = parser.parse_args()
    
    if not args.player and not args.id:
        print("❌ Error: Must specify --player or --id")
        sys.exit(1)
    
    use_id = args.id is not None
    identifier = str(args.id) if args.id else args.player
    
    success = verify_metric(identifier, args.metric, args.season, use_id)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
