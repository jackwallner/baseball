#!/usr/bin/env python3
"""Export every season before the app's current one into a bundled JSON file.

The cutoff is read from `StatScoutSeason.current`, so the rollover stays the
one-line change StoreService.swift promises.
"""
import json
import os
import re
import urllib.request

with open("StatScout/Services/StoreService.swift") as f:
    CURRENT_SEASON = int(re.search(r"static let current = (\d{4})", f.read()).group(1))

SUPABASE_URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_ANON_KEY"]

url = f"{SUPABASE_URL}/rest/v1/player_snapshots"
headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Accept": "application/json",
    "Prefer": "count=exact",
}

page_size = 1000
offset = 0
all_players = []

while True:
    req = urllib.request.Request(
        f"{url}?select=*&season=lt.{CURRENT_SEASON}&order=id.asc&limit={page_size}&offset={offset}",
        headers=headers,
    )
    with urllib.request.urlopen(req) as resp:
        page = json.loads(resp.read())
    all_players.extend(page)
    print(f"  fetched {len(page)} rows (total {len(all_players)})")
    if len(page) < page_size:
        break
    offset += page_size

out_path = "StatScout/Data/players-historical.json"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(all_players, f)

print(f"\nSaved {len(all_players)} rows to {out_path}")
print(f"File size: {os.path.getsize(out_path) / (1024*1024):.1f} MB")

# The app ships the binary-plist version (smaller, faster decode). Regenerate it
# automatically so the JSON and the bundled plist never drift.
import subprocess
print("\nRegenerating binary plist for the iOS bundle...")
subprocess.run(["swift", "scripts/convert_historical_to_plist.swift"], check=True)
