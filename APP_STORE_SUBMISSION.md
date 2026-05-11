# 🏟️ StatScout: App Store Connect Submission Metadata

> **Build:** 1.0 (72)  
> **Schema:** Baseball Savant-style player percentile pages  
> **Monetization:** RevenueCat — Monthly, Yearly (free trial), Lifetime  
> **Last updated:** May 11, 2026

---

## 1. App Information

| Field | Value |
|---|---|
| **App Name** | StatScout: MLB Percentiles |
| **Subtitle** | Baseball Rankings & Metrics |
| **Primary Category** | Sports |
| **Secondary Category** | Utilities |
| **Content Rights** | Does not contain, show, or access third-party content. |
| **Age Rating** | 4+ (No objectionable content) |
| **Copyright** | 2026 Jack Wallner |

---

## 2. Platform URLs

| Field | URL |
|---|---|
| **Support URL** | `https://jackwallner.github.io/baseball/support.html` |
| **Privacy Policy URL** | `https://jackwallner.github.io/baseball/privacy-policy.html` |

---

## 3. App Store Screenshots

Six screenshots available in `Screenshots/appstore/`. Upload in this order:

| # | File | Caption |
|---|---|---|
| 1 | `01_dashboard_leaderboard.png` | Dashboard leaderboard with percentile rankings |
| 2 | `02_teams.png` | Team roster view with player rankings |
| 3 | `03_metric_leaders.png` | Metric leaders — best & worst per category |
| 4 | `04_player_profile.png` | Player profile with percentile bars and standard stats |
| 5 | `05_paywall_pro.png` | StatScout Pro paywall with feature list |
| 6 | `06_year_compare_pro.png` | Year-over-year player comparison (Pro feature) |

---

## 4. Promotional Text

> Baseball Savant-style percentile rankings in your pocket. Visual red-blue metric bars, nightly-updated leaderboards, and deep player profiles — now with StatScout Pro for historical comparisons and year-over-year tracking.

---

## 5. Description

> **Scout the league like a pro.**
> 
> StatScout brings Baseball Savant's signature percentile rankings to your iPhone. See exactly where every MLB player ranks — from xwOBA to Sprint Speed to Outs Above Average — with the same visual red-blue bars you know from the Savant player page.
> 
> **SAVANT-STYLE PERCENTILES**
> Every metric displays as a horizontal percentile bar with a colored circle marker — just like the Baseball Savant player page. The color shifts continuously from blue (0th percentile) through gray (50th) to red (100th), so you can spot elite performers instantly.
> 
> **COMPREHENSIVE PLAYER PROFILES**
> Tap any player to see their full Savant-style profile. View percentile rankings across Hitting, Pitching, Fielding, and Running. Switch between advanced Statcast metrics and standard season stats. Track performance trends with nightly-updated data.
> 
> **NIGHTLY UPDATES**
> Our data feed refreshes every night, pulling the latest Statcast percentile rankings and standard stats for every active MLB player. What you see is always current through the previous day's games.
> 
> **LEADERBOARDS & FILTERS**
> Browse the full league leaderboard filtered by Hitting, Pitching, Fielding, or Running. Sort and search across every active player. Tap any row to dive into their full profile.
> 
> **STATSCOUT PRO**
> Unlock the full experience with StatScout Pro:
> • Historical Seasons — go back to any season from 2020 onward
> • Player Comparisons — compare any two players side by side
> • Year-Over-Year Tracking — see how a player's metrics changed season to season
> • Advanced Percentiles Tab — exclusive percentile deep-dive on every profile
> 
> Choose Monthly, Yearly (with free trial), or Lifetime — one purchase covers everything.
> 
> **PRIVACY-FIRST**
> No accounts. No sign-up. No tracking. No ads. Your data never leaves your device except for the minimal network requests needed to load baseball statistics.
> 
> StatScout is not affiliated with, endorsed by, or sponsored by Major League Baseball, MLB Advanced Media, the MLBPA, or any individual team. Player names, team names, and statistics are used for identification and informational purposes only.

---

## 6. Keywords

```
baseball,mlb,stats,analytics,savant,statcast,fantasy,metrics,leaderboard,sabermetrics,rankings,pitcher,hitter,percentile,xwOBA,OAA,sprint speed,wRC+,barrel,hard hit,pitching,fielding,running,comparisons,historical,scout
```

---

## 7. App Privacy (Data Safety)

Select **"No, we do not collect data from this app"** in App Store Connect.

**Details for reviewer:**
- No account creation or sign-in required
- No analytics SDKs, no third-party trackers, no ad networks
- All user preferences stored locally via `@AppStorage` and `UserDefaults`
- Network requests are limited to: (a) Supabase REST API for player stat snapshots, (b) MLB CDN (`midfield.mlbstatic.com`) for player headshot images
- Purchase state is verified on-device via StoreKit 2 through RevenueCat
- No user-generated content, no chat, no social features
- The `PrivacyInfo.xcprivacy` manifest declares empty `NSPrivacyCollectedDataTypes` and `NSPrivacyAccessedAPITypes` — the app uses no required-reason APIs

---

## 8. Review Information

| Field | Value |
|---|---|
| **Contact Info** | Jack Wallner / jackwallner@gmail.com |
| **Phone** | Available upon request |
| **Demo Account** | Not required — no login, no account system |
| **Sign-in Required** | No |

---

## 9. Notes for Reviewer (Comprehensive)

### App Overview

StatScout is a read-only baseball statistics viewer. It fetches nightly Statcast percentile rankings from a Supabase database and renders them as mobile-friendly player profiles using the same visual style as Baseball Savant player pages. There is no user input beyond search, filtering, and IAP purchase. No content is user-generated.

