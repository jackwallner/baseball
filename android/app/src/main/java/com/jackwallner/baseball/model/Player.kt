package com.jackwallner.baseball.model

import java.time.Instant
import kotlin.math.roundToInt
import kotlinx.serialization.json.JsonObject

enum class MetricCategory(val raw: String) {
    HITTING("Hitting"), PITCHING("Pitching"), FIELDING("Fielding"), RUNNING("Running");
    val metricPriorityOrder: List<String> get() = when (this) {
        HITTING -> listOf("xwOBA", "xBA", "xSLG", "xISO", "xOBP", "K%", "BB%", "Whiff%", "Chase%", "Barrel%", "Hard-Hit%", "EV", "Max EV", "Squared-Up%", "Bat Speed", "Swing Length")
        PITCHING -> listOf("xwOBA", "xERA", "xBA", "xSLG", "xISO", "xOBP", "K%", "BB%", "Whiff%", "Chase%", "Barrel%", "Hard-Hit%", "Avg EV Against", "Max EV Against", "Fastball Velo", "Fastball Spin", "Curve Spin")
        FIELDING -> listOf("Range (OAA)", "Arm Strength", "Arm Value", "Jump", "Burst")
        RUNNING -> listOf("Sprint Speed", "Bolts", "Acceleration")
    }
    companion object { fun from(raw: String) = entries.firstOrNull { it.raw.equals(raw, true) } }
}

enum class SeasonPhase(val raw: String, val label: String, val logTable: String) {
    REGULAR("R", "Regular Season", "player_game_logs"),
    POSTSEASON("P", "Postseason", "player_postseason_game_logs")
}

object StatScoutSeason {
    const val CURRENT = 2026
    const val EARLIEST = 2015
    val current get() = CURRENT
}

object BaseballNumberStyle {
    private val threeDecimalRate = Regex("0\\.\\d{3}")
    fun display(raw: String) = if (threeDecimalRate.matches(raw)) raw.drop(1) else raw
}

data class Metric(val id: String, val label: String, val value: String, val percentile: Int, val category: MetricCategory) {
    companion object {
        fun fromJson(o: JsonObject): Metric {
            val category = MetricCategory.from(o.requireString("category")) ?: throw RowDecodeException("bad category")
            val label = o.requireString("label")
            return Metric(o.string("id") ?: "${category.raw}-$label", label, BaseballNumberStyle.display(o.requireString("value")), o.requireInt("percentile"), category)
        }
    }
}

data class StandardStat(val id: String, val label: String, val value: String, val category: MetricCategory?) {
    fun resolvedCategory(playerType: String?): MetricCategory = category ?: when {
        label in setOf("ERA", "WHIP", "W", "L", "SV", "IP", "ER", "K/9", "BB/9", "K/BB", "QS", "GS", "BF") -> MetricCategory.PITCHING
        label in setOf("E", "A", "PO", "DP", "FLD%", "GF") -> MetricCategory.FIELDING
        playerType == "pitcher" -> MetricCategory.PITCHING
        else -> MetricCategory.HITTING
    }
    companion object {
        fun fromJson(o: JsonObject) = StandardStat(o.string("id") ?: o.requireString("label"), o.requireString("label"), BaseballNumberStyle.display(o.requireString("value")), o.string("category")?.let(MetricCategory::from))
    }
}

data class GameTrend(val date: Instant, val opponent: String, val summary: String, val percentileDelta: Int)

