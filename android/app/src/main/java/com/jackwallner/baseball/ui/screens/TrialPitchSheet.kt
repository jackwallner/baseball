package com.jackwallner.baseball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.baseball.data.PaywallTrigger
import com.jackwallner.baseball.data.PriceEmphasis
import com.jackwallner.baseball.ui.LocalGraph
import com.jackwallner.baseball.ui.components.Hairline
import com.jackwallner.baseball.ui.components.PlusDirectCTA
import com.jackwallner.baseball.ui.components.SfIcon
import com.jackwallner.baseball.ui.components.TextAction
import com.jackwallner.baseball.ui.components.savantCard
import com.jackwallner.baseball.ui.components.topHairline
import com.jackwallner.baseball.ui.theme.SavantPalette
import com.jackwallner.baseball.ui.theme.SavantType

private data class Benefit(val icon: String, val title: String, val detail: String)

private val TRENDS = Benefit("flame.fill", "The Trends board", "The whole league ranked by who's moving, right now.")
private val RECENT = Benefit("chart.bar.fill", "Recent form everywhere", "Last 7 / 15 / 30 days on any player, team or board.")
private val H2H = Benefit("person.2.fill", "Head-to-head matchups", "Stack any two players across every percentile.")

/** Three one-line benefits, never more, chosen by what the user reached for. */
private fun benefits(trigger: PaywallTrigger): List<Benefit> = when (trigger) {
    is PaywallTrigger.LockedSeason -> listOf(
        Benefit("calendar.badge.clock", "The ${trigger.year} season", "Every percentile ranking, plus every year back to 2015."),
        Benefit("arrow.left.arrow.right.circle.fill", "Year-over-year trends", "Put ${trigger.year} beside any other season and see what moved."),
        TRENDS,
    )
    PaywallTrigger.PastSeason, PaywallTrigger.PastSeasonsLoad, PaywallTrigger.YearCompare -> listOf(
        Benefit("calendar.badge.clock", "Every past season", "Back to 2015, with full percentile history."),
        Benefit("arrow.left.arrow.right.circle.fill", "Year-over-year trends", "Compare any two seasons side by side."),
        TRENDS,
    )
    PaywallTrigger.PlayerComparison, PaywallTrigger.TeamView, PaywallTrigger.Winback -> listOf(
        H2H, Benefit("shield.lefthalf.filled", "Full team scouting", "Every club's roster, ranked by any metric."), TRENDS,
    )
    else -> listOf(TRENDS, RECENT, H2H)
}

/** The one contextual offer: a compact half sheet that names what the user reached for and buys in place. */
@Composable
fun TrialPitchSheet(trigger: PaywallTrigger, onDismiss: () -> Unit) {
    val graph = LocalGraph.current
    LaunchedEffect(trigger) { graph.paywallGate.markPresented(trigger) }
    LaunchedEffect(graph.subscriptions.isPro) { if (graph.subscriptions.isPro) onDismiss() }
    val items = benefits(trigger)
    Column(Modifier.fillMaxWidth().background(SavantPalette.canvas)) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfIcon(trigger.icon, 24.dp, SavantPalette.turf)
                    Text(trigger.title, style = SavantType.pageTitle, color = SavantPalette.ink, maxLines = 2)
                }
                Text(trigger.subtitle, style = SavantType.small, color = SavantPalette.inkSecondary, textAlign = TextAlign.Center, maxLines = 3)
            }
            Column(Modifier.fillMaxWidth().savantCard().padding(horizontal = 14.dp)) {
                items.forEachIndexed { index, benefit ->
                    Row(Modifier.padding(vertical = 9.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.width(24.dp), contentAlignment = Alignment.Center) { SfIcon(benefit.icon, 18.dp, SavantPalette.turf) }
                        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                            Text(benefit.title, style = SavantType.bodyBold, color = SavantPalette.ink)
                            Text(benefit.detail, style = SavantType.small, color = SavantPalette.inkSecondary, maxLines = 2)
                        }
                    }
                    if (index < items.size - 1) Hairline()
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().background(SavantPalette.surface).topHairline()
                .windowInsetsPadding(WindowInsets.navigationBars).padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            PlusDirectCTA(trigger, emphasis = PriceEmphasis.BILLED_AMOUNT_FIRST)
            LegalLinks {
                TextAction("Maybe later", SavantType.micro.copy(letterSpacing = 0.3.sp), SavantPalette.inkSecondary, onDismiss)
            }
        }
    }
}
