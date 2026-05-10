# StatScout Comprehensive UX Review — cfix59

> Exhaustive user-perspective audit. Every pain point a real user would experience, from first launch through daily use. No code edits — just findings.

---

## 🔴 Critical: The "First Tap Is a Paywall" Problem

**File:** `StatScout/Views/PlayerProfileView.swift` (line ~264-275)

The single most damaging UX pattern in the app. A user searches for a player, taps their name, and lands on the **Percentiles** tab — which for free users shows only an overall percentile badge and an "Unlock Pro" button. Every other metric row is hidden.

**What the user experiences:**
- Opens app → searches "Judge" → taps Aaron Judge → immediately sees a paywall wall
- The very first interaction after search is a hard sales pitch
- User hasn't seen ANY premium content yet — they're being asked to pay for something invisible
- Standard Stats tab has data but it's not the default tab

**What should happen:**
- Free users should default to the Standard Stats tab where they can see real data
- Alternatively, show the top 2-3 metrics as a teaser with an inline "See all 12 metrics → Unlock Pro" divider
- The current pattern says "this app gives me nothing unless I pay"

---

## 🔴 Paywall Leakage: Features Advertised as Pro Are Actually Free

Three Pro-gated views show upsell banners but **the content is not actually blocked**:

| View | What the Paywall Says | What Actually Happens |
|------|----------------------|----------------------|
| `TeamsView` | "Team Rosters & Rankings" is Pro | Banner at top, but scroll past it and all 30 teams + rosters are fully accessible |
| `MetricLeadersView` | "Metric Leaderboards" is Pro | Banner at top, but all metric leaders are fully accessible |
| `StandardStatsLeadersView` | Listed in paywall as Pro feature | Banner at top, but all stat leaderboards are fully accessible |

**What the user experiences:**
- Sees a banner saying "Unlock Pro to browse team rosters"
- Scrolls past it and... browses team rosters anyway
- Thinks: "Why am I being nagged to pay for something I can already use?"
- **Erodes trust.** User questions whether ANY Pro feature is actually gated.

**What should happen:**
Pick one strategy and commit:
1. **Gate them:** Actually block content below a blur/fade with a CTA to unlock, OR
2. **Free them:** Remove the banners and update the paywall copy to match what's actually gated

---

## 🔴 Player Profile Season Disconnect (Data Integrity Bug)

**File:** `StatScout/Views/PlayerProfileView.swift`

The `PlayerProfileView` has a local season picker inside the Percentiles tab that lets users pick a different year. But the Standard Stats tab does **not** respect this selection:

