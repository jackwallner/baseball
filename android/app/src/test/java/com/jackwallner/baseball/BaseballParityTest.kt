package com.jackwallner.baseball

import com.jackwallner.baseball.data.*
import com.jackwallner.baseball.model.*
import java.io.File
import java.time.Instant
import java.util.zip.GZIPInputStream
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class BaseballParityTest {
    private fun metric(category: MetricCategory, percentile: Int, label: String = "xwOBA") = Metric("${category.raw}-$label", label, ".330", percentile, category)
    private fun player(id: Int = 1, type: String = "batter", team: String = "NYY", metrics: List<Metric> = listOf(metric(MetricCategory.HITTING, 90)), stats: List<StandardStat> = emptyList()) = Player(id, "Bobby Witt Jr.", team, "TBD", "R/R", Instant.parse("2026-10-10T12:00:00Z"), 2026, type, "baseball_savant", metrics, stats)
    private fun stat(label: String, value: String, category: MetricCategory = MetricCategory.HITTING) = StandardStat(label, label, value, category)

    @Test fun overallBalancesCategoriesRatherThanCountingEveryMetric() {
        val p = player(metrics = listOf(metric(MetricCategory.HITTING, 100), metric(MetricCategory.HITTING, 100, "xBA"), metric(MetricCategory.FIELDING, 0)))
        assertEquals(50, p.overallPercentile)
    }
    @Test fun twoWayTakesBestSide() {
        assertEquals(95, player(type = "two_way", metrics = listOf(metric(MetricCategory.HITTING, 95), metric(MetricCategory.PITCHING, 30))).overallPercentile)
    }
    @Test fun suffixesAndMissingPositionsMatchIOS() {
        assertEquals("BW", player().initials)
        assertEquals("DH", player().displayPosition)
        assertEquals("P", player(type = "pitcher").displayPosition)
        assertEquals("TWP", player(type = "two_way").displayPosition)
    }
    @Test fun baseballRatesDropOnlyThreePlaceLeadingZero() {
        assertEquals(".282", BaseballNumberStyle.display("0.282"))
        assertEquals("0.85", BaseballNumberStyle.display("0.85"))
        assertEquals("1.000", BaseballNumberStyle.display("1.000"))
        assertEquals("0.1234", BaseballNumberStyle.display("0.1234"))
    }
    @Test fun twoWayStatsRetainTheirSideAndLegacyInference() {
        val p = player(type = "two_way", stats = listOf(stat("H", "100"), stat("H", "25", MetricCategory.PITCHING)))
        assertEquals("100", p.stat("H", MetricCategory.HITTING)?.value)
        assertEquals("25", p.stat("H", MetricCategory.PITCHING)?.value)
        assertEquals(MetricCategory.PITCHING, StandardStat("era", "ERA", "2.00", null).resolvedCategory("two_way"))
    }
    @Test fun pitchersNeverLeakIntoHittingBoards() {
        assertFalse(player(type = "pitcher").matchesPlayerType(MetricCategory.HITTING))
        assertTrue(player(type = "two_way").matchesPlayerType(MetricCategory.HITTING))
        assertTrue(player(type = "two_way").matchesPlayerType(MetricCategory.PITCHING))
        assertFalse(player().matchesPlayerType(MetricCategory.PITCHING))
    }
    @Test fun postseasonCameosFailAndThresholdRoundsLikeMLB() {
        val regular = player(stats = listOf(stat("G", "6"), stat("PA", "19")))
        val short = player(2, stats = listOf(stat("G", "6"), stat("PA", "18")))
        val cameo = player(3, stats = listOf(stat("G", "1"), stat("PA", "1")))
        val q = PostseasonQualifier(listOf(regular, short, cameo))
        assertTrue(q.qualifies(regular, MetricCategory.HITTING))
        assertFalse(q.qualifies(short, MetricCategory.HITTING))
        assertFalse(q.qualifies(cameo, MetricCategory.HITTING))
    }
    @Test fun inningsUseOutsAndPitcherAppearancesNeverSetTeamGames() {
        val hitter = player(stats = listOf(stat("G", "2"), stat("PA", "8")))
        val starter = player(2, "pitcher", stats = listOf(stat("G", "9", MetricCategory.PITCHING), stat("IP", "2.0", MetricCategory.PITCHING)))
        val opener = player(3, "pitcher", stats = listOf(stat("IP", "1.2", MetricCategory.PITCHING)))
        val q = PostseasonQualifier(listOf(hitter, starter, opener))
        assertEquals(2.0, q.teamGames["NYY"]!!, 0.0001)
        assertTrue(q.qualifies(starter, MetricCategory.PITCHING))
        assertFalse(q.qualifies(opener, MetricCategory.PITCHING))
        assertEquals(4 + 2.0 / 3, PostseasonQualifier.innings(4.2), 0.0001)
    }
    @Test fun teamAliasesIncludeGameLogSpellingsAndNicknames() {
        assertEquals("ARI", normalizedTeamAbbreviation("AZ"))
        assertEquals("OAK", normalizedTeamAbbreviation("ATH"))
        assertEquals(setOf("OAK", "ATH"), gameLogTeamCodes("OAK").toSet())
        assertTrue(teamMatchesQuery("NYY", "yankees"))
        assertTrue(teamMatchesQuery("CWS", "white sox"))
    }
    @Test fun nullRecentMetricsStayMissingAndQualifiersScaleByWindow() {
        val form = RecentForm.fromJson(Json.parseToJsonElement("""{"player_id":1,"season":2026,"player_type":"batter","window_days":30,"plate_appearances":15,"metrics":{"xwoba":null,"ev_avg":95.0},"prior_metrics":{},"delta":{}}""") as JsonObject)
        assertFalse(form.metrics.containsKey("xwoba"))
        assertEquals(95.0, form.metrics["ev_avg"]!!, 0.001)
        assertFalse(TrendQualifier.REGULARS.admits(form))
        assertEquals(18, TrendQualifier.REGULARS.minimum(false, 7))
        assertEquals(120, TrendQualifier.REGULARS.minimum(true, 30))
    }
    @Test fun windowUsesCorrectWeightsAndPeakEVAndDistinctDates() {
        val day = Instant.parse("2026-10-10T04:00:00Z")
        val logs = listOf(
            PlayerGameLog(1,2026,day,"batter","NYY","BOS",10,2,mapOf("xwoba" to 0.4,"ev_avg" to 100.0,"ev_max" to 110.0)),
            PlayerGameLog(2,2026,day,"batter","NYY","BOS",2,8,mapOf("xwoba" to 0.2,"ev_avg" to 80.0,"ev_max" to 105.0)),
        )
        val w = RecentFormWindow.build(logs)
        assertEquals(1, w.games)
        assertEquals(0.3666667, w.metrics["xwoba"]!!, 0.00001)
        assertEquals(84.0, w.metrics["ev_avg"]!!, 0.0001)
        assertEquals(110.0, w.metrics["ev_max"]!!, 0.0001)
    }
    @Test fun historyDecodesEveryIOSRowWithoutLosingCategories() {
        val asset = File("src/main/assets/players-historical.bin")
        val players = GZIPInputStream(asset.inputStream()).use(::decodeHistoricalPlayers)
        assertEquals(14032, players.size)
        assertEquals((2015..2025).toSet(), players.mapNotNull { it.season }.toSet())
        assertEquals(players.size, players.map { it.id }.distinct().size)
        assertTrue(players.any { it.playerType == "two_way" })
        assertEquals(MetricCategory.entries.toSet(), players.flatMap { it.metrics }.map { it.category }.toSet())
    }
    @Test fun cacheRoundTripPreservesTwoWayCategoriesAndGames() {
        val original = player(type = "two_way", stats = listOf(stat("H", "100"), stat("H", "20", MetricCategory.PITCHING))).copy(games = listOf(GameTrend(Instant.parse("2026-10-10T00:00:00Z"),"BOS","2 hits",3)))
        val decoded = Player.fromJson((Json.parseToJsonElement(encodePlayers(listOf(original))) as JsonArray).first() as JsonObject)
        assertEquals(original, decoded)
    }
    @Test fun regularAndPostseasonNeverUseTheSameTable() {
        assertEquals("player_game_logs", SeasonPhase.REGULAR.logTable)
        assertEquals("player_postseason_game_logs", SeasonPhase.POSTSEASON.logTable)
        assertNotEquals(SeasonPhase.REGULAR.logTable, SeasonPhase.POSTSEASON.logTable)
    }
    @Test fun teamERARecomputesFromOutsInsteadOfAveragingPitchers() {
        val a = player(1,"pitcher",stats = listOf(stat("IP","1.2",MetricCategory.PITCHING),stat("ER","1",MetricCategory.PITCHING)))
        val b = player(2,"pitcher",stats = listOf(stat("IP","2.1",MetricCategory.PITCHING),stat("ER","3",MetricCategory.PITCHING)))
        val totals = aggregateTeamStats(listOf(a,b),MetricCategory.PITCHING)
        assertEquals("4.0",totals["IP"])
        assertEquals("9.00",totals["ERA"])
    }
    @Test fun teamOnBaseRatesUsePlateAppearancesWhenHitByPitchAndSacrificeFliesAreMissing() {
        val regular = player(stats = listOf(stat("PA", "600"), stat("OBP", ".350"), stat("OPS", ".850")))
        val callUp = player(id = 2, stats = listOf(stat("PA", "20"), stat("OBP", ".500"), stat("OPS", "1.000")))
        val totals = aggregateTeamStats(listOf(regular, callUp), MetricCategory.HITTING)
        assertEquals(".355", totals["OBP"])
        assertEquals(".855", totals["OPS"])
    }

    @Test fun pendingAndCancelledNeverBecomePurchased() {
        assertEquals(PurchaseOutcome.PENDING, purchaseOutcome(com.revenuecat.purchases.PurchasesErrorCode.PaymentPendingError,false))
        assertEquals(PurchaseOutcome.CANCELLED, purchaseOutcome(com.revenuecat.purchases.PurchasesErrorCode.PurchaseCancelledError,false))
    }
}
