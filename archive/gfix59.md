# StatScout UX & Premium Feature Review

This document contains an exhaustive user-perspective review of the StatScout iOS application, focusing on user experience, UI friction, and particularly the implementation and flow of the "Pro" premium features. 

## 1. Premium Feature Experience: Friction & Inconsistencies

The app struggles with a consistent paywall strategy, oscillating between giving away features for free by accident and aggressively paywalling the user on the very first interaction.

*   **The "Leaky" Paywalls (Teams & Metric Leaderboards):**
    *   **Pain Point:** The Paywall explicitly lists "Team Rosters & Rankings" and "Metric Leaderboards" as Pro features. Navigating to the "Teams" or "Metrics" tabs as a free user displays a "Pro Upsell Banner" at the top of the screen. However, **the features are not actually locked**. A free user can simply scroll past the banner, view all 30 teams, click into team rosters, and view all metric leaderboards. 
    *   **Impact:** Confusing UX. Users might wonder why they are being nagged to pay for something they are already using, severely undermining the perceived value of the Pro tier.
*   **Aggressive Default Paywall on Player Profiles:**
    *   **Pain Point:** When a user taps on a player to view their profile, the app defaults to the "Percentiles" tab. For a free user, this entire tab is locked behind a massive paywall block ("Unlock Pro to see full metric breakdowns"). 
    *   **Impact:** The user's very first interaction after searching for a player is hitting a hard paywall wall, offering zero initial value. 
    *   **Improvement:** For free users, the default tab should ideally be "Standard Stats" so they see actual data upon tapping a player. Alternatively, the "Percentiles" tab should show a "teaser" (e.g., top 2 metrics) before cutting off the rest of the list with a paywall inline.
*   **"Year Compare" Tab Interaction:**
    *   **Pain Point:** The "Year Compare" tab includes a nice small lock icon. However, tapping it doesn't switch the view; it abruptly throws a full-screen modal paywall sheet. 
    *   **Impact:** While standard, it feels a bit like a trap. A smoother UX would be allowing the tab to switch, but rendering the paywall *inside* the tab's content area, letting the user understand they are in the comparison section but need to unlock it.

## 2. Navigation, State & Flow Issues

*   **Severe Season Selection Disconnect in Player Profiles:**
    *   **Pain Point:** There is a global season picker on the Dashboard. However, inside the `PlayerProfileView`, there is a *second, local* season picker specifically within the "Percentiles" tab. Changing this local season picker updates the percentiles, but **it does not update the "Standard Stats" tab**. The standard stats tab hardcodes `player.standardStats` instead of using the dynamically selected `displayedPlayer` for the chosen season.
    *   **Impact:** If a user views Aaron Judge, changes the percentiles season to 2023, and then taps the "Standard Stats" tab, they will still be looking at 2026 standard stats. This data mismatch makes the app feel broken and untrustworthy.
*   **Hidden Sorting Functionality:**
    *   **Pain Point:** On the Dashboard, users can change the sorting metric and toggle Ascending/Descending. However, this menu is attached to the `LeaderboardTableHeader`. There is no visual affordance (like an arrow, a chevron, or a filter icon) to indicate that this header is an interactive menu. 
    *   **Impact:** A huge portion of users will never discover that they can sort the leaderboard by specific metrics like "Sprint Speed" or "xwOBA".
*   **Lack of Swipe Gestures in Profile:**
    *   **Pain Point:** The `PlayerProfileView` uses custom pill buttons for its three internal tabs (Percentiles, Standard Stats, Year Compare). Users naturally try to swipe left and right on the screen to page between these views, but the app forces them to reach up and tap the buttons.
*   **Awkward "Clear" Search Placement:**
    *   **Pain Point:** In the `TeamsView`, the "Clear" button for the search functionality is placed up in the `SavantSectionBar` header, rather than acting as a standard `(x)` button inside the actual `SearchField`. This forces the user to look away from the keyboard/input area to clear their search.

## 3. UI Polish & Visual Friction

*   **Jarring Loading Spinner:**
    *   **Pain Point:** On initial launch (`DashboardView`), if the app needs even a fraction of a second to load the local cache, it displays a massive 1.5x scaled `ProgressView`. 
    *   **Impact:** This causes an ugly UI "flash" or jump before the real data paints. A skeleton loading state or keeping the UI stable while showing a smaller inline indicator would feel much more premium.
*   **Paywall Pricing Hierarchy:**
    *   **Pain Point:** The Paywall displays three tiers: Yearly, Monthly, and Lifetime. "Yearly" is selected by default and marked "Best Value", while Lifetime is below it. If Lifetime is the intended primary anchor (as older code suggests), the layout doesn't emphasize it. The visual weight is heavily on the recurring subscriptions.
*   **Empty States During Data Outages:**
    *   **Pain Point:** If the API fetch fails and the cache is empty, the app shows a generic "Data Error" view with a "Retry" button. If the `selectedCategory` has no players, it just says "No players in category". The language is highly technical ("Data format changed") rather than user-friendly ("We're having trouble fetching the latest stats").

## Summary Recommendations
1. **Enforce the Paywalls:** Actually restrict access to `TeamsView` and `MetricLeadersView` if they are intended to be Pro features, or remove the banners and update the Paywall copy if they are meant to be free.
2. **Fix the Season State Bug:** Ensure the `PlayerProfileView` shares a single `activeSeason` across *all* its tabs so Standard Stats and Percentiles are always looking at the same year.
3. **Soften the Profile Entry:** Stop hitting free users with a paywall the second they open a player profile. Default to Standard Stats, or show teaser data.
4. **Add Visual Cues:** Add a dropdown chevron to the Dashboard sort header so users know it's tappable.