### What to Test — Core Flow (Free Tier)

1. **Launch the app.** The dashboard loads automatically and shows a leaderboard of MLB players ranked by overall percentile. A navy header strip reads "savant" with a "STATSCOUT" badge. Below that: filter pills for Batter/Pitcher, Team, Season, and an Update button.
2. **Scroll the leaderboard.** Rows display player rank, headshot, name, team, key stat value, and a mini percentile bar (red-blue gradient circle on a gray track). This loads ~800+ players.
3. **Tap a player.** The player profile pushes onto the navigation stack (back chevron visible). Verify the navy identity strip shows the player's headshot, name, team, and position. Below it: "PERCENTILE RANKINGS" section with visual metric bars (gray track + colored circle marker + percentile number).
4. **Switch tabs.** On the player profile, tap "STANDARD STATS" to see traditional season stats (AVG, HR, RBI, etc. for hitters; ERA, WHIP, K for pitchers).
5. **Search.** Return to dashboard, use the search field to find a specific player. Results filter as you type.
6. **Category filters.** Use the category tabs (All, Hitting, Pitching, Fielding, Running) to filter the leaderboard by stat category.
7. **Teams tab.** Tap the Teams tab in the bottom bar. Verify the team grid loads. Tap a team to see its roster with player rankings.
8. **Metrics tab.** Tap the Metrics tab. Verify metric leaders are grouped by category showing Best and Worst (highest and lowest percentile) for each Statcast metric.
9. **Settings/About.** The Settings tab (gear icon) shows app info, support links, and the "Restore Purchases" button.

### What to Test — Pro Features (IAP)

10. **Pro paywall.** On the player profile, tap the "COMPARISONS" tab, the "YEAR COMPARE" tab, or the "PERCENTILES" tab — any of these triggers the StatScout Pro paywall for free users. The paywall shows three product options: Monthly, Yearly (pre-selected with "Best Value" badge and free trial), and Lifetime. Tapping the CTA initiates a StoreKit purchase.
11. **Test purchase.** Use a Sandbox tester account to purchase any Pro tier. On success, the app shows "Welcome to StatScout Pro!" and dismisses the paywall. All gated features unlock immediately.
12. **Restore purchases.** Tap "Restore Purchases" in the paywall toolbar or in Settings. The app re-fetches entitlements from RevenueCat/StoreKit.
13. **Historical seasons.** Pro users can select any season from 2020–2026 using the Season filter pill on the dashboard. Free users are restricted to the current season (2026).
14. **Player comparisons.** Pro users can tap "COMPARISONS" on a player profile to select a second player and view side-by-side metric comparisons.
15. **Year-over-year.** Pro users can tap "YEAR COMPARE" to see a player's metrics across multiple seasons with trend arrows.

### Data Freshness

The app pulls data from a Supabase database that is refreshed nightly via an automated GitHub Actions workflow. The data reflects the previous day's games. There is no real-time or in-game updating — this is by design. The app does not display live scores, play-by-play, or in-game data.

### Network Endpoints

- **Supabase REST API** (`https://babzqsbmcunrezsdpyng.supabase.co`) — player snapshot data, read-only via anon key with Row Level Security
- **MLB CDN** (`https://midfield.mlbstatic.com`) — player headshot images
- **RevenueCat** (`https://api.revenuecat.com`) — IAP purchase verification and entitlement checks

### Known Visual Characteristics

- The app is **light-mode only** (`.preferredColorScheme(.light)`). This is intentional — it mirrors the Baseball Savant website's light background aesthetic.
- No shadows are used. Visual separation comes from 0.5pt hairline dividers and alternating white/off-white zebra row backgrounds.
- Corner radii are deliberately small (4pt max, except circular headshots) to match the Savant design language.
- The percentile coloring is a continuous blue-to-gray-to-red gradient, calculated mathematically — not step-based thresholds.
- Stat numbers use monospaced digits for tabular alignment. Section headers are uppercase with tight tracking.

### IAP Configuration (RevenueCat)

| Product ID | Type |
|---|---|
| `com.jackwallner.baseball.pro.monthly` | Auto-renewing subscription |
| `com.jackwallner.baseball.pro.yearly` | Auto-renewing subscription (with free trial) |
| `com.jackwallner.baseball.pro` | Non-consumable lifetime purchase |

All three products unlock the single entitlement: `StatScout Pro`.

### MLB Intellectual Property

The app displays MLB player names, team names, team abbreviations, team colors, player headshots, and publicly available statistics. A disclaimer is present at the bottom of the description, on the About screen within the app, and on the support website. No MLB trademarks are used in the app icon, app name, or in any way that suggests official MLB affiliation.

---

## 10. Version Release Notes (Build 72)

**What's New:**

- Complete visual overhaul to match Baseball Savant's signature style — new navy identity strips, red-accented section headers, continuous percentile-colored marker bars, and zebra-striped stat tables
- StatScout Pro is now available — unlock historical seasons (2020–2026), player comparisons, year-over-year tracking, and advanced percentile deep-dives with Monthly, Yearly (free trial), or Lifetime purchase options
- New player profile layout with tabbed navigation: Percentile Rankings, Standard Stats, Comparisons, and Year Compare
- Category-filtered leaderboards for Hitting, Pitching, Fielding, and Running
- Team rosters with player headshots, team colors, and internal rankings
- Nightly data refresh keeps all stats current through the previous day's games
- Privacy-first: no accounts, no sign-up, no tracking, no ads — ever
