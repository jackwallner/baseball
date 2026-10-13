package com.jackwallner.baseball

import com.jackwallner.baseball.data.StatcastApi
import com.jackwallner.baseball.model.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/** Hits the same public RLS-protected feed as the shipped app. */
class LiveFeedTest {
    @Test fun productionFeedDecodesAndSeparatesPostseason() = runBlocking {
        assertTrue(BuildConfig.SUPABASE_URL.startsWith("https://"))
        val api = StatcastApi(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
        val players = api.fetchCurrentPlayers()
        assertTrue("Expected the current baseball roster", players.size > 500)
        assertTrue(players.all { it.season == StatScoutSeason.CURRENT })
        assertTrue(players.any { it.playerType == "pitcher" })
        assertTrue(players.any { it.matchesPlayerType(MetricCategory.HITTING) })
        assertTrue(players.flatMap { it.metrics }.all { it.percentile in 0..100 })
        val forms = api.fetchRecentForm(StatScoutSeason.CURRENT, 15)
        assertTrue("Expected rolling windows", forms.isNotEmpty())
        assertTrue(forms.all { it.windowDays == 15 && it.season == StatScoutSeason.CURRENT })
        assertNotNull(api.fetchDataThrough(StatScoutSeason.CURRENT))
        val p = players.first { it.playerType == "batter" }
        val logs = api.fetchGameLogs(p.playerId, StatScoutSeason.CURRENT, SeasonPhase.REGULAR)
        assertTrue(logs.all { it.playerId == p.playerId })
        val postseason = api.fetchPostseasonPlayers(StatScoutSeason.CURRENT)
        assertTrue(postseason.all { it.season == StatScoutSeason.CURRENT })
        if (api.fetchPostseasonThrough(StatScoutSeason.CURRENT) != null) assertTrue("Postseason coverage must have player lines", postseason.isNotEmpty())
        println("Live feed verified: ${players.size} current players, ${forms.size} rolling rows, ${postseason.size} postseason players.")
    }
}
