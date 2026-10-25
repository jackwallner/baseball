package com.jackwallner.baseball.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.baseball.AppGraph
import com.jackwallner.baseball.DebugLaunchOptions
import com.jackwallner.baseball.data.PaywallTrigger
import com.jackwallner.baseball.data.PendingUnlockAction
import com.jackwallner.baseball.data.StoreLinks
import com.jackwallner.baseball.ui.components.*
import com.jackwallner.baseball.ui.nav.*
import com.jackwallner.baseball.ui.screens.*
import com.jackwallner.baseball.ui.theme.*

private val tabNames = listOf("Stats", "Trends", "Teams", "Compare")
private val tabIcons = listOf("chart.bar.fill", "flame.fill", "shield.lefthalf.filled", "arrow.left.arrow.right")

@Composable
fun RootScreen(graph: AppGraph) {
    var onboarded by remember { mutableStateOf(graph.defaults.getBoolean("hasCompletedOnboarding")) }
    var tab by remember { mutableIntStateOf(DebugLaunchOptions.launchTab ?: 0) }
    var paywall by remember { mutableStateOf<PaywallTrigger?>(null) }
    var trialPitch by remember { mutableStateOf<PaywallTrigger?>(null) }
    val pendingUnlock = remember { PendingUnlockAction() }
    val navigators = remember { List(4) { Navigator() } }
    val context = LocalContext.current
    val actions = remember {
        object : AppActions {
            override fun openPaywall(trigger: PaywallTrigger) {
                if (trialPitch != trigger) pendingUnlock.set(null)
                trialPitch = null
                paywall = trigger
            }
            override fun openTrialPitch(trigger: PaywallTrigger, onUnlock: (() -> Unit)?) {
                if (onUnlock != null || graph.paywallGate.shouldPresent(trigger)) {
                    pendingUnlock.set(onUnlock)
                    trialPitch = trigger
                }
            }
            override fun openFeedback() { context.openMail(StoreLinks.feedbackMail("StatScout feedback", "")) }
            override fun positiveMoment() {
                graph.review.recordPositiveMoment()
                if (!graph.review.shouldShowAfterPositiveMoment(graph.defaults.getBoolean("hasCompletedOnboarding"))) return
                val activity = context.findActivity() ?: return
                val manager = ReviewManagerFactory.create(context)
                graph.review.markShown()
                manager.requestReviewFlow().addOnSuccessListener { manager.launchReviewFlow(activity, it) }
            }
        }
    }
    fun dismissOffer() {
        trialPitch = null
        paywall = null
        pendingUnlock.dismiss(graph.subscriptions.isPro, graph.subscriptions.purchasePending)
    }
    LaunchedEffect(graph.subscriptions.isPro) {
        if (graph.subscriptions.isPro) dismissOffer()
    }
    LaunchedEffect(Unit) { graph.dashboard.start() }
    LaunchedEffect(graph.pendingTab) {
        graph.pendingTab?.let { name -> tabNames.indexOfFirst { it.equals(name, true) }.takeIf { it >= 0 }?.let { tab = it }; graph.pendingTab = null }
    }
    CompositionLocalProvider(LocalAppActions provides actions) {
        if (!onboarded) {
            OnboardingScreen {
                graph.defaults.putBoolean("hasCompletedOnboarding", true)
                onboarded = true
            }
        } else {
            Scaffold(
                containerColor = SavantPalette.canvas,
                contentWindowInsets = WindowInsets(0, 0, 0, 0),
                bottomBar = {
                    NavigationBar(containerColor = SavantPalette.surface, tonalElevation = 0.dp) {
                        tabNames.forEachIndexed { index, title ->
                            NavigationBarItem(selected = tab == index, onClick = { if (tab == index) navigators[index].popToRoot(); tab = index }, icon = { SfIcon(tabIcons[index], 22.dp, if (tab == index) SavantPalette.turf else SavantPalette.inkTertiary) }, label = { Text(title, style = SavantType.smallBold) }, modifier = Modifier.testTag("tab-$title"), colors = NavigationBarItemDefaults.colors(indicatorColor = SavantPalette.surfaceSunk))
                        }
                    }
                },
            ) { padding ->
                Box(Modifier.padding(padding)) {
                    NavStack(navigators[tab]) { route ->
                        when (route) {
                            Route.Root -> Column(Modifier.fillMaxSize()) {
                                HomeTopBar(tabNames[tab])
                                when (tab) { 0 -> StatsScreen(); 1 -> TrendsScreen(); 2 -> TeamsScreen(); else -> CompareScreen() }
                            }
                            is Route.PlayerProfile -> PlayerProfileScreen(route.player)
                            is Route.Team -> TeamScreen(route.abbr)
                            is Route.Metric -> MetricLeadersScreen(route.label, route.category)
                            is Route.Comparison -> PlayerComparisonScreen(route.playerA, route.playerB)
                            is Route.YearCompare -> YearComparisonScreen(route.player)
                            is Route.TeamComparison -> TeamComparisonScreen(route.teamA, route.teamB, route.seasonA, route.seasonB, route.phase)
                            Route.Settings -> SettingsScreen()
                            Route.Glossary -> GlossaryScreen()
                        }
                    }
                }
            }
        }
        StatScoutSheet(trialPitch != null, ::dismissOffer, fullHeight = false) { trialPitch?.let { TrialPitchSheet(it, ::dismissOffer) } }
        StatScoutSheet(paywall != null, ::dismissOffer) { paywall?.let { PaywallScreen(it, ::dismissOffer) } }
    }
}

@Composable
fun HomeTopBar(title: String) {
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val store = LocalGraph.current.subscriptions
    SavantTopBar(title, leading = {
        IconButton({ navigator.push(Route.Settings) }, Modifier.testTag("settings")) { SfIcon("gearshape.fill", 22.dp, Color.White, contentDescription = "Settings") }
    }, trailing = {
        if (!store.isPro) TextAction(store.upgradeCTALabel, SavantType.smallBold, Color.White, { actions.openPaywall(PaywallTrigger.Upgrade) }, Modifier.testTag("upgrade"))
        else Text("PRO", style = SavantType.micro, color = Color.White)
    })
}