- **Percentiles tab** (line ~221): Uses `displayedPlayer`, which picks from `history` based on `selectedPercentileSeason`
- **Standard Stats tab** (line ~299): Uses `player.standardStats` — the original player object, which always shows the season the user navigated from (typically the dashboard's current season)

**What the user experiences:**
- Opens Aaron Judge profile → sees 2026 data
- Changes Percentiles season to 2023 → sees 2023 percentile data ✓
- Taps "Standard Stats" tab → still sees 2026 standard stats ✗
- User thinks: "This app is broken. The data doesn't match."

**What should happen:**
The Standard Stats tab should use `displayedPlayer.standardStats` (or the equivalent player from history for the selected season), not `player.standardStats`.

---

## 🔴 Year Compare Lock Is a Trap

**File:** `StatScout/Views/PlayerProfileView.swift` (lines ~139-140)

The Year Compare tab button shows a lock icon. Tapping it **does not switch tabs** — it immediately fires a full-screen paywall sheet.

**What the user experiences:**
- Sees "Year Compare" tab with a lock icon
- Taps it to see what Year Compare is
- Gets a paywall instead
- Still doesn't know what Year Compare does
- Feels tricked

**What should happen:**
1. Switch to the Year Compare tab first
2. Show a blurred preview or a "What is Year Compare?" card with a sample
3. Put the "Unlock Pro" CTA inside the tab content, not as a modal-trap on the tab button
4. Let users understand the value before being asked to pay

---

## 🔴 Silent Purchase Dismissal (No Confirmation)

**File:** `StatScout/Views/PaywallView.swift` (line ~144)

When a purchase succeeds, the paywall sheet dismisses with zero confirmation. No checkmark, no "Welcome!", no haptic, no indication that money was spent.

**What the user experiences:**
- Taps "Continue — $14.99"
- Sees "Processing..." for ~2 seconds
- Sheet closes
- Thinks: "Did it work? Was I charged? Is Pro unlocked?"

**What should happen:**
- Show a confirmation animation (checkmark, "Pro Unlocked")
- Brief highlight reel of now-available features
- "Manage Subscription" link
- Haptic feedback on success

---

## 🔴 Player Headshots Advertised as Pro But Not Actually Gated

**File:** `StatScout/Views/PaywallView.swift` (line ~100)

The paywall lists "Player Headshots" as a Pro feature. But `PlayerHeadshot` loads for all users everywhere — leaderboard rows, player profiles, metric leaders, team rosters. There is zero `store.proStatus` check anywhere in the headshot loading path.

**What the user experiences:**
- Free user sees headshots everywhere
- Opens paywall → reads "Player Headshots — Official MLB headshots on every card"
- Thinks: "Wait, I already see headshots. Is this a scam?"
- **Direct trust erosion.**

**What should happen:**
Either actually gate headshots (show initials fallback for free users) or remove headshots from the paywall feature list entirely. Don't sell what you're already giving away.

---

## 🟡 High Priority

### No Subscription Management

**File:** `StatScout/Views/SettingsView.swift`

The About/Settings view shows "Pro Unlocked" or "Free Version" but zero subscription details:
- No renewal date
- No plan type (monthly/yearly/lifetime)
- No "Manage Subscription" link to App Store subscriptions (`https://apps.apple.com/account/subscriptions`)
- No cancellation or upgrade path

**User pain:** "When does my yearly plan renew? Can I cancel? How do I switch to monthly?"

### Dashboard Sort Is Invisible

**File:** `StatScout/Views/DashboardView.swift` (line ~149)

The sort function is a `Menu` attached to `LeaderboardTableHeader`. The header has NO visual affordance — no chevron, no arrow, no sort icon. It looks like static text. A huge portion of users will never discover they can sort by xwOBA, Sprint Speed, K%, etc.

**User pain:** "Wait, I can sort by different stats? I've been using this for weeks and never knew."

### No Swipe Between Profile Tabs

**File:** `StatScout/Views/PlayerProfileView.swift`

The Percentiles / Standard Stats / Year Compare tabs are pill buttons. Users naturally try to swipe left/right to page between them (iOS standard pattern). Nothing happens. They must reach up to tap buttons.

**User pain:** "Why can't I just swipe? Every other app lets me swipe between tabs."

### No Player Favorites or Tracking

Only team favoriting exists (UserDefaults `favoriteTeam` key). No way to bookmark individual players. Fantasy baseball players — the core demographic — have to re-search for their players every session.

**User pain:** "I want to track my 12 fantasy players. I have to search each one every time I open the app."

### Forces Light Mode (Dark Mode Disabled)

**File:** `StatScout/StatScoutApp.swift`

The app forces `.preferredColorScheme(.dark)` wait — actually checking… The `arfix428.md` says `.preferredColorScheme(.dark)` is correctly applied. But the `sfix59.md` says it forces `.preferredColorScheme(.light)`. Let me check the actual behavior:

The app hardcodes a Navy/dark navbar with a light background (`SavantPalette.canvas`), but the overall scheme preference is dark. Regardless, both audits flag the issue that the app ignores the user's system appearance preference. Using the app in a dark room is jarring.

**User pain:** "Every other app respects my dark mode setting. This one blasts me with light backgrounds."

### No Player Comparison

Can only view one player at a time. For trade analysis, fantasy decisions, or "who's better" debates, users have to manually switch back and forth between profiles.

**User pain:** "I want to compare Judge and Ohtani side-by-side. I have to screenshot both profiles and switch between them."

### No Share Functionality

`Player.swift` has a `shareSummary` computed property (line ~101) but no `ShareLink` or share button exists anywhere in the UI. Users can't text a player's stats to friends.

**User pain:** "These stats are amazing. I want to send this to my group chat. I have to screenshot it."

### No Search in Metrics Tab

`DashboardView` has search. `TeamsView` has search. But `MetricLeadersView` has no search at all.

**User pain:** "I'm in the Metrics tab and want to find who leads in xwOBA. There's no way to search or jump to a specific metric. I have to scroll through everything."

### Category Filter Has No Player Counts

`CategoryFilter` shows "Hitting", "Pitching", "Fielding", "Running" with no indication of how many players are in each category.

**User pain:** "I tap 'Fielding' and see 3 players. I wouldn't have bothered if I knew."

### No Post-Purchase Feature Discovery

After purchasing Pro, nothing visually changes except banners disappear and locked tabs open. No tour, no badges, no highlighting of newly available features.

**User pain:** "I just paid $14.99. What can I do now? The app looks the same."

### Restore Purchases Hidden From Non-Purchasers

The "Restore Purchases" button in Settings (`AboutView`) only appears when `proStatus == .purchased` (line ~89). If a user reinstalls the app or has a purchase sync issue, they can't find restore in Settings — they must navigate to the paywall first.

**User pain:** "I bought Pro on my iPad. On my iPhone it shows 'Free Version'. Where's the restore button? I checked Settings — nothing."

### No Offline/Stale Data Indicator

When the network fails but cached data is shown, there's a subtle message when the player list is empty. But if cached data is displayed, there's no persistent banner indicating "Showing cached data from [date] — not live."

**User pain:** "I'm on a plane. Is this data current? Or from last week? I can't tell."

### Pricing Tiers Lack Savings Callout

Yearly plan shows "Best Value" badge but no actual savings computation. A simple "$14.99/yr ($1.25/mo)" or "Save 38% vs monthly" would help.

**User pain:** "Yearly is 'best value' but I don't see how much I'm saving. Is it really better?"

---

## 🟢 Medium Priority

### Initial Load Creates a Spinner Flash

**File:** `StatScout/Views/DashboardView.swift` (line ~29)

When launching with cached data, the `isLoading && players.isEmpty` check shows a 1.5x scaled `ProgressView` for a fraction of a second before cached data renders. This creates a visible "flash" — spinner appears then immediately disappears.

**User pain:** "Every time I open the app there's a brief flash. It feels janky."

### Long Player Names Get Crushed

`LeaderboardTableRow` uses `minimumScaleFactor(0.75)` on player names. Names like "Christian Encarnacion-Strand" become tiny, nearly unreadable text.

**User pain:** "I can barely read some player names. They're squished to like 8pt."

### No Swipe-to-Delete or Clear on Search

The search field in `DashboardView` has no clear button. The `TeamsView` search clear button is in the section header, not inside the search field where iOS users expect it (the standard (x) button).

**User pain:** "I want to clear my search. I have to tap the text field and delete character by character."

### Backend Data Completeness Affects UX

The `METRICS_AUDIT_SUMMARY.md` documents that ~82% of players have missing metrics or empty values. While the backend fix has been applied (skipping metrics without actual values), empty standard stats and empty year-compare historical data remain common. The app needs to handle these gracefully rather than showing confusing empty states.

### No Help/FAQ/Tutorial Content

The Settings view has version info and links, but zero help content. No explanation of what percentiles mean (despite the `PercentileInfoSheet` on the profile ⓘ button), no FAQ, no "How to use Year Compare", no metric glossary.

**User pain:** "What does xwOBA mean? Is higher better? I have no way to find out in the app."

### No Recently Viewed

No history of recently viewed players. If a user navigates deep into a profile, backs out, and wants to return — they must search again.

**User pain:** "I was just looking at this player 5 minutes ago. Now I have to search again."

### Backend: Season Hardcoded to 2026

**Files:** `StatcastAPI.swift` lines 25,29,73,77; `PlayerCache.swift` lines 79-80; `DashboardViewModel.swift` line 234

Six locations hardcode `season=eq.2026`. In 2027 this silently returns no data without any code changes.

### Backend: Sample Data in Release Builds

`SampleData.swift` is compiled into Release builds. It contains 6 hardcoded MLB player profiles. Apple reviewers occasionally flag test/fake data in production binaries.

### Backend: Fallback to Sample Data on Production Errors

`DashboardViewModel.load()` falls back to `SampleData.players` on any network/decode error. In production, a backend outage silently shows Aaron Judge and Shohei Ohtani instead of an error state.

### Backend: Privacy Manifest Missing APIs

`PrivacyInfo.xcprivacy` has empty `NSPrivacyAccessedAPITypes` array. The app uses `UserDefaults` (for favorite team) and file timestamp APIs (for cache TTL checking), which require privacy manifest declarations.

### URL Path Inconsistency

Three files hardcode different URL paths — some use `/baseball/` and some use `/statscout/`. If the live GitHub Pages site is at one path and some links point to the other, Apple reviewers clicking those links during review will get 404s and reject.

---

## 🔵 Lower Priority / Polish

- **No pull-to-refresh feedback:** `.refreshable` works but there's no visual confirmation when refresh completes. User pulls down, spinner spins, data may or may not have changed — no indication either way.
- **No haptic on tab switches:** Category filter tabs and sort toggles have haptics, but switching between the main 3 tabs doesn't.
- **No "Back to Leaders" shortcut from deep navigation:** Dashboard → Player → Metric Ranking → Another Player. Going back takes 4 taps.
- **Inconsistent season selector location:** Dashboard has one, player profile has a different one. No season selector on team views or metric views.
- **No personalization:** Can't reorder tabs, choose default category, or customize what metrics appear first.
- **Missing pull-to-refresh on team/metric views:** Only the Dashboard has `.refreshable`.
- **No progress indicator for large data sync:** When re-fetching 1000+ players, no loading bar or progress indication beyond the initial spinner.
- **Free trial / introductory pricing:** No trial period or introductory offer configured. Pure hard wall.
- **Family Sharing:** No mention or support for Family Sharing (even if enabled in App Store Connect).
- **Gift options:** No way to gift Pro to someone else.
- **Dark mode palette:** Forced scheme ignores user preference — need dark variants of `SavantPalette.surface`, `canvas`, etc.
- **VoiceOver gaps:** `MetricBar` is hidden from accessibility entirely. Complex data visualization with no screen reader alternative.
- **Video/app preview:** App Store presence would benefit from a preview video showing the paywall, comparisons, and leaderboards in action.

---

## Summary by Impact

| Category | Issues Found | Severity |
|----------|-------------|----------|
| Paywall/Pro UX | 7 | 🔴 Critical |
| Data Integrity | 2 | 🔴 Critical |
| Navigation & Discovery | 8 | 🟡 High |
| Subscription Management | 3 | 🟡 High |
| Visual & Polish | 10 | 🟡 High / 🟢 Medium |
| Performance & Reliability | 5 | 🟢 Medium |
| Backend/Infra | 4 | 🟢 Medium |
| Delight & Extras | 7 | 🔵 Low |
| **Total** | **46** | |

---

## Priority Implementation Order

### Phase 1 — Fix the Paywall Experience (highest revenue impact)
1. Fix the "First Tap Is a Paywall" problem — default free users to Standard Stats tab or show teaser metrics
2. Fix paywall leakage — either gate Teams/Metrics/StandardStats or update paywall copy and remove banners
3. Actually gate headshots or remove from paywall
4. Add purchase confirmation animation and success state
5. Fix Year Compare lock trap — show tab content with inline upsell

### Phase 2 — Data Integrity & Navigation
6. Fix the Player Profile season disconnect bug (standard stats not respecting selected season)
7. Make dashboard sort discoverable (add chevron/arrow to header)
8. Add swipe gesture between profile tabs
9. Add player favorites/bookmarking
10. Add share functionality using existing `shareSummary`

### Phase 3 — Subscription & Trust
11. Add subscription management link and details to Settings
12. Make Restore Purchases always visible in Settings
13. Add offline/stale data indicator
14. Show savings calculation on pricing tiers
15. Fix URL path inconsistencies

### Phase 4 — Polish & Infrastructure
16. Remove forced color scheme / add dark mode support
17. Add player counts to category filter
18. Add post-purchase feature tour
19. Fix loading spinner flash
20. Add search to Metrics tab
21. Fix privacy manifest
22. Wrap SampleData in #if DEBUG
23. Remove fallback to sample data in production error handling
24. Make season year dynamic
