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

@Composable
fun CompareScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val navigator = LocalNavigator.current
    var mode by remember { mutableStateOf("Players") }
    var a by rememberRetained("compare-a") { mutableStateOf<Player?>(null) }
    var b by rememberRetained("compare-b") { mutableStateOf<Player?>(null) }
    var choosing by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    var teamA by remember { mutableStateOf<String?>(null) }
    var teamB by remember { mutableStateOf<String?>(null) }
    var seasonA by rememberRetained("compare-season-a") { mutableIntStateOf(vm.selectedSeason) }
    var seasonB by rememberRetained("compare-season-b") { mutableIntStateOf(vm.selectedSeason) }
    val phase = vm.selectedPhase
    fun roster(year: Int) = if (phase == SeasonPhase.POSTSEASON) vm.postseasonPlayers.filter { it.season == year } else vm.players.filter { it.season == year }
    Column {
        SeasonControls()
        Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Players", "Teams", "Seasons").forEach { name -> FilterChip(mode == name, { mode = name }, label = { Text(name, style = SavantType.smallBold) }) }
        }
        if (!graph.subscriptions.isPro) {
            LazyColumn { item { ProPitch(if (mode == "Teams") PaywallTrigger.TeamView else if (mode == "Seasons") PaywallTrigger.YearCompare else PaywallTrigger.PlayerComparison) } }
            return@Column
        }
        if (mode == "Teams") {
            val teamsA = roster(seasonA).map { normalizedTeamAbbreviation(it.team) }.distinct().sorted()
            val teamsB = roster(seasonB).map { normalizedTeamAbbreviation(it.team) }.distinct().sorted()
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                ComparisonSeasonPicker(seasonA, phase) { seasonA = it; teamA = null }
                ChoiceMenu(teamA?.let(::teamDisplayName) ?: "Choose first team", teamsA.map { it to teamDisplayName(it) }, { teamA = it }, "compare-team-a")
                ComparisonSeasonPicker(seasonB, phase) { seasonB = it; teamB = null }
                ChoiceMenu(teamB?.let(::teamDisplayName) ?: "Choose second team", teamsB.map { it to teamDisplayName(it) }, { teamB = it }, "compare-team-b")
                Button({ teamA?.let { first -> teamB?.let { navigator.push(Route.TeamComparison(first, it, seasonA, seasonB, phase)) } } }, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = teamA != null && teamB != null && (teamA != teamB || seasonA != seasonB)) { Text("Compare Teams") }
            }
        } else {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ComparisonSeasonPicker(seasonA, phase) { seasonA = it; a = null }
                OutlinedButton({ choosing = 1 }, Modifier.fillMaxWidth().heightIn(min = 64.dp).testTag("compare-player-a")) { a?.let { PlayerIdentity(it) } ?: Text(if (mode == "Seasons") "Choose a player" else "Choose first player") }
                if (mode == "Players") ComparisonSeasonPicker(seasonB, phase) { seasonB = it; b = null }
                if (mode == "Players") OutlinedButton({ choosing = 2 }, Modifier.fillMaxWidth().heightIn(min = 64.dp).testTag("compare-player-b")) { b?.let { PlayerIdentity(it) } ?: Text("Choose second player") }
                val compatible = a?.let { first -> b?.let { (first.playerType == "pitcher") == (it.playerType == "pitcher") || first.playerType == "two_way" || it.playerType == "two_way" } } ?: true
                if (!compatible) Text("Choose two hitters or two pitchers for a useful comparison.", style = SavantType.small, color = SavantPalette.down)
                Button({ a?.let { first -> if (mode == "Seasons") navigator.push(Route.YearCompare(first)) else b?.let { navigator.push(Route.Comparison(first, it)) } } }, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("compare-start"), enabled = a != null && (mode == "Seasons" || (b != null && (a?.playerId != b?.playerId || a?.season != b?.season) && compatible))) { Text(if (mode == "Seasons") "Compare Seasons" else "Compare") }
                Text("Follow players to keep them one tap from a comparison, and to spot them on the Trends board.", style = SavantType.small, color = SavantPalette.inkSecondary)
            }
            val favorites = vm.seasonPlayers.filter { graph.favorites.isFavorite(it.playerId) }
            if (favorites.isNotEmpty()) {
                SectionBar("Following")
                LazyColumn(Modifier.weight(1f)) { items(favorites, key = { it.id }) { p -> PlayerRow(p) } }
            }
        }
    }
    StatScoutSheet(choosing != 0, { choosing = 0 }) {
        Column(Modifier.fillMaxSize().background(SavantPalette.canvas)) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Choose a player", style = SavantType.pageTitle, color = SavantPalette.ink, modifier = Modifier.weight(1f))
                TextButton({ choosing = 0 }) { Text("Cancel") }
            }
            SearchField(query, { query = it })
            LazyColumn(Modifier.weight(1f)) {
                items(roster(if (choosing == 1) seasonA else seasonB).filter { query.isBlank() || it.name.contains(query, true) || teamMatchesQuery(it.team, query) }.sortedByDescending { it.overallPercentile }, key = { it.id }) { p ->
                    Box(Modifier.fillMaxWidth().clickable { if (choosing == 1) a = p else b = p; choosing = 0; query = "" }.padding(16.dp).testTag("pick-${p.playerId}")) { PlayerIdentity(p) }
                }
            }
        }
    }
}