data class Player(
    val playerId: Int, val name: String, val team: String, val position: String,
    val handedness: String, val updatedAt: Instant, val season: Int?,
    val playerType: String?, val source: String?, val metrics: List<Metric>,
    val standardStats: List<StandardStat>?, val games: List<GameTrend> = emptyList(),
    val imageUrl: String? = null,
) {
    val id get() = "$playerId-${season ?: 0}"
    val overallPercentile: Int get() {
        val groups = metrics.groupBy { it.category }.values.map { group -> group.map { it.percentile }.average() }
        if (groups.isEmpty()) return 0
        return (if (playerType == "two_way") groups.max() else groups.average()).roundToInt()
    }
    val headlineMetric get() = metrics.maxByOrNull { it.percentile }
    fun percentile(category: MetricCategory): Int? = metrics.filter { it.category == category }.takeIf { it.isNotEmpty() }?.map { it.percentile }?.average()?.roundToInt()
    fun matchesPlayerType(category: MetricCategory?): Boolean = when (category) {
        MetricCategory.HITTING -> playerType?.lowercase() != "pitcher"
        MetricCategory.PITCHING -> playerType?.lowercase() in setOf("pitcher", "two_way")
        else -> true
    }
    fun stat(label: String, category: MetricCategory): StandardStat? = standardStats?.firstOrNull { it.label == label && it.resolvedCategory(playerType) == category }
    val displayPosition: String get() = when (position.trim().uppercase()) {
        "PITCHER" -> "P"
        "", "TBD", "-", "\u2014" -> when (playerType) { "pitcher" -> "P"; "two_way" -> "TWP"; "hitter", "batter" -> "DH"; else -> position }
        else -> position
    }
    val initials: String get() {
        val parts = name.split(" ").filter { it.isNotBlank() }
        val last = parts.lastOrNull { it.trim('.', ',').uppercase() !in setOf("JR", "SR", "II", "III", "IV", "V") }
        return (parts.firstOrNull()?.take(1) ?: "") + (if (parts.size > 1) last?.take(1) ?: "" else "")
    }
    val shareSummary get() = "$name · $team $displayPosition\nOverall: ${overallPercentile.ordinal} percentile\nTop stat: ${headlineMetric?.let { "${it.label} ${it.value}, ${it.percentile.ordinal} percentile" } ?: "Unavailable"}\nStatScout"
    companion object {
        fun fromJson(o: JsonObject) = Player(
            o.requireInt("id"), o.requireString("name"), o.requireString("team"), o.requireString("position"), o.requireString("handedness"),
            parseDate(o.requireString("updated_at")) ?: throw RowDecodeException("bad updated_at"), o.int("season"), o.string("player_type"), o.string("source"),
            (o.array("metrics") ?: throw RowDecodeException("missing metrics")).map { Metric.fromJson(it as? JsonObject ?: throw RowDecodeException("bad metric")) },
            o.array("standard_stats")?.map { StandardStat.fromJson(it as? JsonObject ?: throw RowDecodeException("bad stat")) },
            o.array("games")?.mapNotNull { item -> (item as? JsonObject)?.let { g -> parseDate(g.requireString("date"))?.let { GameTrend(it, g.requireString("opponent"), g.requireString("summary"), g.requireInt("percentile_delta")) } } }.orEmpty(),
            o.string("image_url"),
        )
    }
}

class PostseasonQualifier(players: List<Player>) {
    val teamGames = players.filter { it.playerType != "pitcher" }.groupBy { normalizedTeamAbbreviation(it.team) }
        .mapValues { (_, roster) -> roster.mapNotNull { it.stat("G", MetricCategory.HITTING)?.value?.toDoubleOrNull() }.maxOrNull() ?: 0.0 }
    fun qualifies(player: Player, category: MetricCategory): Boolean {
        val games = teamGames[normalizedTeamAbbreviation(player.team)]?.takeIf { it > 0 } ?: return false
        return if (category == MetricCategory.PITCHING) innings(player.stat("IP", category)?.value?.toDoubleOrNull() ?: 0.0) >= games
        else (player.stat("PA", MetricCategory.HITTING)?.value?.toDoubleOrNull() ?: 0.0) >= (games * 3.1).roundToInt()
    }
    companion object {
        fun innings(boxScore: Double): Double { val whole = boxScore.toInt(); return whole + ((boxScore - whole) * 10).roundToInt() / 3.0 }
    }
}

val Int.ordinal: String get() = "$this${if (this % 100 in 11..13) "th" else when (this % 10) { 1 -> "st"; 2 -> "nd"; 3 -> "rd"; else -> "th" }}"
