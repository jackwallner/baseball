-- Postseason standard stat lines, keyed like player_snapshots but kept out of
-- it for the same reason the postseason game logs are kept out of
-- player_game_logs: the shipped app reads player_snapshots directly, filtered
-- only by season, so an October row placed there would appear on a
-- regular-season leaderboard in a build nobody can patch.
--
-- Standard stats are written first. A later nightly step adds Statcast metrics
-- mapped onto the current regular-season percentile curves, because Baseball
-- Savant publishes no postseason percentile leaderboards.

create table if not exists public.player_postseason_stats (
  id bigint not null,
  season integer not null,
  name text not null default '',
  team text not null default 'TBD',
  position text not null default '',
  player_type text not null default 'unknown',
  standard_stats jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (id, season)
);

create index if not exists player_postseason_stats_season_idx
  on public.player_postseason_stats(season);
create index if not exists player_postseason_stats_team_idx
  on public.player_postseason_stats(team);

alter table public.player_postseason_stats enable row level security;

drop policy if exists "Public read player postseason stats"
  on public.player_postseason_stats;
create policy "Public read player postseason stats"
  on public.player_postseason_stats
  for select
  using (true);
