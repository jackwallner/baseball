-- Round the postseason stats table out to the shape the app already decodes a
-- Player from, so the existing standard-stats board can render these rows with
-- no new model and no changes to Player's decoder (where handedness, metrics
-- and games are all required keys).
--
-- metrics stays empty and is expected to: Savant publishes no postseason
-- percentile leaderboards, so an empty array here is the honest answer rather
-- than a gap waiting to be filled. It is what makes the percentile board
-- correctly render nothing for October.

alter table public.player_postseason_stats
  add column if not exists handedness text not null default '',
  add column if not exists image_url text,
  add column if not exists metrics jsonb not null default '[]'::jsonb,
  add column if not exists games jsonb not null default '[]'::jsonb,
  add column if not exists source text not null default 'mlb_stats_api_postseason';
