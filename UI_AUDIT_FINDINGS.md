# StatScout Comprehensive UI/UX Audit Findings

## App Navigation Hierarchy

```
RootTabView (3 tabs)
├── Leaders Tab (DashboardView)
│   ├── PlayerProfileView
│   │   └── MetricRankingView (via metric row tap)
│   └── MetricRankingView (via leaderboard metric column)
├── Teams Tab (TeamsView)
│   └── TeamView
│       └── PlayerProfileView
└── Metrics Tab (MetricLeadersView)
    └── MetricRankingView
        └── PlayerProfileView

Global: AboutView (sheet from any tab)
```

---

## Test Coverage Matrix

| Feature | Test File | Test Cases | Status |
|---------|-----------|------------|--------|
| Dashboard Search | `StatScoutComprehensiveUITests.swift` | testDashboardSearchField, testDashboardEmptySearchState | ✅ Created |
| Category Filter | `StatScoutComprehensiveUITests.swift` | testDashboardCategoryFilterSwitching | ✅ Created |
| Leaderboard Sort | `StatScoutComprehensiveUITests.swift` | testDashboardLeaderboardSort | ✅ Created |
| Leaderboard Navigation | `StatScoutComprehensiveUITests.swift` | testDashboardLeaderboardRowNavigation | ✅ Created |
| Player Profile Metrics | `StatScoutComprehensiveUITests.swift` | testPlayerProfileMetricBars | ✅ Created |
| Player History | `StatScoutComprehensiveUITests.swift` | testPlayerProfileYearOverYearHistory | ✅ Created |
| Share Functionality | `StatScoutComprehensiveUITests.swift` | testPlayerProfileShareFunctionality | ✅ Created |
| Teams Grid | `StatScoutComprehensiveUITests.swift` | testTeamsViewGridLayout | ✅ Created |
| Team Roster | `StatScoutComprehensiveUITests.swift` | testTeamViewRosterAndSearch | ✅ Created |
| Metric Leaders | `StatScoutComprehensiveUITests.swift` | testMetricLeadersViewCategoryGrouping | ✅ Created |
| Metric Ranking Sort | `StatScoutComprehensiveUITests.swift` | testMetricRankingViewSorting | ✅ Created |
| About View | `StatScoutComprehensiveUITests.swift` | testAboutViewLinks | ✅ Created |
| Navigation Stack | `StatScoutComprehensiveUITests.swift` | testDeepNavigationStack | ✅ Created |
| Accessibility | `StatScoutComprehensiveUITests.swift` | testVoiceOverLabels | ✅ Created |
| Performance | `StatScoutComprehensiveUITests.swift` | testLargeLeaderboardScrolling | ✅ Created |

---

## Findings by Screen

### 1. DashboardView

#### ✅ Positive Findings
- **Search**: Real-time filtering with name, team, and full team name support
- **Category Filter**: Horizontal scrollable tabs with visual selection indicator (red underline)
- **Sort**: Toggle between ascending/descending with arrow indicator
- **Empty States**: Proper `ContentUnavailableView` for no results and no data
- **Error States**: Retry button with appropriate messaging for network failures
- **Data Freshness**: "Through [date]" indicator shows last update time

#### ⚠️ Potential Issues
1. **Search field placeholder** may be truncated on smaller screens: "Search players or teams (e.g. NYY, LAD)"
2. **Sort button** is small - may be hard to tap on some devices
3. **No loading state** for individual row images (AsyncImage has no placeholder skeleton)

#### 🔧 Recommendations
- [ ] Add shimmer/skeleton loading for player headshots
- [ ] Increase sort button tap target size
- [ ] Consider haptic feedback on category switch

---

### 2. PlayerProfileView

#### ✅ Positive Findings
- **Navigation**: Clean `NavigationLink` from leaderboard rows
- **Metric Display**: Grouped by category with average percentile in subsection header
- **Year-over-Year**: Conditional display only when history > 1 season exists
- **Standard Stats**: 2-column grid layout with proper empty state
- **Share**: Native `ShareLink` with formatted summary including top metric
- **Deep Link**: Metric rows navigate to `MetricRankingView` via `MetricRoute`