@Composable
private fun ComparisonSeasonPicker(season: Int, phase: SeasonPhase, onSelect: (Int) -> Unit) {
    val years = if (phase == SeasonPhase.POSTSEASON) listOf(StatScoutSeason.CURRENT) else LocalGraph.current.dashboard.seasons
    ChoiceMenu("$season season", years.map { it to "$it" }, onSelect, "compare-season-$season")
}

@Composable
fun PlayerComparisonScreen(a: Player, b: Player) {
    val actions = LocalAppActions.current
    LaunchedEffect(a.id, b.id) { actions.positiveMoment() }
    PushedScreen("Player Comparison") {
        if (!LocalGraph.current.subscriptions.isPro) { ProPitch(PaywallTrigger.PlayerComparison); return@PushedScreen }
        ComparisonBody(a, b)
    }
}

@Composable
private fun ComparisonBody(a: Player, b: Player) {
    LazyColumn(Modifier.fillMaxSize().testTag("comparison"), contentPadding = PaddingValues(bottom = 16.dp)) {
        item {
            Row(Modifier.fillMaxWidth().background(SavantPalette.surface).padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.weight(1f)) { PlayerIdentity(a); Text("${a.season} · ${a.overallPercentile.ordinal} overall", style = SavantType.small, color = SavantPalette.inkSecondary) }
                Column(Modifier.weight(1f)) { PlayerIdentity(b); Text("${b.season} · ${b.overallPercentile.ordinal} overall", style = SavantType.small, color = SavantPalette.inkSecondary) }
            }
        }
        MetricCategory.entries.forEach { category ->
            val labels = (a.metrics + b.metrics).filter { it.category == category }.map { it.label }.distinct().sortedBy { category.metricPriorityOrder.indexOf(it) }
            if (labels.isNotEmpty()) {
                item { SectionBar(category.raw, "PCTL") }
                items(labels) { label ->
                    val left = a.metrics.firstOrNull { it.label == label && it.category == category }
                    val right = b.metrics.firstOrNull { it.label == label && it.category == category }
                    ComparisonRow(label, left?.let { "${it.value} · ${it.percentile}" } ?: "N/A", right?.let { "${it.value} · ${it.percentile}" } ?: "N/A", (left?.percentile ?: -1).compareTo(right?.percentile ?: -1))
                }
                item { SectionBar("Standard ${category.raw}") }
                val stats = (a.standardStats.orEmpty().filter { it.resolvedCategory(a.playerType) == category } + b.standardStats.orEmpty().filter { it.resolvedCategory(b.playerType) == category }).map { it.label }.distinct()
                items(stats) { label -> ComparisonRow(label, a.stat(label, category)?.value ?: "N/A", b.stat(label, category)?.value ?: "N/A") }
            }
        }
    }
}

