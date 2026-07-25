-- Pre-aggregated rolling windows, one row per player per window length.
--
-- player_game_logs holds the raw per-game rows, which is the right shape for
-- one player's profile but not for ranking the league: a 30-day league-wide
-- slice is ~9,700 rows (~2.4 MB) that the client would have to pull and
-- aggregate before it could sort anything. This table is ~1,100 rows per
-- window instead, so the Stats "Recent" filter, the Hot/Cold leaderboard and
-- the leaderboard trend arrows are all a single small fetch.
--
-- Modelled on Baseball Savant's rolling leaderboard, which reports THEN / NOW
-- / delta rather than a bare current-window number: `metrics` is the window
-- ending today, `prior_metrics` the immediately preceding window of equal
-- length, and `delta` the change between them.
--
-- Metrics stay in jsonb so the metric set can evolve without a migration —
-- the same reason player_game_logs does it.

create table if not exists public.player_recent_form (
  player_id bigint not null,
  season integer not null,
  player_type text not null, -- 'batter' | 'pitcher'
  window_days integer not null, -- 7 | 15 | 30
  -- The last date included in the window. Lets the client tell a stale row
  -- (pipeline failed overnight) from a genuinely cold player.
  as_of date not null,
  team text,
  games integer not null default 0,
  plate_appearances integer not null default 0,
  batted_ball_events integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  prior_metrics jsonb not null default '{}'::jsonb,
  delta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, player_type, window_days)
);

-- Leaderboard access pattern: every qualified player for one season, one
-- window, one side of the ball.
create index if not exists player_recent_form_leaderboard_idx
  on public.player_recent_form(season, window_days, player_type);

-- Profile access pattern: all three windows for one player.
create index if not exists player_recent_form_player_idx
  on public.player_recent_form(player_id, season);

create index if not exists player_recent_form_team_idx
  on public.player_recent_form(season, window_days, team);

alter table public.player_recent_form enable row level security;

drop policy if exists "Public read player recent form" on public.player_recent_form;
create policy "Public read player recent form"
  on public.player_recent_form
  for select
  using (true);
