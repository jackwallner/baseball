# Video Analysis & Screen-Match Notes

This document contains extremely detailed notes based on the provided screen recording and narration. It matches the spoken transcription with the visual state of the application and maps these issues directly to the corresponding areas of the codebase.

---

## 1. Onboarding Flow & Aesthetics (0:00 - 1:10)
**Transcription:** *"starting here by going to the baseball app... full onboarding flow... skip up in the top right. This looks fine but it's pretty bland so I really would like if this was more stat baseball subcontent themed stat cast component. We can't use that directly but we can use with the color scheme and the bars and make it look like more of the stat cast baseball subcontent apps and flow... AI loves word signals that's removed all signals and make a rule to never use signals again..."*
**Visual State / Screen Match:** The user is on the initial splash screens / onboarding flow of the "Stat Scout" app. There is a "Skip" button in the top right. The design is described as "bland" and currently features terminology including the word "signals".
**Codebase Mapping:** 
- `StatScout/Views/RootTabView.swift` (or the respective Onboarding View)
- `StatScout/Views/SavantTokens.swift` / `SavantModules.swift` (for theming and colors)
**Actionable Items:**
- **Theming:** Update the onboarding design to closely mimic the visual styling of official Statcast/Savant tools. Utilize their specific color schemes and bar-chart motifs so users immediately recognize the data context.
- **Copywriting:** Perform a project-wide find-and-replace to completely remove the word "signals" from the app's copy.

## 2. Paywall Pitch / Pro Features (1:10 - 1:47)
**Transcription:** *"Pro and lots of trends again kind of AI slop work for a bitch there. We really want to have something that offers the Pro at this point you know some sort of soft paywall not required but some sort of pitch here of that being an option if this person interested... we're going to click play ball"*
**Visual State / Screen Match:** The screen displays a pitch for the "Pro" tier features ("lots of trends"). The user describes the current layout/copy as "AI slop". The screen ends with a "Play Ball" button to enter the main app.
**Codebase Mapping:** 
- `StatScout/Views/PaywallView.swift`
- `StatScout/ViewModels/DashboardViewModel.swift`
**Actionable Items:**
- Implement a "soft paywall" presentation right before the user enters the app (before hitting "Play Ball"). It should not be required to pass, but serve as an early pitch to users while their intent is highest. 

## 3. Dashboard Data & "Last Updated" Bug (1:47 - 2:16)
**Transcription:** *"we can go ahead and see the data here which is awesome. It does seem like the app was last updated yesterday at 6.04 am so that is either that should be wrong. We either have the something wrong with the data backup or that date hasn't refreshed because it should be every night gets refreshed here."*
**Visual State / Screen Match:** The user has entered the main Dashboard. A label displays "Last updated yesterday at 6:04 AM".
**Codebase Mapping:** 
- `StatScout/Views/DashboardView.swift`
- `StatScout/Services/StatcastAPI.swift` (or backend data ingest scripts)
**Actionable Items:**
- Investigate the data refresh logic. The text either visually lags behind the actual database refresh, or the backend script (`backfill_team_data.py` / cron jobs) is failing to update the timestamp. It should reflect a nightly refresh.

## 4. Paywall Tier Selection Bug (2:16 - 2:55)
**Transcription:** *"The monthly yearly and lifetime numbers are wrong there. If we click start free trial we should get this brought up... Similarly here great if I click this doesn't move this selection there which is weird and similarly this lifetime I guess just gave it to me so something weird there."*
**Visual State / Screen Match:** The user is on the Paywall view looking at pricing tiers (Monthly, Yearly, Lifetime). The pricing numbers are incorrect. The user taps different tiers, but the visual selection state (highlight/border) does not move. Tapping "Lifetime" abruptly granted the purchase.
**Codebase Mapping:** 
- `StatScout/Views/PaywallView.swift`
- `StatScout/Services/StoreManager.swift` / `StoreService.swift`
**Actionable Items:**
- Fix the hardcoded or bugged pricing numbers for the tiers.
- Fix the `@State` or `@Binding` property controlling the active visual selection of the subscription tier so tapping a tier highlights it properly.
- Investigate the "Lifetime" purchase flow bypass (likely due to a previous sandbox test, but verify the state handling).

## 5. Metric Leaders Sort & Header UI (2:55 - 3:23)
**Transcription:** *"Here we can see all the players... we can sort by there. I would like an option to change this sort by... also go up or down right now it just has that sort... It's kind of weird how the header bar like changes there and it's kind of odd. It doesn't need to do that"*
**Visual State / Screen Match:** The user is viewing a list of players/metric leaders. They want to be able to sort the stats in both ascending and descending order. As they scroll or interact, the navigation/header bar animates or changes in an erratic, "odd" way.
**Codebase Mapping:** 
- `StatScout/Views/MetricLeadersView.swift`
- `StatScout/Views/StandardStatsLeadersView.swift`
**Actionable Items:**
- Add a toggle to reverse the sort order (ascending vs. descending).
- Remove or refine the dynamic header/navigation bar animation to keep the UI stable while scrolling the player list.