#### ⚠️ Potential Issues
1. **MetricBar accessibility**: The bar itself is `accessibilityHidden(true)` - screen readers only see the text values
2. **Long player names**: No truncation handling in `PlayerIdentityStrip` beyond `minimumScaleFactor: 0.7`
3. **Share preview**: Limited customization of share sheet preview

#### 🔧 Recommendations
- [ ] Add `accessibilityLabel` to MetricBar with full metric description
- [ ] Test with longest MLB player names (e.g., "Cristian Javier-Feliciano Guzman")
- [ ] Consider adding metric definitions/glossary link

---

### 3. MetricBar (Components.swift)

#### ✅ Positive Findings (Post-Fix)
- **Percentile in circle**: Number clearly visible inside colored circle
- **Stat value on right**: Actual value separated from percentile
- **Color coding**: Matches Baseball Savant style (blue → white → red)
- **Bar fill**: Extends to circle position showing progression

#### ⚠️ Potential Issues
1. **Circle size**: 28pt may be too large for very low percentile values (circle extends beyond bar at 0%)
2. **Text legibility**: 11pt font may be small for some users
3. **Color contrast**: Need to verify white text on light blue (low percentiles) passes WCAG

#### 🔧 Recommendations
- [ ] Test edge case: 0th and 100th percentile display
- [ ] Consider dynamic text sizing for accessibility
- [ ] Verify color contrast ratios

---

### 4. TeamsView & TeamView

#### ✅ Positive Findings
- **Grid Layout**: 3-column responsive grid with all 30 teams
- **Team Colors**: MLB-consistent color coding
- **Player Count**: Badge shows number of tracked players per team
- **Roster Search**: Real-time filtering within team roster
- **Alphabetical Sort**: Players sorted A-Z, can filter by search

#### ⚠️ Potential Issues
1. **No empty team state**: If a team has 0 players, tile shows "0" without explanation
2. **Team name truncation**: Long team names may truncate with `minimumScaleFactor: 0.7`
3. **No roster sort options**: Only alphabetical, no sort by percentile or position

#### 🔧 Recommendations
- [ ] Add "No players tracked" overlay for empty teams
- [ ] Add roster sort options (Name, Percentile, Position)

---

### 5. MetricLeadersView

#### ✅ Positive Findings
- **Category Grouping**: Metrics grouped by Hitting/Pitching/Fielding/Running
- **Best/Worst Display**: Shows leader and laggard for each metric
- **Player Headshots**: Small 24px headshots in best/worst cells
- **Navigation**: Tap metric name → MetricRankingView, tap player → PlayerProfileView

#### ⚠️ Potential Issues
1. **Missing metrics**: If a metric has no qualified players, shows "—"
2. **Horizontal scroll**: Metric names may truncate in 3-column layout
3. **No metric description**: Users may not know what "xwOBA" means

#### 🔧 Recommendations
- [ ] Add metric description tooltip or info button
- [ ] Consider 2-line metric name wrapping

---

### 6. MetricRankingView

#### ✅ Positive Findings
- **Dynamic Filtering**: Shows only players with the selected metric
- **Sort Toggle**: Same ascending/descending as main leaderboard
- **Full Leaderboard**: Complete ranking with percentile bar mini

#### ⚠️ Potential Issues
1. **No empty state message**: Just shows "No rankings found" without context
2. **No metric context**: Users may forget which metric they're viewing

#### 🔧 Recommendations
- [ ] Add metric definition at top of view
- [ ] Show qualifying threshold explanation

---

### 7. AboutView

#### ✅ Positive Findings
- **Version Info**: App version and build number displayed
- **Last Updated**: Shows data freshness timestamp
- **External Links**: Support and Privacy Policy open in browser
- **Disclaimer**: Proper legal disclaimer about MLB affiliation

