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
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException

@Composable
fun ProPitch(trigger: PaywallTrigger) {
    val actions = LocalAppActions.current
    val store = LocalGraph.current.subscriptions
    Column(Modifier.fillMaxWidth().padding(16.dp).savantCard().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(trigger.title, style = SavantType.playerName, color = SavantPalette.ink)
        Text(trigger.subtitle, style = SavantType.body, color = SavantPalette.inkSecondary)
        Button({ actions.openPaywall(trigger) }, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("unlock-${trigger.paywallImpressionId}")) { Text("${store.upgradeCTALabel} StatScout+", style = SavantType.bodyBold) }
    }
}

fun dayLabel(instant: Instant?): String = instant?.atZone(EASTERN)?.let { DateTimeFormatter.ofPattern("MMM d, yyyy").format(it) } ?: "Not available"

@Composable
fun TrendsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val navigator = LocalNavigator.current
    var pitcher by remember { mutableStateOf(false) }
    var days by remember { mutableIntStateOf(15) }
    var qualifier by remember { mutableStateOf(TrendQualifier.REGULARS) }
    var selected by remember(pitcher) { mutableStateOf(if (pitcher) TrendMetric.pitching.first() else TrendMetric.batting.first()) }
    var rising by remember { mutableStateOf(true) }
    var following by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var forms by remember { mutableStateOf<List<RecentForm>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(days, retry) {
        loading = true; error = null
        try { forms = graph.api.fetchRecentForm(StatScoutSeason.CURRENT, days) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = "Couldn't load recent form. Check your connection and try again."; forms = emptyList() }
        finally { loading = false }
    }
    val players = vm.players.filter { it.season == StatScoutSeason.CURRENT }.associateBy { it.playerId }
    val ranked = forms.filter { (it.playerType == "pitcher") == pitcher && qualifier.admits(it) && it.delta[selected.key] != null }
        .mapNotNull { form -> players[form.playerId]?.let { it to form } }
        .filter { (p, _) -> (query.isBlank() || p.name.contains(query, true) || teamMatchesQuery(p.team, query)) && (!following || graph.favorites.isFavorite(p.playerId)) }
        .sortedBy { (_, form) -> form.delta.getValue(selected.key) * (if (selected.lowerIsBetter) -1 else 1) * (if (rising) -1 else 1) }
    Column {
        SearchField(query, { query = it })
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ChoiceMenu(if (pitcher) "Pitching" else "Hitting", listOf(false to "Hitting", true to "Pitching"), { pitcher = it }, "trend-side")
            ChoiceMenu("Last $days days", listOf(7, 15, 30).map { it to "Last $it days" }, { days = it }, "trend-window")
            ChoiceMenu(selected.label, (if (pitcher) TrendMetric.pitching else TrendMetric.batting).map { it to it.label }, { selected = it }, "trend-metric")
            ChoiceMenu(qualifier.label, TrendQualifier.entries.map { it to it.label }, { qualifier = it }, "trend-qualifier")
        }
        Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(rising, { rising = true }, label = { Text("Heating up", style = SavantType.smallBold) })
            FilterChip(!rising, { rising = false }, label = { Text("Cooling off", style = SavantType.smallBold) })
            FilterChip(following, { following = !following }, label = { Text("Following", style = SavantType.smallBold) })
        }
        Text("Through ${dayLabel(forms.mapNotNull { it.asOf }.maxOrNull())} · ${qualifier.minimum(pitcher, days)}+ ${if (pitcher) "BF" else "PA"}", style = SavantType.small, color = SavantPalette.inkSecondary, modifier = Modifier.padding(16.dp))
        SectionBar(if (rising) "Heating up" else "Cooling off", selected.label)
        LazyColumn(Modifier.weight(1f).testTag("trends-list")) {
            if (loading) item { LoadingRow() }
            error?.let { item { EmptyMessage("Recent form unavailable", it, "Retry", { retry++ }) } }
            if (!loading && error == null && ranked.isEmpty()) item { EmptyMessage("No matching recent form", "Try a different window, sample threshold, or player.") }
            items((if (graph.subscriptions.isPro) ranked else ranked.take(3)), key = { "${it.first.id}-${it.second.playerType}" }) { (player, form) ->
                Row(Modifier.fillMaxWidth().background(SavantPalette.surface).clickable { navigator.push(Route.PlayerProfile(player)) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    PlayerIdentity(player, Modifier.weight(1f))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(form.metrics[selected.key]?.let(selected::format) ?: "", style = SavantType.statLarge, color = SavantPalette.ink)
                        val delta = form.delta[selected.key] ?: 0.0
                        Text("${if (delta > 0) "+" else ""}${selected.format(delta)}", style = SavantType.statSmall, color = if ((delta > 0) != selected.lowerIsBetter) SavantPalette.up else SavantPalette.down)
                        Text("${form.games}G · ${form.plateAppearances}${if (pitcher) "BF" else "PA"}", style = SavantType.micro, color = SavantPalette.inkTertiary)
                    }
                }
                HorizontalDivider(thickness = 0.5.dp, color = SavantPalette.divider)
            }
            if (!graph.subscriptions.isPro) item { ProPitch(PaywallTrigger.RecentForm) }
        }
    }
}
