package com.jackwallner.baseball

import android.content.Intent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private fun launch(pro: Boolean = false, onboarded: Boolean = true): ActivityScenario<MainActivity> {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("resetAll", true); putExtra("onboarded", onboarded); putExtra("forcePro", pro); putExtra("uiTest", true)
        }
        return ActivityScenario.launch(intent)
    }
    private fun awaitPlayers() { compose.waitUntil(240_000) { compose.onAllNodesWithTag("leaderboard").fetchSemanticsNodes().isNotEmpty() && compose.onAllNodes(hasTestTagPrefix("player-")).fetchSemanticsNodes().isNotEmpty() } }
    private fun hasTestTagPrefix(prefix: String) = SemanticsMatcher("test tag starts with $prefix") { node -> node.config.getOrElse(androidx.compose.ui.semantics.SemanticsProperties.TestTag) { "" }.startsWith(prefix) }

    @Test fun firstRunCompletesAndCurrentPlayersLoad() {
        launch(onboarded = false).use {
            compose.onNodeWithTag("onboarding-continue").performClick()
            compose.onNodeWithTag("onboarding-continue").performClick()
            compose.onNodeWithTag("onboarding-continue").performClick()
            awaitPlayers()
            compose.onNodeWithTag("tab-Stats").assertIsDisplayed()
        }
    }
    @Test fun followingPersistsAndBackReturnsToBoard() {
        launch().use {
            awaitPlayers()
            compose.onAllNodes(hasTestTagPrefix("player-")).onFirst().performClick()
            compose.onNodeWithTag("follow-player").performClick()
            compose.onNodeWithTag("follow-player").assertTextContains("Following")
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("board-Following").performClick()
            compose.onAllNodes(hasTestTagPrefix("player-")).onFirst().assertIsDisplayed()
        }
    }
    @Test fun fullHistoryLoadsWithoutExhaustingThePhoneHeap() {
        launch(pro = true).use {
            awaitPlayers()
            val graph = ApplicationProvider.getApplicationContext<StatScoutApplication>().graph
            compose.waitUntil(240_000) {
                !graph.dashboard.historyLoading && graph.dashboard.players.count { (it.season ?: 0) < 2026 } == 14032
            }
            compose.onNodeWithTag("tab-Stats").assertIsDisplayed()
            org.junit.Assert.assertNull(graph.dashboard.historyError)
        }
    }
    @Test fun freeComparisonOffersUpgradeAndCloses() {
        launch().use {
            compose.onNodeWithTag("tab-Compare").performClick()
            compose.onNodeWithTag("unlock-statscout_paywall_player_comparison").performClick()
            compose.waitUntil(15_000) { compose.onAllNodesWithText("StatScout+", substring = true).fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("paywallClose").performClick()
            compose.onNodeWithTag("tab-Compare").assertIsDisplayed()
        }
    }
    @Test fun proCanOpenTeamsTrendsAndSettings() {
        launch(pro = true).use {
            awaitPlayers()
            compose.onNodeWithTag("tab-Teams").performClick()
            compose.onNodeWithTag("teams-list").performScrollToNode(hasTestTag("team-NYY"))
            compose.onNodeWithTag("team-NYY").performClick()
            compose.onNodeWithTag("team-page").assertIsDisplayed()
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("tab-Trends").performClick()
            compose.onNodeWithTag("trends-list").assertIsDisplayed()
            compose.onNodeWithTag("settings").performClick()
            compose.onNodeWithTag("settings-page").assertIsDisplayed()
        }
    }
}