#### ⚠️ Potential Issues
1. **Links not tappable in UITest**: May need `openURL` entitlement testing
2. **No data refresh button**: Users can't manually trigger refresh

#### 🔧 Recommendations
- [ ] Add "Refresh Data" button for manual pull-to-refresh equivalent

---

## Data Integrity Findings

### ✅ Positive Findings
1. **Caching**: `DiskPlayerCache` persists data for offline viewing
2. **Error Handling**: Graceful degradation with cached data on network failure
3. **Two-Way Players**: Special handling in `overallPercentile` calculation (uses max category average)
4. **Season Handling**: Composite ID with playerId + season for history

### ⚠️ Potential Issues
1. **Empty value display**: If `metric.value` is empty, shows percentile only
2. **Date parsing**: Custom ISO8601 formatter with fractional seconds fallback
3. **Image URLs**: Fallback to MLB midfield API if `imageURL` is nil

---

## Accessibility Findings

### ✅ Positive Findings
- `PercentileBarMini` has `accessibilityLabel`
- `OverallPercentileBadge` has `accessibilityLabel`
- `PlayerHeadshot` has `accessibilityHidden(true)` (decorative)
- `TeamColorDot` has `accessibilityHidden(true)` (decorative)

### ⚠️ Issues
1. **MetricBar**: Hidden from accessibility entirely
2. **LeaderboardTableRow**: No accessibility label for the row
3. **No accessibility hints**: Users don't know they can tap for details

### 🔧 Recommendations
```swift
// Add to MetricBar:
.accessibilityElement(children: .ignore)
.accessibilityLabel("\(metric.label): \(metric.value), \(metric.percentile)th percentile")

// Add to LeaderboardTableRow:
.accessibilityElement(children: .combine)
.accessibilityHint("Double-tap to view player profile")
```

---

## Performance Findings

### ✅ Positive Findings
- `LazyVGrid` for team grid (efficient cell reuse)
- `ScrollView` with bounce behavior based on size
- `AsyncImage` with placeholder for headshots

### ⚠️ Potential Issues
1. **Metric ranking calculation**: Computed on every view update, not cached
2. **Image loading**: No lazy loading for off-screen images

---

## Edge Cases to Test

| Scenario | Expected Behavior | Test Status |
|----------|-------------------|-------------|
| Player with no metrics | Show "No metrics available" | ⚠️ Needs test |
| Two-way player (Ohtani) | Show max category average | ✅ Handled |
| Very long player name | Scale down to 70% minimum | ⚠️ Needs test |
| 0th percentile | Blue circle at left edge | ⚠️ Needs test |
| 100th percentile | Red circle at right edge | ⚠️ Needs test |
| No network + no cache | Show ConfigMissingView | ✅ Handled |
| Network error + has cache | Show cached data with warning | ✅ Handled |
| Special characters in name | Proper display (e.g., "José Ramírez") | ⚠️ Needs test |
| Empty search results | Show "No players found" with suggestion | ✅ Handled |

---

## Summary of Recommendations

### High Priority
1. [ ] Add accessibility labels to MetricBar and leaderboard rows
2. [ ] Test 0th and 100th percentile edge cases in MetricBar
3. [ ] Verify color contrast for low percentile values
4. [ ] Add pull-to-refresh on all list views

### Medium Priority
1. [ ] Add shimmer loading for AsyncImage headshots
2. [ ] Add metric definitions/glossary
3. [ ] Add roster sort options (TeamView)
4. [ ] Increase sort button tap target

### Low Priority
1. [ ] Add haptic feedback on category switch
2. [ ] Add manual refresh button in AboutView
3. [ ] Add player position filter to roster

---

## Test Execution

Run the comprehensive UI tests:

```bash
cd /Users/jackwallner/baseball
xcodebuild test -project StatScout.xcodeproj -scheme StatScoutUITests -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

Or run specific test:

```bash
xcodebuild test -project StatScout.xcodeproj -scheme StatScoutUITests -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing StatScoutUITests/StatScoutComprehensiveUITests/testDashboardSearchField
```