@Composable
fun ComparisonRow(label: String, left: String, right: String, winner: Int = 0) {
    Row(Modifier.fillMaxWidth().background(SavantPalette.surface).heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(left, style = SavantType.statMed, color = if (winner > 0) SavantPalette.up else SavantPalette.ink, modifier = Modifier.weight(1f))
        Text(label, style = SavantType.smallBold, color = SavantPalette.inkSecondary, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Text(right, style = SavantType.statMed, color = if (winner < 0) SavantPalette.up else SavantPalette.ink, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
    HorizontalDivider(thickness = 0.5.dp, color = SavantPalette.divider)
}

@Composable
fun YearComparisonScreen(player: Player) {
    val graph = LocalGraph.current
    val history = graph.dashboard.players.filter { it.playerId == player.playerId }.sortedByDescending { it.season }
    var first by remember { mutableIntStateOf(player.season ?: StatScoutSeason.CURRENT) }
    var second by remember(history.size) { mutableIntStateOf(history.firstOrNull { it.season != first }?.season ?: first) }
    PushedScreen("Year-over-Year") {
        if (!graph.subscriptions.isPro) { ProPitch(PaywallTrigger.YearCompare); return@PushedScreen }
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            ChoiceMenu("$first", history.mapNotNull { it.season }.distinct().map { it to "$it" }, { first = it }, "year-first")
            ChoiceMenu("$second", history.mapNotNull { it.season }.distinct().map { it to "$it" }, { second = it }, "year-second")
        }
        if (graph.dashboard.historyLoading) LoadingRow()
        val a = history.firstOrNull { it.season == first }
        val b = history.firstOrNull { it.season == second }
        if (a != null && b != null) Box(Modifier.weight(1f)) { ComparisonBody(a, b) }
        else EmptyMessage("Past seasons unavailable", graph.dashboard.historyError ?: "No season history for this player.", "Retry", graph.dashboard::loadHistory)
    }
}

@Composable
fun TeamComparisonScreen(teamA: String, teamB: String, seasonA: Int, seasonB: Int, phase: SeasonPhase) {
    val graph = LocalGraph.current
    val players = if (phase == SeasonPhase.POSTSEASON) graph.dashboard.postseasonPlayers else graph.dashboard.players
    val rosterA = players.filter { it.season == seasonA && normalizedTeamAbbreviation(it.team) == teamA }
    val rosterB = players.filter { it.season == seasonB && normalizedTeamAbbreviation(it.team) == teamB }
    PushedScreen("Team Comparison") {
        if (!graph.subscriptions.isPro) { ProPitch(PaywallTrigger.TeamView); return@PushedScreen }
        LazyColumn {
            item { ComparisonRow(phase.label, "$teamA $seasonA", "$teamB $seasonB") }
            MetricCategory.entries.forEach { category ->
                item { SectionBar(category.raw, "ROSTER PCTL") }
                items(category.metricPriorityOrder) { label ->
                    val a = rosterA.flatMap { it.metrics }.filter { it.label == label && it.category == category }.map { it.percentile }.takeIf { it.isNotEmpty() }?.average()?.let { Math.round(it).toInt() }
                    val b = rosterB.flatMap { it.metrics }.filter { it.label == label && it.category == category }.map { it.percentile }.takeIf { it.isNotEmpty() }?.average()?.let { Math.round(it).toInt() }
                    if (a != null || b != null) ComparisonRow(label, a?.toString() ?: "N/A", b?.toString() ?: "N/A", (a ?: -1).compareTo(b ?: -1))
                }
                val statsA = aggregateTeamStats(rosterA, category)
                val statsB = aggregateTeamStats(rosterB, category)
                item { SectionBar("Standard ${category.raw}") }
                items((statsA.keys + statsB.keys).distinct()) { label -> ComparisonRow(label, statsA[label] ?: "N/A", statsB[label] ?: "N/A") }
            }
        }
    }
}
