-- Postseason game logs live in their own table, and that separation is load
-- bearing rather than tidy-minded.
--
-- The shipped app (1.4.3, and 1.4.4 whenever it goes out) queries
-- player_game_logs directly with select=* and no game_type filter of its own.
-- Any postseason row placed in that table is therefore visible to a build
-- already in users' hands, which is the exact mix-up
-- 20260825000000_add_game_type_to_game_logs.sql exists to prevent: a playoff
-- club's newest games are its playoff games, so a phase-blind "last 7 days"
-- in October is entirely postseason under a regular-season heading.
--
-- Keeping the rows in a separate relation makes that impossible by
-- construction rather than by a flag someone has to remember not to flip. A
-- legacy build cannot see a table it has never heard of, so the pipeline can
-- start collecting the postseason immediately and the phase-aware release can
-- take its time.
--
-- Shape mirrors player_game_logs exactly so the aggregators write to either
-- without knowing which. game_type carries the round: F wild card, D division
-- series, L league championship, W world series.

create table if not exists public.player_postseason_game_logs (
  player_id bigint not null,
  season integer not null,
  game_date date not null,
  player_type text not null, -- 'batter' | 'pitcher'
  game_type text not null,
  team text,
  opponent text,
  plate_appearances integer not null default 0,
  batted_ball_events integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, game_date, player_type)
);

create index if not exists player_postseason_game_logs_player_season_idx
  on public.player_postseason_game_logs(player_id, season);
create index if not exists player_postseason_game_logs_date_idx
  on public.player_postseason_game_logs(game_date desc);
create index if not exists player_postseason_game_logs_season_date_idx
  on public.player_postseason_game_logs(season, game_date desc);

alter table public.player_postseason_game_logs enable row level security;

drop policy if exists "Public read player postseason game logs"
  on public.player_postseason_game_logs;
create policy "Public read player postseason game logs"
  on public.player_postseason_game_logs
  for select
  using (true);
