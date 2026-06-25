# StatScout User-Facing Bug Report

> Written from the perspective of an end-user testing the app. These are the problems I would actually encounter while using StatScout.

---

## CRITICAL: The Numbers Are Wrong

### C-1: Every metric says "100 PCTL" instead of the actual stat value
- **Where I see it:** Tapping any player card → the metric bars under "Hitting", "Pitching", etc.
- **What I see:** "xwOBA: 100 PCTL" or "Avg EV: 99 PCTL"
- **What I expect:** "xwOBA: .463" or "Avg EV: 96.2 mph" — the actual baseball numbers I came for.
- **Why it matters:** This is the entire value proposition of the app. Baseball Savant shows me the stat *and* the percentile. Right now I only get the percentile. I can't tell if .350 wOBA is good or bad without cross-referencing another app.
- **Root cause (code):** `backend/ingest.py:87` writes the percentile into the `value` field instead of the raw stat.

### C-2: The app silently shows fake/demo data when the real feed is broken
- **Where I see it:** Opening the app with no internet, or after the nightly refresh fails.
- **What I see:** Aaron Judge, Shohei Ohtani, Bobby Witt Jr., Paul Skenes — always the same four players, always the same stats.
- **What I expect:** An error message like "Can't connect to Statcast feed" or "Data is stale — last updated yesterday."
- **Why it matters:** I have no idea whether I'm looking at real 2026 season data or placeholder mockups from development. I might make fantasy/wager decisions based on stale or fake numbers.
- **Root cause (code):** `DashboardViewModel.load()` catches every error and loads `SampleData.players` with a single yellow banner.

### C-3: Team search and team rosters are completely broken
- **Where I see it:** The "Teams" chip row, tapping any team name, or searching "NYY".
- **What I see:** Every player is listed under team "MLB". The team chips show "MLB" only. Tapping it shows every player in one giant list. Search for "NYY" returns nothing because backend set every team to "MLB".
- **What I expect:** Actual 30 MLB teams, team logos/colors, roster pages with just that team's players.
- **Why it matters:** I downloaded this to track my team's players. I can't.
- **Root cause (code):** `backend/ingest.py:106` hardcodes `"team": "MLB"` for every player.

---

## HIGH: Missing Features That Feel Like Bugs

### H-1: There is no way to refresh the data
- **Where I see it:** The main dashboard.
- **What I try:** Pulling down to refresh (standard iOS gesture). Nothing happens. No refresh button. No "Last updated: 2 hours ago" timestamp on the main screen.
- **What I expect:** Pull-to-refresh, or at minimum a visible timestamp so I know if I'm looking at yesterday's data or last week's.
- **Why it matters:** Baseball stats change daily. If I check the app at 11am and the nightly job failed, I'm looking at yesterday's leaderboard without knowing it.

### H-2: "Recent Games" section never appears
- **Where I see it:** Any player profile page.
- **What I see:** The profile shows percentile bars, then ends. No game log. No trend graph.
- **What I expect:** A "Recent Games" section with last night's game, opponent, and how their percentiles moved.
- **Why it matters:** The app promises "game-to-game trends and context" in the subtitle. It's literally in the code (`PlayerProfileView.swift:50`) but the backend never sends game data, so the section is invisible.

### H-3: The Random Player button sometimes does nothing
- **Where I see it:** Dashboard, below the search bar.
- **What I see:** I tap "Random Player" and nothing happens. No animation, no feedback, no player sheet opens.
- **What I expect:** A random player profile opens every time, or the button is disabled with a "Loading players..." label.
- **Why it matters:** Feels broken. I don't know if I mis-tapped or if the app crashed.

### H-4: Settings is just an About page with a gear icon
- **Where I see it:** Tapping the gear in the top right.
- **What I see:** Static text: "Nightly Refresh", "Last Updated", and an app description.
- **What I expect:** Actual settings. Toggle for dark/light mode, data source selection, cache clear, contact/support, privacy policy, sign out if there's ever auth.
- **Why it matters:** The gear icon is the universal symbol for "change how this app works." Right now it's false advertising.

### H-5: No player photos anywhere
- **Where I see it:** Player cards, leaderboard rows, profile headers.
- **What I see:** Text only. Name, team, position, percentile number.
- **What I expect:** MLB headshot next to the name, like every other baseball app (Baseball Savant, MLB app, FanGraphs).
- **Why it matters:** Visual recognition is instant. Reading "Paul Skenes" takes effort; seeing his face is instant. The backend already has image URLs — the app just doesn't show them.

