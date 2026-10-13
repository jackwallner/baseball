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
import com.jackwallner.baseball.BuildConfig
import com.jackwallner.baseball.data.*
import com.jackwallner.baseball.model.*
import com.jackwallner.baseball.ui.*
import com.jackwallner.baseball.ui.components.*
import com.jackwallner.baseball.ui.nav.*
import com.jackwallner.baseball.ui.theme.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen() {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf<String?>(null) }
    var restoring by remember { mutableStateOf(false) }
    var reviewCodeOpen by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var invalid by remember { mutableStateOf(false) }
    PushedScreen("Settings") {
        LazyColumn(Modifier.weight(1f).testTag("settings-page")) {
            item { SectionBar("StatScout+") }
            item {
                if (store.isPro) ValueRow("Membership", "StatScout+")
                else SettingAction("Upgrade to StatScout+") { actions.openPaywall(PaywallTrigger.Upgrade) }
                SettingAction(if (restoring) "Restoring…" else "Restore Purchases", !restoring) {
                    scope.launch {
                        restoring = true
                        try { store.restorePurchases(); message = if (store.isPro) "StatScout+ restored." else "No active purchases found on this Google Play account." }
                        catch (e: Exception) { message = e.message ?: "Restore failed. Please try again." }
                        finally { restoring = false }
                    }
                }
                SettingAction("Manage Subscription") { context.openUrl(StoreLinks.manageSubscriptionURL(store.activeProductId)) }
                message?.let { Text(it, style = SavantType.small, color = SavantPalette.inkSecondary, modifier = Modifier.padding(16.dp)) }
            }
            item { SectionBar("Data") }
            item {
                ValueRow("Current season", "${StatScoutSeason.CURRENT}")
                ValueRow("Data through", dayLabel(graph.dashboard.dataThrough))
                ValueRow("Last update", dayLabel(graph.dashboard.players.filter { it.season == StatScoutSeason.CURRENT }.maxOfOrNull { it.updatedAt }))
                ValueRow("Historical seasons", "${StatScoutSeason.EARLIEST}–${StatScoutSeason.CURRENT - 1}")
                SettingAction("Refresh Data") { graph.dashboard.refresh() }
                Text("Statcast data updates nightly. Postseason values use the regular-season percentile curve. Team percentiles average ranked roster players.", style = SavantType.small, color = SavantPalette.inkSecondary, modifier = Modifier.padding(16.dp))
            }
            item { SectionBar("Help & Feedback") }
            item {
                SettingAction("Stat Glossary") { navigator.push(Route.Glossary) }
                SettingAction("Rate on Google Play") { context.openPlayListing() }
                SettingAction("Send Feedback") { actions.openFeedback() }
                SettingAction("Support") { context.openUrl(StoreLinks.SUPPORT_URL) }
            }
            item { SectionBar("About") }
            item {
                SettingAction("Privacy Policy") { context.openUrl(StoreLinks.PRIVACY_URL) }
                SettingAction("Terms of Use") { context.openUrl(StoreLinks.TERMS_URL) }
                Text("Independent baseball analysis. StatScout is not affiliated with or endorsed by MLB, any team, or Baseball Savant.", style = SavantType.small, color = SavantPalette.inkSecondary, modifier = Modifier.padding(16.dp))
                Box(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { reviewCodeOpen = true }).testTag("app-version")) { ValueRow("App Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})") }
            }
        }
    }
    if (reviewCodeOpen) AlertDialog(onDismissRequest = { reviewCodeOpen = false }, title = { Text("Reviewer Access") }, text = {
        Column { OutlinedTextField(code, { code = it; invalid = false }, label = { Text("Access code") }, singleLine = true, isError = invalid); if (invalid) Text("Code not recognized.") }
    }, confirmButton = { TextButton({ if (store.activateReviewAccess(code)) { reviewCodeOpen = false; code = "" } else invalid = true }) { Text("Unlock") } }, dismissButton = { TextButton({ reviewCodeOpen = false; code = "" }) { Text("Cancel") } })
}

@Composable
private fun SettingAction(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    TextButton(onClick, Modifier.fillMaxWidth().heightIn(min = 52.dp).background(SavantPalette.surface), enabled = enabled, contentPadding = PaddingValues(horizontal = 16.dp)) { Text(title, style = SavantType.body, modifier = Modifier.weight(1f), color = SavantPalette.linkBlue) }
    HorizontalDivider(thickness = 0.5.dp, color = SavantPalette.divider)
}

@Composable
fun GlossaryScreen() {
    PushedScreen("Stat Glossary") {
        LazyColumn(Modifier.weight(1f)) {
            items(glossary.entries.toList()) { (term, meaning) -> Column(Modifier.fillMaxWidth().padding(16.dp)) { Text(term, style = SavantType.cardTitle, color = SavantPalette.ink); Text(meaning, style = SavantType.body, color = SavantPalette.inkSecondary) } }
        }
    }
}

private val glossary = linkedMapOf(
    "Percentile" to "A 90th percentile ranks above 90% of qualified players. Higher percentiles always mean better performance, even when a lower raw value is better. Red is high, blue is low.",
    "xwOBA" to "Expected weighted on-base average estimates production from contact quality and strikeouts or walks.",
    "xBA" to "Expected batting average estimates the chance that each batted ball becomes a hit from its exit velocity and launch angle.",
    "xSLG / xISO" to "Expected slugging percentage and isolated power describe the quality of a player's extra-base contact.",
    "xERA" to "Expected earned run average translates a pitcher's expected weighted on-base average allowed into an ERA scale. Lower is better.",
    "Barrel%" to "The share of batted balls with the combination of exit velocity and launch angle most likely to produce extra-base hits.",
    "Hard-Hit%" to "The share of batted balls hit at least 95 mph.",
    "EV / Max EV" to "Average and maximum exit velocity, measured in miles per hour off the bat.",
    "K% / BB%" to "Strikeouts or walks as a percentage of plate appearances. For a pitcher these describe the batters faced.",
    "Whiff% / Chase%" to "Swings that miss and swings at pitches outside the strike zone.",
    "Bat Speed / Swing Length" to "The speed of the bat through the hitting zone and the distance it travels in a swing.",
    "Fastball Velo / Spin" to "Average fastball velocity in mph and spin rate in revolutions per minute.",
    "Range (OAA)" to "Outs Above Average estimates outs saved by a fielder relative to an average defender.",
    "Sprint Speed" to "A runner's fastest one-second window, expressed in feet per second.",
    "Recent Form" to "Last 7, 15, or 30 calendar days through the data coverage date. Deltas compare the window to the equal-length window immediately before it.",
    "Postseason" to "October is stored separately from regular-season data. Percentiles compare postseason values to the same year's regular-season curve. Qualified boards use 3.1 PA or 1 inning per team game.",
)
