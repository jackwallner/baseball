# Backend ingestion

The backend is intentionally serverless/free-tier friendly. A scheduled GitHub Actions workflow runs `backend/ingest.py`, pulls Baseball Savant Statcast percentile rankings through `pybaseball`, and upserts mobile-ready player snapshots into Supabase Postgres.

## Local setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
cp backend/.env.example backend/.env
```

Fill in `backend/.env`, then run:

```bash
python backend/ingest.py
```

## Data contract

The iOS app reads rows from `player_snapshots` using Supabase REST. Each row contains:

- `id`: MLBAM player id
- `name`
- `team`
- `position`
- `handedness`
- `image_url`
- `updated_at`
- `metrics`: JSON array of percentile metrics
- `games`: JSON array of recent game notes

## MVP Statcast integration

The MVP uses `statcast_batter_percentile_ranks` and `statcast_pitcher_percentile_ranks` from `pybaseball`. These functions read Baseball Savant percentile leaderboard exports and produce the same kind of red/blue percentile-bar data users see on Baseball Savant player pages.

The app stores one current `player_snapshots` row per MLBAM player. Each row contains app-ready metric JSON so the iOS player page can load quickly without making a user's phone compute raw Statcast percentiles.