## 6. Year Comparison & Player Comparison UX (3:23 - 4:08)
**Transcription:** *"Year compare 2026 to 2025. This screen could use some work. It looks a bit silly... it's a little hard to read so some sort of cool like overlay or showing the delta difference the two stats bars there and the difference overall change... I should really compare with someone doesn't really work I'm guessing because the years are different"*
**Visual State / Screen Match:** The user is on the Year Comparison screen for a specific player. The current layout makes it hard to quickly parse the differences between the two years. They mention the "Compare with someone" feature is broken.
**Codebase Mapping:** 
- `StatScout/Views/YearComparisonView.swift`
- `StatScout/Views/PlayerComparisonView.swift`
**Actionable Items:**
- Overhaul `YearComparisonView.swift` to visually emphasize the *delta* (change) between years using overlaying bars, +/- indicators, or a cleaner layout, rather than just showing two disconnected stats.
- Fix the `PlayerComparisonView` logic. It currently fails, likely because it struggles to align or handle data across mismatched years.

## 7. Teams Tab: Loading Lag & Star/Crash Bug (4:08 - 5:05)
**Transcription:** *"If I go to Teams there seems to be some bug when I first go to Teams that it initializes and bugs out here so need to make sure that we're having some sort of loading screens... I can star a team that I want to see and looks like when I do that it also freezes so starring a team freezes... looks like I might actually crash the app to star a team"*
**Visual State / Screen Match:** The user taps the "Teams" tab in the bottom navigation. The app stutters/lags heavily upon entry. The user then attempts to "star" (favorite) a team, which completely freezes and subsequently crashes the application.
**Codebase Mapping:** 
- `StatScout/Views/TeamsView.swift`
- `StatScout/Views/TeamView.swift`
- Data Models / CoreData / SwiftData holding the "starred" state.
**Actionable Items:**
- **Performance:** Implement lazy loading (`LazyVStack`/`LazyVGrid`) or a proper loading state screen for the `TeamsView` so it does not block the main thread initializing all teams at once.
- **Crash Fix:** Investigate the action triggered by the "star" button. It is causing a severe thread block or memory leak, resulting in an app freeze and crash. 

## 8. General UX: Metrics & Minimum Qualification (5:05 - end)
**Transcription:** *"one way to see standard stats and stats out stat cast stats there and click in here one big little more obvious that if I click into one of these things I can see the highest or lowest... it would also be nice to be able to set a on the metrics some sort of minimum qualification component and that way I'm not getting overblown with people that haven't played before"*
**Visual State / Screen Match:** The user is exploring different stat categories. They note that the difference between Standard Stats and Statcast Stats could be clearer, and it isn't obvious that tapping a metric navigates to a leader list.
**Codebase Mapping:** 
- `StatScout/Views/DashboardView.swift`
- `StatScout/Views/MetricRankingView.swift`
**Actionable Items:**
- **UI Clarity:** Make the distinction between Standard and Statcast stats more prominent. Add visual indicators (like chevrons `>`) to make it obvious that metric rows are tappable navigation links.
- **Data Filtering:** Implement a "Minimum Qualification" filter (e.g., minimum At Bats, Innings Pitched, or Batted Ball Events) for the leaderboards. This will prevent players with only 1 or 2 total events from cluttering the top/bottom of the statistical rankings.

---

# The Vibe: What Needs to be Fixed

*(This section summarizes the high-level intent, aesthetic direction, and general "vibe" the user expects another AI to implement.)*

**1. "Statcast" Authenticity:**
The application needs to shed its "bland" and generic "AI slop" feeling. The user wants the app to feel like an authentic, highly-polished extension of the official Baseball Savant/Statcast ecosystem. This means utilizing their recognizable color schemes, clean bar charts, and authoritative data presentation. Remove any hallucinated terminology (like the word "signals").

**2. Seamless but Present Monetization:**
The Paywall needs to be a "soft pitch" seamlessly integrated right when the user's interest is highest (onboarding). It shouldn't feel like a hard block, but a natural option. More importantly, the paywall UI itself *must* be functional—currently, selecting different tiers does not provide visual feedback, and the pricing data looks incorrect.

**3. Data Legibility over Raw Numbers:**
On the comparison screens (Year-over-Year and Player vs Player), simply displaying two columns of stats is considered "silly" and "hard to read." The vibe requires a UX shift towards highlighting the *Delta*. The user wants to see the visual difference (overlays, growth/decline indicators) at a glance, rather than having to do the math themselves. 

**4. Performance and Stability are Paramount:**
The core functionality works, but the app feels fragile in key areas. The "Teams" tab locking up the UI because it lacks a loading state, and the app outright crashing when trying to "star" a team, severely hurts the premium feel. The app needs to be buttery smooth, relying on lazy loading and proper state management to prevent main-thread blocking.

**5. Meaningful Leaderboards (Quality Control):**
The leaderboards currently feel "overblown" with irrelevant data because there are no minimum qualifiers. The vibe requires the data to be treated like real baseball leaderboards—players need a minimum number of events (PAs, Pitches, etc.) to qualify, so the stats reflect actual, meaningful baseball trends.