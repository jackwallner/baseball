package com.jackwallner.baseball

import android.content.Intent

/** Release and QA accept no test unlocks or fixture feeds. */
object DebugLaunchOptions {
    val launchTab: Int? = null
    fun apply(graph: AppGraph, intent: Intent?) = Unit
}
