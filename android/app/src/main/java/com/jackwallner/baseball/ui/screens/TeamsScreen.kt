package com.jackwallner.baseball.ui.screens

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.baseball.data.PaywallTrigger
import com.jackwallner.baseball.model.*
import com.jackwallner.baseball.ui.*
import com.jackwallner.baseball.ui.components.*
import com.jackwallner.baseball.ui.nav.*
import com.jackwallner.baseball.ui.theme.*
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CancellationException

@Composable
fun TeamsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val navigator = LocalNavigator.current
    var query by remember { mutableStateOf("") }
    var category by remember { mutableStateOf(MetricCategory.HITTING) }
    val clubs = vm.seasonPlayers.groupBy { normalizedTeamAbbreviation(it.team) }.filter { (team, _) -> team in teamNicknames && (query.isBlank() || teamMatchesQuery(team, query)) }
        .toList().sortedByDescending { (_, players) -> players.mapNotNull { it.percentile(category) }.takeIf { it.isNotEmpty() }?.average() ?: 0.0 }
    Column {
        SeasonControls()
        SearchField(query, { query = it }, "Search teams")
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricCategory.entries.forEach { c -> FilterChip(category == c, { category = c }, label = { Text(c.raw, style = SavantType.smallBold) }) }
        }
        SectionBar("Every Club", "${clubs.size} TEAMS")
        LazyColumn(Modifier.weight(1f).testTag("teams-list")) {
            if (vm.loading && clubs.isEmpty()) item { LoadingRow() }
            if (clubs.isEmpty() && !vm.loading) item { EmptyMessage("No teams match", "Try another search or season.") }
            itemsIndexed(clubs, key = { _, pair -> pair.first }) { index, (team, players) ->
                val scores = players.mapNotNull { it.percentile(category) }
                Row(Modifier.fillMaxWidth().background(SavantPalette.surface).clickable { navigator.push(Route.Team(team)) }.heightIn(min = 68.dp).padding(12.dp).testTag("team-$team"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${index + 1}", style = SavantType.statSmall, color = SavantPalette.inkTertiary, modifier = Modifier.width(24.dp))
                    Box(Modifier.size(8.dp).background(MLBTeamColor.color(team)))
                    Column(Modifier.weight(1f)) { Text(teamDisplayName(team), style = SavantType.bodyBold, color = SavantPalette.ink); Text("${players.size} players", style = SavantType.small, color = SavantPalette.inkTertiary) }
                    Text(if (scores.isEmpty()) "Unranked" else "${Math.round(scores.average())}", style = SavantType.statLarge, color = SavantPalette.ink)
                }
                HorizontalDivider(thickness = 0.5.dp, color = SavantPalette.divider)
            }
        }
    }
}

@Composable
fun TeamScreen(team: String) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    var category by remember { mutableStateOf(MetricCategory.HITTING) }
    var days by remember { mutableIntStateOf(15) }
    var label by remember(category) { mutableStateOf(category.metricPriorityOrder.first()) }
    var logs by remember { mutableStateOf<List<PlayerGameLog>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    val roster = vm.seasonPlayers.filter { normalizedTeamAbbreviation(it.team) == normalizedTeamAbbreviation(team) }
    LaunchedEffect(team, vm.selectedSeason, vm.selectedPhase, days, graph.subscriptions.isPro, retry) {
        logs = emptyList(); error = null
        if (!graph.subscriptions.isPro || vm.selectedSeason != StatScoutSeason.CURRENT) return@LaunchedEffect
        loading = true
        try {
            val end = (if (vm.selectedPhase == SeasonPhase.POSTSEASON) vm.postseasonThrough else vm.dataThrough) ?: java.time.Instant.now()
            logs = graph.api.fetchTeamGameLogs(team, vm.selectedSeason, end.minus((days - 1).toLong(), ChronoUnit.DAYS), vm.selectedPhase)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "Couldn't load team form. Try again." }
        finally { loading = false }
    }
    PushedScreen(teamDisplayName(team)) {
        LazyColumn(Modifier.weight(1f).testTag("team-page"), contentPadding = PaddingValues(bottom = 16.dp)) {
            item {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(teamDisplayName(team), style = SavantType.playerName, color = SavantPalette.ink, modifier = Modifier.weight(1f))
                    OutlinedButton({ graph.favorites.setFavoriteTeam(if (graph.favorites.isFavoriteTeam(team)) null else team) }) { Text(if (graph.favorites.isFavoriteTeam(team)) "Following" else "Follow") }
                }
                SeasonControls()
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MetricCategory.entries.forEach { c -> FilterChip(category == c, { category = c }, label = { Text(c.raw, style = SavantType.smallBold) }) }
                }
            }
            item { SectionBar("Standard Stats", category.raw.uppercase()) }
            item {
                val totals = aggregateTeamStats(roster, category)
                StandardStatsGrid(totals.map { (name, value) -> StandardStat(name, name, value, category) })
                Text("Totals add up the current roster’s season lines. A traded player brings his whole year with him.", style = SavantType.micro, color = SavantPalette.inkTertiary, modifier = Modifier.padding(16.dp))
            }
            item { SectionBar("Team Percentiles", "ROSTER AVERAGE") }
            item {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    category.metricPriorityOrder.forEach { metricLabel ->
                        val metrics = roster.flatMap { it.metrics }.filter { it.category == category && it.label == metricLabel }
                        if (metrics.isNotEmpty()) MetricBar(Metric(metricLabel, metricLabel, "", Math.round(metrics.map { it.percentile }.average()).toInt(), category))
                    }
                }
            }
            if (vm.selectedSeason == StatScoutSeason.CURRENT && !graph.subscriptions.isPro) item { ProPitch(PaywallTrigger.TeamView) }
            if (vm.selectedSeason == StatScoutSeason.CURRENT && graph.subscriptions.isPro) item {
                SectionBar("Recent Form", "LAST $days DAYS")
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(7, 15, 30).forEach { d -> FilterChip(days == d, { days = d }, label = { Text("$d days", style = SavantType.smallBold) }) } }
                if (loading) LoadingRow()
                error?.let { EmptyMessage("Team form unavailable", it, "Retry", { retry++ }) }
                val window = RecentFormWindow.build(logs.filter { (it.playerType == "pitcher") == (category == MetricCategory.PITCHING) })
                Text("${window.games} team game dates · ${window.plateAppearances}${if (category == MetricCategory.PITCHING) "BF" else "PA"}", style = SavantType.small, color = SavantPalette.inkSecondary, modifier = Modifier.padding(16.dp))
                category.metricPriorityOrder.forEach { metricLabel -> window.metrics[RecentMetricKey.key(metricLabel, category == MetricCategory.PITCHING)]?.let { ValueRow(metricLabel, RecentMetricKey.format(it, metricLabel)) } }
            }
            item {
                SectionBar("Roster", "${roster.size} PLAYERS")
                Box(Modifier.padding(horizontal = 16.dp)) { ChoiceMenu(label, category.metricPriorityOrder.map { it to it }, { label = it }, "roster-metric") }
            }
            items(roster.filter { it.matchesPlayerType(category) }.sortedByDescending { it.metrics.firstOrNull { m -> m.label == label && m.category == category }?.percentile ?: -1 }, key = { it.id }) { p -> PlayerRow(p, p.metrics.firstOrNull { it.label == label && it.category == category }) }
        }
    }
}