### H-6: Inconsistent red/blue colors for percentiles
- **Where I see it:** Comparing the Featured card vs Leaderboard row vs Profile page.
- **What I see:** A 75th-percentile metric is red in the Featured card, white/gray in the Leaderboard row, and red again on the profile page. A 25th-percentile is blue on the card but white on the leaderboard.
- **What I expect:** Consistent Baseball Savant colors: ≥75 = red (elite), ≤25 = blue (poor), everything in between = neutral gray.
- **Why it matters:** I use color as a quick visual cue. Inconsistent colors force me to read the number every time.

### H-7: The Metric Leaders page can show blank nothingness
- **Where I see it:** Tapping "Metric Leaders" from the dashboard.
- **What I see:** A header, a subtitle, then empty white space. No "No data yet" message. No skeleton loaders.
- **What I expect:** Either a populated list, or a friendly empty state explaining why.
- **Why it matters:** I can't tell if it's still loading, if the data failed, or if the feature isn't built yet.

### H-8: Team roster page is also blank if a team has no players
- **Where I see it:** Tapping a team chip.
- **What I see:** Header with team name and "0 players", then empty space below.
- **What I expect:** "No players tracked for this team yet" or a back button.
- **Why it matters:** See H-7 — same confusion.

---

## MEDIUM: Annoying UX / Polish Issues

### M-1: No share button despite the app generating share text
- **Where I see it:** Player profile page.
- **What I see:** Nothing. No share icon. No "Copy link".
- **What I expect:** A share sheet so I can text a friend: "Aaron Judge · xwOBA .463, 100th percentile"
- **Why it matters:** The code already builds this exact sentence (`shareSummary`) but never exposes a button. Media/fan use case (the target audience) requires easy sharing.

### M-2: Every metric bar has a useless "50" tick mark in the middle
- **Where I see it:** Player profile percentile bars.
- **What I see:** A thin vertical white line at the 50% width mark on every bar.
- **What I expect:** Either a labeled 50th percentile reference, or nothing. A random line with no label is visual noise.
- **Why it matters:** Baseball Savant doesn't show this. It distracts from the actual percentile fill.

### M-3: "Done" button required to close every sheet — no swipe gesture
- **Where I see it:** Every player profile, team view, settings, metric leaders.
- **What I try:** Swiping down to dismiss (standard iOS sheet behavior). Nothing happens. I must find and tap "Done" in the top-right corner.
- **What I expect:** Swipe-to-dismiss on sheets, or at least a drag indicator at the top.
- **Why it matters:** One-handed use is hard when the dismiss button is in the top-right corner. This is especially frustrating on larger phones.

### M-4: Category filter chips don't show counts
- **Where I see it:** Dashboard, below search.
- **What I see:** "All", "Hitting", "Pitching", "Fielding", "Running" chips. No numbers.
- **What I expect:** "Hitting (247)" or a small badge so I know how many players qualify.
- **Why it matters:** I might tap "Fielding" and see 3 players. A count prevents that disappointment.

### M-5: Featured players horizontal scroll has no page dots or count
- **Where I see it:** The "Featured" carousel on the dashboard.
- **What I see:** 5 player cards I can swipe through. No indication of how many there are or which one I'm on.
- **What I expect:** Page control dots, or "1 / 5" indicator.
- **Why it matters:** I don't know if there are 5 featured players or 50. I might miss the last one.

### M-6: "Random Player" and "Metric Leaders" buttons are awkwardly placed
- **Where I see it:** Dashboard, between search and Featured section.
- **What I see:** A red "Random Player" pill on the left, a "Metric Leaders" pill on the right.
- **What I expect:** Primary actions like "Metric Leaders" to be more prominent, or both to be in a toolbar/navigation area rather than floating in the scroll content.
- **Why it matters:** The layout feels like a draft. Important navigation controls are mixed with content.

### M-7: The app doesn't work in light mode
- **Where I see it:** If I have iOS set to Light Appearance.
- **What I see:** White text on near-white backgrounds. Completely unreadable.
- **What I expect:** Either the app forces dark mode (like Netflix), or it properly adapts to light mode with dark text.
- **Why it matters:** Right now the app is unusable for anyone not in dark mode. They'll delete it immediately.

### M-8: Player names with accents or suffixes may display incorrectly
- **Where I see it:** Any roster with international players or Jr./III suffixes.
- **What I see:** (Not visible in current sample data, but predicted from backend logic)
- **What I expect:** "Elly De La Cruz" not "De La Cruz, Elly, Jr."
- **Why it matters:** Name formatting is basic table-stakes for a baseball app.

