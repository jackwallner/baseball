package com.jackwallner.baseball.data

import com.jackwallner.baseball.model.*
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

class DataFormatException(message: String) : IOException(message)

interface StatcastProviding {
    suspend fun fetchCurrentPlayers(): List<Player>
    suspend fun fetchHistoricalPlayers(): List<Player>
    suspend fun fetchPostseasonPlayers(season: Int): List<Player>
    suspend fun fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase): List<PlayerGameLog>
    suspend fun fetchTeamGameLogs(team: String, season: Int, since: Instant, phase: SeasonPhase): List<PlayerGameLog>
    suspend fun fetchRecentForm(season: Int, days: Int): List<RecentForm>
    suspend fun fetchDataThrough(season: Int): Instant?
    suspend fun fetchPostseasonThrough(season: Int): Instant?
}

/** Mirrors the iOS PostgREST queries, including the separate postseason tables. */
class StatcastApi(private val baseUrl: String, private val apiKey: String) : StatcastProviding {
    override suspend fun fetchCurrentPlayers() = players("player_snapshots", "eq.${StatScoutSeason.CURRENT}")
    override suspend fun fetchHistoricalPlayers() = players("player_snapshots", "lt.${StatScoutSeason.CURRENT}")
    override suspend fun fetchPostseasonPlayers(season: Int) = players("player_postseason_stats", "eq.$season")

    private suspend fun players(table: String, season: String): List<Player> = withContext(Dispatchers.Default) {
        paged(table, listOf("season" to season), "id.asc").decodeRows(Player::fromJson)
    }

    override suspend fun fetchGameLogs(playerId: Int, season: Int, phase: SeasonPhase): List<PlayerGameLog> =
        paged(phase.logTable, listOf("player_id" to "eq.$playerId", "season" to "eq.$season"), "game_date.desc").decodeRows(PlayerGameLog::fromJson)

    override suspend fun fetchTeamGameLogs(team: String, season: Int, since: Instant, phase: SeasonPhase): List<PlayerGameLog> =
        paged(phase.logTable, listOf("team" to "in.(${gameLogTeamCodes(team).joinToString(",")})", "season" to "eq.$season", "game_date" to "gte.${DateTimeFormatter.ISO_LOCAL_DATE.format(since.atZone(EASTERN))}"), "game_date.desc,player_id.asc,player_type.asc").decodeRows(PlayerGameLog::fromJson)

    override suspend fun fetchRecentForm(season: Int, days: Int) = paged("player_recent_form", listOf("season" to "eq.$season", "window_days" to "eq.$days"), "player_id.asc").decodeRows(RecentForm::fromJson)
    override suspend fun fetchDataThrough(season: Int) = through("player_recent_form", "as_of", season)
    override suspend fun fetchPostseasonThrough(season: Int) = through("player_postseason_game_logs", "game_date", season)

    private suspend fun through(table: String, column: String, season: Int): Instant? {
        val row = get(table, listOf("select" to column, "season" to "eq.$season", "order" to "$column.desc", "limit" to "1")).firstOrNull() as? JsonObject
        return row?.string(column)?.let(::parseDay)
    }

    private suspend fun paged(table: String, filters: List<Pair<String, String>>, order: String): JsonArray {
        val result = mutableListOf<JsonElement>()
        var offset = 0
        while (true) {
            val page = get(table, listOf("select" to "*", "order" to order, "limit" to "1000", "offset" to offset.toString()) + filters)
            result.addAll(page)
            if (page.size < 1000) return JsonArray(result)
            offset += 1000
        }
    }

    internal suspend fun get(table: String, parameters: List<Pair<String, String>>): JsonArray = withContext(Dispatchers.IO) {
        val query = parameters.joinToString("&") { (k, v) -> "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}" }
        val connection = URL("${baseUrl.trimEnd('/')}/rest/v1/$table?$query").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 20_000
            connection.readTimeout = 45_000
            connection.useCaches = false
            connection.setRequestProperty("apikey", apiKey)
            connection.setRequestProperty("Authorization", "Bearer $apiKey")
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode !in 200..299) throw IOException("Data service returned ${connection.responseCode}")
            val payload = connection.inputStream.bufferedReader().use { it.readText() }
            Json.parseToJsonElement(payload) as? JsonArray ?: throw DataFormatException("Expected an array of rows")
        } finally { connection.disconnect() }
    }
}

internal fun <T> JsonArray.decodeRows(decode: (JsonObject) -> T): List<T> {
    val decoded = lenientList(decode)
    if (isNotEmpty() && decoded.isEmpty()) throw DataFormatException("The data format changed. Please try again later.")
    return decoded
}
