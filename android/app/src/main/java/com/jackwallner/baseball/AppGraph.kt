package com.jackwallner.baseball

import android.content.Context
import androidx.compose.runtime.*
import com.jackwallner.baseball.data.*
import kotlinx.coroutines.MainScope

class AppGraph(context: Context) {
    val appContext = context.applicationContext
    val scope = MainScope()
    val defaults = SharedPreferencesStore(appContext)
    val clock = SystemAppClock()
    val review = ReviewPromptTracker(defaults, clock)
    val diagnostics = ConversionDiagnostics(defaults, clock)
    val subscriptions = SubscriptionService(appContext, defaults, diagnostics)
    val favorites = FavoritesStore(defaults)
    val paywallGate = PaywallGate()
    var pendingTab by mutableStateOf<String?>(null)
    val api: StatcastProviding = StatcastApi(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
    var feedOverride: StatcastProviding? = null
    val dashboard by lazy { DashboardViewModel(appContext, feedOverride ?: api, scope) }
}