### M-9: Position labels are too generic
- **Where I see it:** Player cards and profile headers.
- **What I see:** "Hitter", "Pitcher", "Two-way"
- **What I expect:** "RF", "SP", "DH/SP", "SS" — actual baseball positions.
- **Why it matters:** I want to know if a player is a shortstop or a designated hitter. "Hitter" is meaningless.

### M-10: No search result empty state
- **Where I see it:** Typing a name in the search bar that doesn't match.
- **What I see:** The entire dashboard disappears. Just blank space below the search bar.
- **What I expect:** "No players found for 'xyz'" with a suggestion to check spelling or browse teams.
- **Why it matters:** Blank space looks like a crash.

### M-11: Game trend delta numbers have no legend
- **Where I see it:** Player profile → Recent Games (when visible in sample data).
- **What I see:** "+3" in green or "-1" in orange.
- **What I expect:** A tooltip or label explaining "+3 = percentile improved by 3 points since last game"
- **Why it matters:** I can guess, but explicit labels remove ambiguity.

### M-12: The "Percentile" badge in the leaderboard is tiny
- **Where I see it:** Leaderboard rows.
- **What I see:** A 52×52 square with "92" and "PCTL" in 8pt font.
- **What I expect:** Larger, more readable numbers, or the Baseball Savant-style large percentile circle.
- **Why it matters:** This is the primary sort metric. It shouldn't require squinting.

---

## LOW: Minor Friction / Missed Opportunities

### L-1: No onboarding for first-time users
- **Where I see it:** First app open.
- **What I see:** Dashboard with data already there. No explanation of what percentiles mean, what "xwOBA" stands for, or how often data updates.
- **What I expect:** A 2–3 card onboarding explaining the app is Baseball Savant percentiles for mobile, updated nightly.

### L-2: No favorite/bookmark players
- **Where I see it:** Dashboard, player profiles.
- **What I see:** No star, heart, or pin button on any player.
- **What I expect:** A "My Players" section at the top of the dashboard for my fantasy team or favorite players.

### L-3: No league/division context on team chips
- **Where I see it:** Team chip row.
- **What I see:** "NYY", "LAD", "BOS" as plain text pills.
- **What I expect:** Team logos or colors so I can scan faster.

### L-4: Metric labels are abbreviated without tooltips
- **Where I see it:** Metric bars.
- **What I see:** "xwOBA", "xSLG", "OAA", "Barrel%"
- **What I expect:** Tap-and-hold or an info button showing "Expected Weighted On-Base Average — measures quality of contact + walk/strikeout outcomes."
- **Why it matters:** Casual fans don't know what xwOBA is. The app is marketed to "fans and media" but assumes advanced-stat literacy.

### L-5: The "StatScout" title is redundant
- **Where I see it:** Dashboard navigation bar and the hero header.
- **What I see:** "StatScout" in the nav bar AND "StatScout" in the giant hero card below it.
- **What I expect:** One or the other. The hero card should show today's date or data freshness, not repeat the app name.

### L-6: No player comparison feature
- **Where I see it:** Player profiles.
- **What I see:** One player at a time.
- **What I expect:** A "Compare" button to pit two players head-to-head on the same metrics, side by side.
- **Why it matters:** Fantasy trade decisions and sports arguments are the core use case for percentile data.

### L-7: No percentile history over time
- **Where I see it:** Player profile.
- **What I see:** Current percentiles only.
- **What I expect:** A sparkline or mini-chart showing how a player's xwOBA percentile moved over the last 30 days.
- **Why it matters:** "Is he trending up or down?" is more valuable than a single snapshot.

### L-8: The sample data has the same players every launch
- **Where I see it:** Offline mode or when the backend fails.
- **What I see:** Judge, Ohtani, Witt, Skenes. Always the same four.
- **What I expect:** A rotating set of interesting players, or a clear "Demo Mode" watermark.
- **Why it matters:** After 3 launches it feels like a toy, not a real app.

---

## User Bug Count Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 3 |
| HIGH     | 8 |
| MEDIUM   | 12 |
| LOW      | 8 |
| **Total**| **31** |

---

## User Story: A First-Time Session

