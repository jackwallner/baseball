package com.jackwallner.baseball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.baseball.ui.components.*
import com.jackwallner.baseball.ui.theme.*

@Composable
fun OnboardingScreen(onComplete: () -> Unit) {
    var page by remember { mutableIntStateOf(0) }
    val titles = listOf("Who's hot\nright now.", "Any two.\nAny season.", "Every club.\nEvery angle.")
    val details = listOf("Spot the hitters heating up and the pitchers finding their stride. Real Statcast data, updated nightly.", "Compare players head-to-head and see how their rankings changed, season by season, back to 2015.", "Scout all 30 clubs. Explore hitting, pitching, fielding, and running, with the numbers that explain the game.")
    Column(Modifier.fillMaxSize().background(SavantPalette.canvas).safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("STATSCOUT", style = SavantType.cardTitle, color = SavantPalette.midnight, modifier = Modifier.weight(1f))
            TextAction("Skip", SavantType.smallBold, SavantPalette.linkBlue, onComplete, Modifier.testTag("onboarding-skip"))
        }
        Spacer(Modifier.weight(0.4f))
        Text(titles[page], style = SavantType.statHero, color = SavantPalette.ink)
        Text(details[page], style = SavantType.body, color = SavantPalette.inkSecondary)
        Column(Modifier.fillMaxWidth().savantCard().padding(16.dp)) {
            SectionBar(listOf("RECENT FORM", "PLAYER COMPARISON", "30 CLUBS")[page])
            listOf("xwOBA" to 92, "Barrel%" to 86, "Exit Velo" to 79).forEach { (name, percentile) ->
                MetricBar(com.jackwallner.baseball.model.Metric(name, name, "", percentile, com.jackwallner.baseball.model.MetricCategory.HITTING))
            }
        }
        Text("StatScout+ unlocks Trends, recent form, comparisons, and every past season. Explore current-season leaders and follow players free.", style = SavantType.small, color = SavantPalette.inkSecondary)
        Spacer(Modifier.weight(1f))
        Text("${page + 1} / 3", style = SavantType.micro, color = SavantPalette.inkTertiary)
        Button({ if (page < 2) page++ else onComplete() }, Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("onboarding-continue")) { Text(if (page < 2) "Continue" else "Start Scouting", style = SavantType.bodyBold) }
    }
}
