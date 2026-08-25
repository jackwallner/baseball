-- Postseason and spring-training pitch data arrive through exactly the same
-- pull as the regular season. pybaseball 2.2.7's statcast() hardcodes
-- hfGT=R|PO|S in its request, so a plain date-range fetch returns all three
-- and nothing downstream told them apart.
--
-- A postseason game is just a new game_date, so those rows upsert cleanly and
-- invisibly against the (player_id, season, game_date, player_type) key. The
-- effect, from the first Wild Card game on, is that every club still playing
-- has its Recent Form and Trends windows quietly become postseason-only while
-- still reading "Regular Season". The iOS app reads player_game_logs directly
-- and applies no game_type filter of its own, so the only thing standing
-- between a shipped build and that mix-up is what the ingest chooses to write.
--
-- game_type carries Statcast's own code: R regular season, S spring training,
-- and the postseason rounds F (wild card), D (division), L (championship),
-- W (world series).
--
-- Existing rows default to 'R'. That is right for everything from Opening Day
-- on. A handful of late-March 2026 rows may actually be spring training, since
-- SEASON_START (Mar 20) predates Opening Day and the S code was never
-- excluded; re-ingest that window with --full once this is deployed to correct
-- them.

alter table public.player_game_logs
  add column if not exists game_type text not null default 'R';

-- The rollup and any future phase-aware board slice on exactly this.
create index if not exists player_game_logs_season_type_date_idx
  on public.player_game_logs(season, game_type, game_date desc);