1. I open the app. It looks slick — dark theme, baseball colors. **(Good)**
2. I see Aaron Judge's card. I tap it. **(Good)**
3. I see "xwOBA: 100 PCTL". Wait, what is his actual xwOBA? I don't know. **(CRITICAL-1)**
4. I swipe back — nope, have to find the Done button. **(M-3)**
5. I search "NYY" — nothing. Search "Yankees" — nothing. I look at the team chips — only "MLB" appears. **(CRITICAL-3)**
6. I pull down to refresh — nothing happens. I wonder if the data is from today. **(H-1)**
7. I go to Settings to check. It tells me the app refreshes nightly but doesn't say when the last refresh actually happened. **(H-4)**
8. I try to share Aaron Judge's stats — no share button. **(M-1)**
9. I switch my phone to light mode because I'm outside. The app becomes unreadable. **(M-7)**
10. I delete the app. **(End of story)**

---

## Appendix: Project Setup Issues That Break the App Before I Even See It

These aren't bugs I hit while using the app — they're build/pipeline problems that prevent the app from shipping or make it unstable.

### C-4: The app might get rejected from the App Store entirely
- **What it means for me:** I search the App Store for "StatScout" and it's not there.
- **What's broken:** There's no `PrivacyInfo.xcprivacy` file in the project. Apple now requires this privacy manifest for all iOS 17+ apps that use networking (which this app does — it calls Supabase).
- **Impact:** App Store Connect will reject the binary during upload. I never get to download it.

### H-9: The developers are shipping code with zero automated tests
- **What it means for me:** Every update is a gamble. A refactoring of the search logic or the percentile math could silently break the leaderboard sorting, and nobody catches it before it hits my phone.
- **What's broken:** The Xcode project has no unit test target and no UI test target. None. Not even a single test file.
- **Impact:** Higher chance of regressions in every release. The "top 5 featured players" could display in wrong order, or search could return nothing, and it only gets discovered by users.

### H-10: The app is built with an old Xcode project format
- **What it means for me:** When the developer opens the project in a modern Xcode (15 or 16), they get a migration prompt. If they click the wrong thing, build settings change unpredictably. The build might use outdated compiler defaults that miss modern Swift 6.0 safety checks.
- **What's broken:** `LastUpgradeCheck = 1430` in the project file — that's Xcode 14.3 from 2023. The app targets iOS 17 and Swift 6.0.
- **Impact:** Inconsistent builds between developers; potential runtime crashes from missed concurrency diagnostics.

### H-11: The release build is signed like a debug build
- **What it means for me:** The TestFlight / App Store upload might fail, causing delayed releases. If it does upload, the signing certificate might not be the hardened distribution profile Apple requires for store builds.
- **What's broken:** Both Debug and Release configurations use `CODE_SIGN_IDENTITY = "iPhone Developer"`. Release should use `"iPhone Distribution"`.
- **Impact:** Fragile CI pipeline; potential App Store signing rejection.

### M-13: No custom Info.plist means missing app metadata
- **What it means for me:** The app might lack a custom URL scheme, deep-link support, or required privacy usage descriptions (e.g., "This app uses the network to load baseball statistics"). If Apple ever requires a specific plist key for Supabase/REST apps, it can't be added declaratively.
- **What's broken:** `GENERATE_INFOPLIST_FILE = YES` auto-creates the plist, but there's no actual `Info.plist` file in the project to edit.
- **Impact:** Inability to declare custom URL schemes, background modes, or required API usage strings without switching build systems mid-project.

### M-14: Provisioning profiles are a black box
- **What it means for me:** If the sole developer's Mac dies or they get a new machine, the TestFlight upload script (`testflight.sh`) will fail with cryptic signing errors. The project has no `PROVISIONING_PROFILE_SPECIFIER` set.
- **What's broken:** The build relies entirely on Xcode's "automatic provisioning" magic. This is fine for local development but breaks in CI or on new hardware.
- **Impact:** Unreproducible builds; bus factor of 1; new contributors can't archive the app.

### M-15: Entitlements are missing — no push notifications, no iCloud
- **What it means for me:** Features I'd expect in a modern sports app (push alerts when my favorite player's percentile jumps, iCloud sync of my followed players) are impossible to enable.
- **What's broken:** No `.entitlements` file is referenced in the project. The app has zero capability declarations.
- **Impact:** Even if the developers write the code for push notifications later, they can't toggle the capability without regenerating the project and reconfiguring Apple Developer Portal.

### L-9: Empty Swift Package Manager scaffolding
- **What it means for me:** Nothing directly, but it signals the project was set up hastily. If they want to add a real image caching library (e.g., Kingfisher) or a networking layer (e.g., Alamofire), the SPM workspace structure isn't ready.
- **What's broken:** `packageProductDependencies = ( );` is empty, and there's an empty `xcshareddata/swiftpm/configuration/` directory.
- **Impact:** Future dependency additions require manual Xcode GUI work, which conflicts with the automated `xcodegen generate` workflow.
