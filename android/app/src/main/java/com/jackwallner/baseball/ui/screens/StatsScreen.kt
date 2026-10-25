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
fun SeasonControls() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val actions = LocalAppActions.current
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ChoiceMenu("${vm.selectedSeason}", vm.seasons.map { it to "$it${if (it < StatScoutSeason.CURRENT && !graph.subscriptions.isPro) " · Pro" else ""}" }, {
            val season = it
            val selectSeason = { vm.selectedSeason = season; if (season != StatScoutSeason.CURRENT) vm.selectedPhase = SeasonPhase.REGULAR }
            if (season < StatScoutSeason.CURRENT && !graph.subscriptions.isPro) actions.openTrialPitch(PaywallTrigger.LockedSeason(season), selectSeason)
            else selectSeason()
        }, "season-picker")
        if (vm.selectedSeason == StatScoutSeason.CURRENT) ChoiceMenu(vm.selectedPhase.label, SeasonPhase.entries.map { it to it.label }, { vm.selectedPhase = it }, "phase-picker")
        IconButton({ vm.refresh() }, Modifier.testTag("refresh")) { SfIcon("arrow.clockwise", 20.dp, SavantPalette.linkBlue, contentDescription = "Refresh data") }
    }
}

@Composable
fun StatsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val actions = LocalAppActions.current
    var board by remember { mutableStateOf("Leaders") }
    var query by remember { mutableStateOf("") }
    var category by remember { mutableStateOf(MetricCategory.HITTING) }
    var label by remember(category) { mutableStateOf(category.metricPriorityOrder.first()) }
    var standard by remember { mutableStateOf(false) }
    var qualifier by remember { mutableStateOf("Qualified") }
    var descending by remember { mutableStateOf(true) }
    var position by remember { mutableStateOf("All positions") }
    val roster = vm.seasonPlayers.filter { it.matchesPlayerType(category) }
    val labels = if (standard) roster.flatMap { it.standardStats.orEmpty().filter { s -> s.resolvedCategory(it.playerType) == category }.map { it.label } }.distinct().sorted() else category.metricPriorityOrder
    val activeLabel = if (label in labels) label else labels.firstOrNull() ?: label
    val sorted = roster.filter { p ->
        (query.isBlank() || p.name.contains(query, true) || teamMatchesQuery(p.team, query)) &&
        (position == "All positions" || p.displayPosition == position) && vm.qualified(p, category, qualifier) &&
        (board != "Following" || graph.favorites.isFavorite(p.playerId))
    }.filter { p -> if (standard) p.stat(activeLabel, category) != null else p.metrics.any { it.category == category && it.label == activeLabel } }
        .sortedWith(compareBy<Player> { p ->
            val value = if (standard) p.stat(activeLabel, category)?.value else p.metrics.firstOrNull { it.category == category && it.label == activeLabel }?.value
            (value?.replace(",", "")?.removeSuffix("%")?.toDoubleOrNull() ?: 0.0) * if (descending) -1 else 1
        }.thenBy { it.name })
    Column {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("Leaders", "Following", "Best & Worst").forEach { name -> FilterChip(board == name, { if (name == "Best & Worst" && !graph.subscriptions.isPro) actions.openTrialPitch(PaywallTrigger.BestWorst) { board = name } else board = name }, label = { Text(name, style = SavantType.smallBold) }, modifier = Modifier.testTag("board-$name")) }
        }
        SeasonControls()
        SearchField(query, { query = it })
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ChoiceMenu(category.raw, MetricCategory.entries.map { it to it.raw }, { category = it }, "category-picker")
            ChoiceMenu(if (standard) "Standard" else "Statcast", listOf(false to "Statcast", true to "Standard"), { standard = it }, "stat-mode")
            ChoiceMenu(activeLabel, labels.map { it to it }, { label = it }, "metric-picker")
            ChoiceMenu(qualifier, listOf("All", "Min Sample", "Qualified").map { it to it }, { qualifier = it }, "qualifier-picker")
            ChoiceMenu(if (position == "All positions") "Pos" else position, (listOf("All positions") + roster.map { it.displayPosition }.distinct().sorted()).map { it to it }, { position = it }, "position-picker")
            IconButton({ descending = !descending }) { SfIcon(if (descending) "arrow.down" else "arrow.up", 18.dp, SavantPalette.ink, contentDescription = "Reverse sort order") }
        }
        if (vm.selectedPhase == SeasonPhase.POSTSEASON) Text("Postseason values · Percentiles vs ${vm.selectedSeason} regular season", style = SavantType.small, color = SavantPalette.inkSecondary, modifier = Modifier.padding(16.dp))
        vm.error?.let { Text(it, style = SavantType.small, color = SavantPalette.down, modifier = Modifier.padding(16.dp)) }
        SectionBar(if (board == "Following") "Following" else "$activeLabel Leaders", "${sorted.size} PLAYERS")
        LazyColumn(Modifier.weight(1f).testTag("leaderboard"), contentPadding = PaddingValues(bottom = 16.dp)) {
            if (vm.loading && sorted.isEmpty()) item { LoadingRow() }
            if (board == "Following" && graph.favorites.playerIds.isEmpty()) item { EmptyMessage("Keep your players one tap away", "Open a player and tap Follow to build your list.") }
            if (sorted.isEmpty() && !vm.loading && !(board == "Following" && graph.favorites.playerIds.isEmpty())) item {
                EmptyMessage("No players match", if (vm.selectedPhase == SeasonPhase.POSTSEASON) vm.postseasonError ?: "Postseason player lines may still be arriving. Try All or another category." else "Try another search, category, or qualifier.", if (vm.error != null) "Retry" else null, vm::refresh)
            }
            val visible = if (board == "Best & Worst") (sorted.take(10) + sorted.takeLast(10).reversed()).distinctBy { it.id } else sorted
            itemsIndexed(visible, key = { _, p -> p.id }) { index, player ->
                val metric = if (standard) player.stat(activeLabel, category)?.let { Metric(it.id, it.label, it.value, player.percentile(category) ?: 0, category) } else player.metrics.firstOrNull { it.category == category && it.label == activeLabel }
                PlayerRow(player, metric, index + 1)
            }
        }
    }
}

@Composable
fun MetricLeadersScreen(label: String, category: MetricCategory) {
    val vm = LocalGraph.current.dashboard
    val roster = vm.seasonPlayers.filter { it.matchesPlayerType(category) && vm.qualified(it, category, "Qualified") }
        .mapNotNull { p -> p.metrics.firstOrNull { it.label == label && it.category == category }?.let { p to it } }.sortedByDescending { it.second.percentile }
    PushedScreen(label) {
        SectionBar("${category.raw} · ${vm.selectedSeason}", "PCTL")
        LazyColumn { itemsIndexed(roster, key = { _, it -> it.first.id }) { index, pair -> PlayerRow(pair.first, pair.second, index + 1) } }
    }
}
