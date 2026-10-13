package com.jackwallner.baseball

import android.content.Intent

/** All test unlocks and launch controls are absent from release builds. */
object DebugLaunchOptions {
    var launchTab: Int? = null
        private set
    fun apply(graph: AppGraph, intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getBoolean("resetAll")) graph.defaults.keys().forEach(graph.defaults::remove)
        if (extras.getBoolean("onboarded")) graph.defaults.putBoolean("hasCompletedOnboarding", true)
        if (extras.getBoolean("forcePro")) graph.subscriptions.forceProForDebug()
        if (extras.getBoolean("uiTest")) graph.review.isAutomationRun = true
        if (extras.containsKey("tab")) launchTab = extras.getInt("tab")
    }
}
