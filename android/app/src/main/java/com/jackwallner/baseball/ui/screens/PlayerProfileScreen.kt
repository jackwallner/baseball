package com.jackwallner.baseball.ui.screens

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.baseball.data.PaywallTrigger
import com.jackwallner.baseball.model.*
import com.jackwallner.baseball.ui.*
import com.jackwallner.baseball.ui.components.*
import com.jackwallner.baseball.ui.nav.*
import com.jackwallner.baseball.ui.theme.*
import kotlinx.coroutines.CancellationException

@Composable
fun PlayerProfileScreen(initial: Player) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val context = LocalContext.current
    val history = graph.dashboard.players.filter { it.playerId == initial.playerId }.sortedByDescending { it.season }
    var season by remember { mutableIntStateOf(initial.season ?: StatScoutSeason.CURRENT) }
    val player = if (season == initial.season) initial else history.firstOrNull { it.season == season } ?: initial
    var category by remember { mutableStateOf(if (initial.playerType == "pitcher") MetricCategory.PITCHING else MetricCategory.HITTING) }
    var days by remember { mutableIntStateOf(15) }
    val openingPhase = remember { graph.dashboard.selectedPhase }
    val phase = if (season == StatScoutSeason.CURRENT) openingPhase else SeasonPhase.REGULAR
    var logs by remember { mutableStateOf<List<PlayerGameLog>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(initial.playerId) { actions.positiveMoment() }
    LaunchedEffect(player.playerId, season, phase, graph.subscriptions.isPro, retry) {
        logs = emptyList(); error = null
        if (!graph.subscriptions.isPro) return@LaunchedEffect
        loading = true
        try { logs = graph.api.fetchGameLogs(player.playerId, season, phase) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "Couldn't load game logs. Try again." }
        finally { loading = false }
    }
    PushedScreen(player.name, trailing = {
        IconButton({ context.shareText(player.shareSummary) }) { SfIcon("square.and.arrow.up", 22.dp, androidx.compose.ui.graphics.Color.White, contentDescription = "Share player") }
    }) {
        LazyColumn(Modifier.weight(1f).testTag("player-profile"), contentPadding = PaddingValues(bottom = 20.dp)) {
            item {
                Column(Modifier.fillMaxWidth().background(SavantPalette.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PlayerIdentity(player)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("${player.overallPercentile.ordinal} overall", style = SavantType.statLarge, color = SavantPalette.textColor(player.overallPercentile), modifier = Modifier.weight(1f))
                        OutlinedButton({ graph.favorites.toggleFavorite(player.playerId) }, Modifier.testTag("follow-player")) { Text(if (graph.favorites.isFavorite(player.playerId)) "Following" else "Follow") }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ChoiceMenu("$season", history.mapNotNull { it.season }.distinct().map { it to "$it" }, { if (it < StatScoutSeason.CURRENT && !graph.subscriptions.isPro) actions.openTrialPitch(PaywallTrigger.LockedSeason(it)) else season = it }, "profile-season")
                        TextButton({ navigator.push(Route.Team(player.team)) }) { Text(teamDisplayName(player.team), style = SavantType.smallBold) }
                    }
                    if (phase == SeasonPhase.POSTSEASON) Text("Postseason values · Percentiles vs $season regular season", style = SavantType.small, color = SavantPalette.inkSecondary)
                }
            }
            item {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MetricCategory.entries.filter { c -> player.metrics.any { it.category == c } || player.standardStats.orEmpty().any { it.resolvedCategory(player.playerType) == c } }.forEach { c -> FilterChip(category == c, { category = c }, label = { Text(c.raw, style = SavantType.smallBold) }) }
                }
            }
            item { SectionBar("Standard Stats", "$season") }
            item { StandardStatsGrid(player.standardStats.orEmpty().filter { it.resolvedCategory(player.playerType) == category }) }
            item { SectionBar("Statcast Percentiles", category.raw.uppercase()) }
            items(player.metrics.filter { it.category == category }.sortedBy { category.metricPriorityOrder.indexOf(it.label).let { i -> if (i < 0) Int.MAX_VALUE else i } }, key = { it.id }) { metric ->
                Box(Modifier.padding(horizontal = 16.dp).background(SavantPalette.surface)) { MetricBar(metric) { navigator.push(Route.Metric(metric.label, metric.category)) } }
            }
            if (season == StatScoutSeason.CURRENT) item { SectionBar("Recent Form", phase.label.uppercase()) }
            if (!graph.subscriptions.isPro) item { ProPitch(PaywallTrigger.PlayerScouting) }
            else {
                if (season == StatScoutSeason.CURRENT) item {
                    Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(7, 15, 30).forEach { d -> FilterChip(days == d, { days = d }, label = { Text("$d days", style = SavantType.smallBold) }) } }
                    if (loading) LoadingRow()
                    error?.let { EmptyMessage("Recent form unavailable", it, "Retry", { retry++ }) }
                    val end = if (phase == SeasonPhase.POSTSEASON) graph.dashboard.postseasonThrough else graph.dashboard.dataThrough
                    val cutoff = (end ?: java.time.Instant.now()).atZone(java.time.ZoneId.of("America/New_York")).toLocalDate().minusDays((days - 1).toLong()).atStartOfDay(java.time.ZoneId.of("America/New_York")).toInstant()
                    val windowLogs = logs.filter { it.gameDate >= cutoff && (it.playerType == "pitcher") == (category == MetricCategory.PITCHING) }
                    val window = RecentFormWindow.build(windowLogs)
                    Column(Modifier.padding(16.dp)) {
                        Text("Last $days days through ${dayLabel(end)} · ${window.games}G · ${window.plateAppearances}${if (category == MetricCategory.PITCHING) "BF" else "PA"}", style = SavantType.small, color = SavantPalette.inkSecondary)
                        if (window.plateAppearances < if (category == MetricCategory.PITCHING) 30 else 15) Text("Small sample", style = SavantType.micro, color = SavantPalette.inkTertiary)
                        player.metrics.filter { it.category == category }.forEach { m -> window.metrics[RecentMetricKey.key(m.label, category == MetricCategory.PITCHING)]?.let { value -> ValueRow(m.label, RecentMetricKey.format(value, m.label)) } }
                    }
                    if (!loading && logs.isEmpty() && error == null) EmptyMessage("No game logs for this season")
                }
                item { SectionBar("Game Log") }
                items(logs.sortedByDescending { it.gameDate }.take(30)) { log -> ValueRow(dayLabel(log.gameDate), "${log.opponent ?: ""} · ${log.plateAppearances}${if (log.playerType == "pitcher") "BF" else "PA"}") }
                item { Button({ navigator.push(Route.YearCompare(player)) }, Modifier.fillMaxWidth().padding(16.dp)) { Text("Compare Seasons") } }
            }
        }
    }
}

@Composable
fun ValueRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().background(SavantPalette.surface).heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = SavantType.body, color = SavantPalette.inkSecondary, modifier = Modifier.weight(1f))
        Text(value, style = SavantType.statMed, color = SavantPalette.ink)
    }
    HorizontalDivider(thickness = 0.5.dp, color = SavantPalette.divider)
}

@Composable
fun StandardStatsGrid(stats: List<StandardStat>) {
    Column(Modifier.fillMaxWidth().background(SavantPalette.surface).padding(12.dp)) {
        if (stats.isEmpty()) Text("No standard line available", style = SavantType.small, color = SavantPalette.inkTertiary)
        stats.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                row.forEach { stat -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Text(stat.label, style = SavantType.micro, color = SavantPalette.inkTertiary); Text(stat.value, style = SavantType.statLarge, color = SavantPalette.ink) } }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
