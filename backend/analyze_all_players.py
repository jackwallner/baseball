"""
Comprehensive analysis of all 2026 player metrics.
Generates a detailed report showing which metrics are available vs missing.
"""

import os
import sys
from collections import defaultdict
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
                    if '=' in line and 'export' not in line:
                        k, v = line.strip().split('=', 1)
                        if k == 'SUPABASE_URL':
                            url = v
                        elif k == 'SUPABASE_SERVICE_ROLE_KEY':
                            key = v
    
    return url, key


def analyze_all_players(season: int = 2026):
    """Analyze metrics for all players in a season."""
    
    url, key = get_env_or_creds()
    if not url or not key:
        print("❌ Error: Could not find Supabase credentials")
        sys.exit(1)
    
    supabase = create_client(url, key)
    
    print(f"📊 Fetching all players for season {season}...")
    all_players = []
    offset = 0
    limit = 1000
    
    while True:
        result = supabase.table('player_snapshots').select('*').eq('season', season).range(offset, offset + limit - 1).execute()
        players = result.data
        if not players:
            break
        all_players.extend(players)
        offset += limit
        if len(players) < limit:
            break
    
    print(f"✅ Fetched {len(all_players)} players\n")
    
    # Categorize players
    batters = [p for p in all_players if p.get('player_type') == 'batter']
    pitchers = [p for p in all_players if p.get('player_type') == 'pitcher']
    
    print("=" * 70)
    print(f"COMPREHENSIVE ANALYSIS: Season {season}")
    print("=" * 70)
    print(f"\nTotal Players: {len(all_players)}")
    print(f"  - Batters: {len(batters)}")
    print(f"  - Pitchers: {len(pitchers)}")
    print()
    
    # Analyze metrics
    all_metrics = defaultdict(lambda: {'count': 0, 'with_value': 0, 'with_percentile': 0, 'both': 0})
    player_completeness = []
    
    for player in all_players:
        metrics = player.get('metrics', [])
        player_type = player.get('player_type', 'unknown')
        
        has_value_count = 0
        has_both_count = 0
        total_metrics = len(metrics)
        
        for m in metrics:
            label = m.get('label', 'Unknown')
            value = m.get('value')
            percentile = m.get('percentile')
            
            has_value = value is not None and str(value).strip() != ''
            has_percentile = percentile is not None
            
            all_metrics[label]['count'] += 1
            if has_value:
                all_metrics[label]['with_value'] += 1
            if has_percentile:
                all_metrics[label]['with_percentile'] += 1
            if has_value and has_percentile:
                all_metrics[label]['both'] += 1
                has_both_count += 1
            if has_value:
                has_value_count += 1
        
        completeness = (has_both_count / total_metrics * 100) if total_metrics > 0 else 0
        player_completeness.append({
            'name': player.get('name', 'Unknown'),
            'team': player.get('team', 'Unknown'),
            'type': player_type,
            'completeness': completeness,
            'total': total_metrics,
            'complete': has_both_count
        })
    
    # Sort by completeness
    player_completeness.sort(key=lambda x: x['completeness'], reverse=True)
    
    # Overall completeness
    avg_completeness = sum(p['completeness'] for p in player_completeness) / len(player_completeness) if player_completeness else 0
    print(f"\n📈 OVERALL COMPLETENESS: {avg_completeness:.1f}%")
    print(f"   (Average % of metrics that have both value AND percentile)")
    print()
    
    # Top 10 most complete players
    print("=" * 70)
    print("TOP 10 MOST COMPLETE PLAYERS")
    print("=" * 70)
    for i, p in enumerate(player_completeness[:10], 1):
        print(f"{i:2}. {p['name'][:25]:25} ({p['team']:3}) {p['type']:7} - {p['completeness']:5.1f}% ({p['complete']}/{p['total']})")
    
    # Bottom 10 least complete players
    print("\n" + "=" * 70)
    print("BOTTOM 10 LEAST COMPLETE PLAYERS")
    print("=" * 70)
    for i, p in enumerate(player_completeness[-10:], 1):
        print(f"{i:2}. {p['name'][:25]:25} ({p['team']:3}) {p['type']:7} - {p['completeness']:5.1f}% ({p['complete']}/{p['total']})")
    
    # Metric breakdown
    print("\n" + "=" * 70)
    print("METRIC AVAILABILITY BREAKDOWN")
    print("=" * 70)
    print(f"{'Metric':<25} {'Total':>8} {'Has Value':>10} {'Has %ile':>10} {'Both':>10} {'% Both':>8}")
    print("-" * 70)
    
    # Sort metrics by "both" percentage
    sorted_metrics = sorted(all_metrics.items(), key=lambda x: x[1]['both'] / len(all_players) * 100 if len(all_players) > 0 else 0, reverse=True)
    
    for label, stats in sorted_metrics:
        total = stats['count']
        with_value = stats['with_value']
        with_percentile = stats['with_percentile']
        both = stats['both']
        pct_both = (both / total * 100) if total > 0 else 0
        print(f"{label:<25} {total:>8} {with_value:>10} {with_percentile:>10} {both:>10} {pct_both:>7.1f}%")
    
    # Summary stats
    print("\n" + "=" * 70)
    print("SUMMARY STATISTICS")
    print("=" * 70)
    
    fully_complete = sum(1 for p in player_completeness if p['completeness'] == 100)
    over_80 = sum(1 for p in player_completeness if p['completeness'] >= 80)
    under_50 = sum(1 for p in player_completeness if p['completeness'] < 50)
    
    print(f"\nPlayers with 100% complete metrics: {fully_complete}/{len(player_completeness)} ({fully_complete/len(player_completeness)*100:.1f}%)")
    print(f"Players with ≥80% complete metrics: {over_80}/{len(player_completeness)} ({over_80/len(player_completeness)*100:.1f}%)")
    print(f"Players with <50% complete metrics: {under_50}/{len(player_completeness)} ({under_50/len(player_completeness)*100:.1f}%)")
    
    # Missing metrics breakdown
    print("\n" + "=" * 70)
    print("MOST PROBLEMATIC METRICS (lowest % with both value and percentile)")
    print("=" * 70)
    
    problematic = [(label, stats) for label, stats in sorted_metrics if (stats['both'] / stats['count'] * 100 if stats['count'] > 0 else 0) < 50]
    for label, stats in problematic[:10]:
        total = stats['count']
        with_value = stats['with_value']
        with_percentile = stats['with_percentile']
        both = stats['both']
        pct_both = (both / total * 100) if total > 0 else 0
        
        # Calculate what's missing
        missing_value = with_percentile - both  # Has percentile but no value
        missing_percentile = with_value - both  # Has value but no percentile
        missing_both = total - with_value - with_percentile + both
        
        print(f"\n{label}:")
        print(f"  Complete (both):     {both:>4}/{total:<4} ({pct_both:>5.1f}%)")
        print(f"  Missing value:       {missing_value:>4} (have percentile only)")
        print(f"  Missing percentile:  {missing_percentile:>4} (have value only)")
        print(f"  Missing both:        {missing_both:>4}")


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Analyze all player metrics for a season')
    parser.add_argument('--season', '-s', type=int, default=2026, help='Season year (default: 2026)')
    args = parser.parse_args()
    
    analyze_all_players(args.season)
