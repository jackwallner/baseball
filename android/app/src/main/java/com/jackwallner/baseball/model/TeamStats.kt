package com.jackwallner.baseball.model

import java.util.Locale

/** Counting stats sum; rates use their underlying counts or the feed's weights. */
fun aggregateTeamStats(roster: List<Player>, category: MetricCategory): Map<String, String> {
    val players = roster.filter { it.matchesPlayerType(category) }
    fun total(label: String) = players.sumOf { it.stat(label, category)?.value?.replace(",", "")?.toDoubleOrNull() ?: 0.0 }
    val counters = when (category) {
        MetricCategory.HITTING -> listOf("PA", "AB", "R", "H", "2B", "3B", "HR", "RBI", "BB", "SO", "SB", "CS")
        MetricCategory.PITCHING -> listOf("W", "L", "SV", "H", "R", "ER", "HR", "BB", "SO")
        MetricCategory.FIELDING -> listOf("E", "A", "PO", "DP")
        MetricCategory.RUNNING -> listOf("SB", "CS")
    }
    val result = linkedMapOf<String, String>()
    counters.forEach { label -> if (players.any { it.stat(label, category) != null }) result[label] = total(label).toInt().toString() }
    fun rate(label: String, numerator: Double, denominator: Double, decimals: Int) {
        if (denominator > 0) result[label] = BaseballNumberStyle.display(String.format(Locale.US, "%.${decimals}f", numerator / denominator))
    }
    fun weightedRate(label: String, weightLabel: String) {
        val samples = players.mapNotNull { player ->
            val value = player.stat(label, category)?.value?.toDoubleOrNull() ?: return@mapNotNull null
            val weight = player.stat(weightLabel, category)?.value?.replace(",", "")?.toDoubleOrNull() ?: return@mapNotNull null
            if (weight > 0) value * weight to weight else null
        }
        rate(label, samples.sumOf { it.first }, samples.sumOf { it.second }, 3)
    }
    if (category == MetricCategory.HITTING) {
        rate("AVG", total("H"), total("AB"), 3)
        // The feed omits HBP and SF. Use the same PA-weighted rates as iOS.
        weightedRate("OBP", "PA")
        weightedRate("OPS", "PA")
        val bases = total("H") + total("2B") + total("3B") * 2 + total("HR") * 3
        rate("SLG", bases, total("AB"), 3)
    }
    if (category == MetricCategory.PITCHING) {
        val innings = players.sumOf { PostseasonQualifier.innings(it.stat("IP", category)?.value?.toDoubleOrNull() ?: 0.0) }
        val outs = Math.round(innings * 3)
        result["IP"] = "${outs / 3}.${outs % 3}"
        rate("ERA", total("ER") * 9, innings, 2)
        rate("WHIP", total("H") + total("BB"), innings, 2)
        rate("K/9", total("SO") * 9, innings, 2)
    }
    if (category == MetricCategory.FIELDING) rate("FLD%", total("PO") + total("A"), total("PO") + total("A") + total("E"), 3)
    return result
}
