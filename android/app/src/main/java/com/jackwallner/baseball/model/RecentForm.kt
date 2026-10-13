package com.jackwallner.baseball.model

import java.time.Instant
import java.util.Locale
import kotlinx.serialization.json.JsonObject

data class RecentForm(
    val playerId: Int, val season: Int, val playerType: String, val windowDays: Int,
    val asOf: Instant?, val team: String?, val games: Int, val plateAppearances: Int,
    val battedBallEvents: Int, val metrics: Map<String, Double>, val priorMetrics: Map<String, Double>, val delta: Map<String, Double>,
) {
    val isSmallSample get() = plateAppearances < if (playerType == "pitcher") 30 else 15
    companion object {
        fun fromJson(o: JsonObject) = RecentForm(o.requireInt("player_id"), o.requireInt("season"), o.requireString("player_type"), o.requireInt("window_days"), o.string("as_of")?.let(::parseDay), o.string("team"), o.int("games") ?: 0, o.int("plate_appearances") ?: 0, o.int("batted_ball_events") ?: 0, o.numberMap("metrics"), o.numberMap("prior_metrics"), o.numberMap("delta"))
    }
}

data class PlayerGameLog(
    val playerId: Int, val season: Int, val gameDate: Instant, val playerType: String,
    val team: String?, val opponent: String?, val plateAppearances: Int, val battedBallEvents: Int, val metrics: Map<String, Double>,
) {
    companion object {
        fun fromJson(o: JsonObject) = PlayerGameLog(o.requireInt("player_id"), o.requireInt("season"), parseDay(o.requireString("game_date")) ?: throw RowDecodeException("bad game_date"), o.requireString("player_type"), o.string("team"), o.string("opponent"), o.requireInt("plate_appearances"), o.requireInt("batted_ball_events"), o.numberMap("metrics"))
    }
}

data class RecentFormWindow(val games: Int, val plateAppearances: Int, val battedBallEvents: Int, val metrics: Map<String, Double>) {
    companion object {
        private val bbeKeys = setOf("ev_avg", "ev_max", "hardhit_pct", "barrel_pct", "opp_ev_avg", "opp_hardhit_pct", "opp_barrel_pct")
        fun build(logs: List<PlayerGameLog>): RecentFormWindow {
            val combined = mutableMapOf<String, Double>()
            for (key in logs.flatMap { it.metrics.keys }.toSet()) {
                val values = logs.mapNotNull { log -> log.metrics[key]?.let { it to if (key in bbeKeys) log.battedBallEvents else log.plateAppearances } }.filter { it.second > 0 }
                if (values.isNotEmpty()) combined[key] = values.sumOf { it.first * it.second } / values.sumOf { it.second }
            }
            for (key in listOf("ev_max", "opp_ev_max")) logs.mapNotNull { it.metrics[key] }.maxOrNull()?.let { combined[key] = it }
            return RecentFormWindow(logs.map { it.gameDate }.distinct().size, logs.sumOf { it.plateAppearances }, logs.sumOf { it.battedBallEvents }, combined)
        }
    }
}

enum class TrendQualifier(val label: String, private val battingRate: Double, private val pitchingRate: Double) {
    ALL("All", 0.0, 0.0), SAMPLE("Min Sample", 1.0, 2.0), REGULARS("Regulars", 2.5, 4.0);
    fun minimum(pitcher: Boolean, days: Int) = Math.floor((if (pitcher) pitchingRate else battingRate) * days + 0.5).toInt()
    fun admits(form: RecentForm) = form.plateAppearances >= minimum(form.playerType == "pitcher", form.windowDays)
}

