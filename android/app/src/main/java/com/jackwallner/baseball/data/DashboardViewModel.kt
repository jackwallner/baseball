package com.jackwallner.baseball.data

import android.content.Context
import androidx.compose.runtime.*
import com.jackwallner.baseball.model.*
import java.io.File
import java.time.Instant
import java.util.zip.GZIPInputStream
import kotlinx.coroutines.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray

/** Current and historical loads merge on the main thread whichever finishes first. */
class DashboardViewModel(private val context: Context, val provider: StatcastProviding, private val scope: CoroutineScope) {
    var players by mutableStateOf<List<Player>>(emptyList())
        private set
    var postseasonPlayers by mutableStateOf<List<Player>>(emptyList())
        private set
    var loading by mutableStateOf(false)
        private set
    var historyLoading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var historyError by mutableStateOf<String?>(null)
        private set
    var postseasonError by mutableStateOf<String?>(null)
        private set
    var dataThrough by mutableStateOf<Instant?>(null)
        private set
    var postseasonThrough by mutableStateOf<Instant?>(null)
        private set
    var selectedSeason by mutableIntStateOf(StatScoutSeason.CURRENT)
    var selectedPhase by mutableStateOf(SeasonPhase.REGULAR)
    private val currentCache get() = File(context.cacheDir, "players-current.json")
    private var started = false
    private var refreshJob: Job? = null
    val seasonPlayers: List<Player> get() = if (selectedPhase == SeasonPhase.POSTSEASON) postseasonPlayers.filter { it.season == selectedSeason } else players.filter { it.season == selectedSeason }
    val seasons: List<Int> get() = (StatScoutSeason.EARLIEST..StatScoutSeason.CURRENT).reversed().toList()

    fun start() {
        if (started) return
        started = true
        refreshJob = scope.launch {
            withContext(Dispatchers.IO) { runCatching { currentCache.readText().let { (Json.parseToJsonElement(it) as JsonArray).decodeRows(Player::fromJson) } }.getOrNull() }?.let(::merge)
            refreshNow()
            loadHistory()
        }
    }

    private fun merge(incoming: List<Player>) { players = (players + incoming).associateBy { it.id }.values.toList() }

    fun refresh() {
        if (refreshJob?.isActive == true) return
        refreshJob = scope.launch { refreshNow() }
    }

    private suspend fun refreshNow() = supervisorScope {
        loading = true
        error = null
        val live = async {
            try {
                val current = provider.fetchCurrentPlayers()
                players = players.filter { (it.season ?: 0) != StatScoutSeason.CURRENT } + current
                // Keep the full server payload so refreshes do not lose fields.
                val api = provider as? StatcastApi
                if (api != null) writeCurrentCache(current)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { error = if (players.isEmpty()) "Couldn't load players. Check your connection and try again." else "Showing saved data. Pull the latest data when you're online." }
        }
        val coverage = async { runCatching { provider.fetchDataThrough(StatScoutSeason.CURRENT) }.getOrNull()?.let { dataThrough = it } }
        val postseason = async {
            try {
                postseasonThrough = provider.fetchPostseasonThrough(StatScoutSeason.CURRENT)
                if (postseasonThrough != null) postseasonPlayers = provider.fetchPostseasonPlayers(StatScoutSeason.CURRENT)
                postseasonError = null
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { postseasonError = "Couldn't load postseason data. Try again." }
        }
        try { awaitAll(live, coverage, postseason) } finally { loading = false }
    }

    private suspend fun writeCurrentCache(current: List<Player>) = withContext(Dispatchers.IO) {
        runCatching {
            val text = encodePlayers(current)
            val staging = File(context.cacheDir, "players-current.tmp")
            staging.writeText(text)
            staging.renameTo(currentCache)
        }
        Unit
    }

    fun loadHistory() {
        if (historyLoading) return
        scope.launch {
            historyLoading = true
            historyError = null
            try {
                val history = withContext(Dispatchers.IO) {
                    context.assets.open("players-historical.bin").use { input ->
                        GZIPInputStream(input).use(::decodeHistoricalPlayers)
                    }
                }
                merge(history.filter { (it.season ?: 0) < StatScoutSeason.CURRENT })
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) {
                try { merge(provider.fetchHistoricalPlayers()) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { historyError = "Couldn't load past seasons. Try again." }
            } finally { historyLoading = false }
        }
    }

    fun qualified(player: Player, category: MetricCategory, level: String): Boolean = when (level) {
        "All" -> true
        "Min Sample" -> if (category == MetricCategory.PITCHING) PostseasonQualifier.innings(player.stat("IP", category)?.value?.toDoubleOrNull() ?: 0.0) >= 5
            else (player.stat("PA", MetricCategory.HITTING)?.value?.toDoubleOrNull() ?: player.stat("AB", MetricCategory.HITTING)?.value?.toDoubleOrNull() ?: 0.0) >= 10
        else -> if (selectedPhase == SeasonPhase.POSTSEASON) PostseasonQualifier(seasonPlayers).qualifies(player, category) else player.metrics.any { it.category == category }
    }
}
