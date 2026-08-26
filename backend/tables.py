"""Table names and phase codes shared across the pipeline scripts.

Its own module, with no third-party imports, so the cheap scripts (the refresh
guard, the freshness check) can name a table without dragging pandas and
pybaseball in behind it.

The regular season and the postseason are stored separately on purpose. A
shipped app queries the regular-season table directly with no phase filter of
its own, so a playoff row placed there lands inside a regular-season "last 7
days" on a build nobody can patch. Anything that asks "what is the newest game
we hold?" has to consult both; anything that asks "what does the regular-season
board show?" must consult only the first.
"""

REGULAR_SEASON_TABLE = "player_game_logs"
POSTSEASON_TABLE = "player_postseason_game_logs"
GAME_LOG_TABLES = (REGULAR_SEASON_TABLE, POSTSEASON_TABLE)

# Statcast's own codes.
REGULAR_SEASON = "R"
SPRING_TRAINING = "S"
POSTSEASON_TYPES = ("F", "D", "L", "W")