data class TrendMetric(val key: String, val label: String, val unit: String, val decimals: Int, val lowerIsBetter: Boolean) {
    fun format(value: Double): String {
        val text = String.format(Locale.US, "%.${decimals}f", value)
        return (if (decimals == 3) text.replace("0.", ".") else text) + unit
    }
    companion object {
        val batting = listOf(
            TrendMetric("xwoba", "xwOBA", "", 3, false), TrendMetric("xba", "xBA", "", 3, false), TrendMetric("xslg", "xSLG", "", 3, false), TrendMetric("xiso", "xISO", "", 3, false),
            TrendMetric("barrel_pct", "Barrel%", "%", 1, false), TrendMetric("hardhit_pct", "Hard-Hit%", "%", 1, false), TrendMetric("sweetspot_pct", "Sweet-Spot%", "%", 1, false),
            TrendMetric("ev_avg", "Exit Velo", " mph", 1, false), TrendMetric("bat_speed", "Bat Speed", " mph", 1, false), TrendMetric("bb_pct", "BB%", "%", 1, false),
            TrendMetric("k_pct", "K%", "%", 1, true), TrendMetric("whiff_pct", "Whiff%", "%", 1, true), TrendMetric("chase_pct", "Chase%", "%", 1, true),
        ) + listOf("avg", "obp", "slg", "ops").map { TrendMetric(it, it.uppercase(), "", 3, false) }
        val pitching = listOf(
            TrendMetric("opp_xwoba", "xwOBA Against", "", 3, true), TrendMetric("opp_xba", "xBA Against", "", 3, true), TrendMetric("opp_xslg", "xSLG Against", "", 3, true),
            TrendMetric("k_pct", "K%", "%", 1, false), TrendMetric("whiff_pct", "Whiff%", "%", 1, false), TrendMetric("chase_pct", "Chase%", "%", 1, false), TrendMetric("bb_pct", "BB%", "%", 1, true),
            TrendMetric("opp_barrel_pct", "Barrel% Against", "%", 1, true), TrendMetric("opp_hardhit_pct", "Hard-Hit% Against", "%", 1, true), TrendMetric("opp_ev_avg", "Exit Velo Against", " mph", 1, true),
            TrendMetric("fb_velo_avg", "Fastball Velo", " mph", 1, false), TrendMetric("fb_spin_avg", "Fastball Spin", " rpm", 0, false), TrendMetric("gb_pct", "Ground-Ball%", "%", 1, false),
        ) + listOf("avg", "obp", "slg", "ops").map { TrendMetric(it, "${it.uppercase()} Against", "", 3, true) }
    }
}

object RecentMetricKey {
    fun key(label: String, pitcher: Boolean): String = when (label) {
        "xwOBA" -> if (pitcher) "opp_xwoba" else "xwoba"
        "xBA" -> if (pitcher) "opp_xba" else "xba"
        "xSLG" -> if (pitcher) "opp_xslg" else "xslg"
        "xISO" -> "xiso"
        "Barrel%" -> if (pitcher) "opp_barrel_pct" else "barrel_pct"
        "Hard-Hit%" -> if (pitcher) "opp_hardhit_pct" else "hardhit_pct"
        "Sweet-Spot%" -> "sweetspot_pct"
        "EV", "Avg EV Against" -> if (pitcher) "opp_ev_avg" else "ev_avg"
        "Max EV", "Max EV Against" -> if (pitcher) "opp_ev_max" else "ev_max"
        "K%" -> "k_pct"; "BB%" -> "bb_pct"; "Whiff%" -> "whiff_pct"; "Chase%" -> "chase_pct"
        "Bat Speed" -> "bat_speed"; "Swing Length" -> "swing_length"; "Fastball Velo" -> "fb_velo_avg"; "Fastball Spin" -> "fb_spin_avg"
        else -> label.lowercase()
    }
    fun format(value: Double, label: String): String = when {
        label.endsWith("%") -> String.format(Locale.US, "%.1f%%", value)
        label.endsWith("Spin") -> String.format(Locale.US, "%.0f", value)
        label == "Swing Length" -> String.format(Locale.US, "%.2f", value)
        "EV" in label || "Velo" in label || label == "Bat Speed" -> String.format(Locale.US, "%.1f", value)
        value < 10 -> String.format(Locale.US, "%.3f", value).replace("0.", ".")
        else -> String.format(Locale.US, "%.1f", value)
    }
}
