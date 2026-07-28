# App Store Screenshot Positioning Spec — StatScout

> Supersedes the layout section (§2.3) and frame list (§4) of `BRIEF.md`.
> Palette, type, trademark rules and the "crop only, never retouch" rule in
> `BRIEF.md` all still stand.
>
> Raw source screenshots: `claude-design/screenshots-2026-07/raw_*.png`
> (iPhone 17 Pro **Max** simulator, **1320 × 2868**, light-mode UI, build 144,
> StatScout+ active). Shot on the Max deliberately: the raw is already the exact
> pixel size of the 6.9" App Store canvas, so the only scaling in the pipeline is
> the one that fits the screen inside the device shell.

---

## 1. What's wrong with the set that's live now

The seven frames on ASC today (`fastlane/screenshots/en-US/`) share one layout:
headline block at the top, then roughly 300px of empty background, then a
centred device that runs off the bottom edge.

Two problems, one cosmetic and one commercial.

**Commercial: the thumbnail sells nothing.** In the App Store gallery the first
card is cropped to roughly its top third. On the current frames that third
contains a headline, a band of empty navy, a bezel and a status bar. A person
scrolling search results sees *no product at all* until they tap in. Every
competitor screenshot in that row is showing a chart.

**Cosmetic: the frames are stale.** They show a "Leaders" title, a `Pro` pill, a
Season/Search row and an All / Any PA-IP / Qualified segmented control. None of
those exist. The app now has four tabs, a floating tab bar, a season pill in the
leading toolbar slot and a chip control row.

Everything below is aimed at the first problem. The second is fixed by
reshooting, which is what the raw files are for.

---

## 2. Canvas

| | |
|---|---|
| Primary size | **1320 × 2868** (6.9", iPhone 17 Pro Max slot) |
| Secondary | 1290 × 2796 (6.7") — same layout scaled 0.977, no re-composition |
| Colour space | sRGB, PNG, no alpha |
| Count | 8 frames, ordered as in §5 |

ASC will down-sample the 6.9" set for smaller devices; only these two need to be
produced.

---

## 3. The geometry

One geometry for all eight frames. The device never moves, never resizes, and is
never rotated. Swiping the gallery should feel like the phone is standing still
while the screen behind it changes.

```
y=0     ┌──────────────────────────────────┐
        │                                  │
 96     │   [logo lockup — frame 1 only]   │
        │                                  │
        │   HEADLINE LINE ONE              │  ← 78pt, heavy
        │   Headline line two.             │  ← the red one
        │   Sub-copy, one line.            │  ← 34pt semibold
 393    ├──────────────────────────────────┤
        │        ╭──────────────╮          │
        │        │              │          │
        │        │    DEVICE    │          │  ← 1128 wide, whole
        │        │              │          │     screen visible
        │        │              │          │
2808    │        ╰──────────────╯          │
2868    └──────────────────────────────────┘
```

| Element | Value |
|---|---|
| Text safe margin | 96px left and right, all frames |
| Headline band | y 0 → 393 (13.7%) |
| Headline type | 78pt / 104px line height, 2 lines max, tracking −0.5 |
| Sub-copy | 34pt, one line, 24px below the headline block |
| Device outer | 1128 × 2415, x = 96 → 1224, y = 393 → 2808 |
| Screenshot scale | 0.8303 (1320 × 2868 → 1096 × 2381) |
| Bezel | 16px, black titanium, 60px corner radius |
| Device shadow | y+8, blur 12, black 30% — one shadow, no glow |
| Bottom margin | 60px |

### Three rules that matter more than the numbers

1. **The whole screen is visible, including the floating tab bar.** The current
   set bleeds the phone off the bottom edge and loses it. That bar is how a
   stranger learns the app has four sections; it costs 230px of device height to
   show and it is worth it.
2. **Product starts at y=393, inside the thumbnail crop.** The gallery card cuts
   at roughly y=956, so every frame's thumbnail carries the headline, the navy
   nav bar, the control chips and three or four data rows. That is the entire
   point of this revision.
3. **No dead band.** Sub-copy bottom to device top is 24–40px, not 300. If a
   headline needs more room than the band gives it, the headline is too long.

### Bottom-band variant — do not use

`BRIEF.md` §2.3 offered a "navy band at the bottom" alternative for dense
frames. Drop it. It puts the copy outside the thumbnail crop and it breaks the
standing-still-phone effect. One geometry, eight frames.

---

## 4. Background rotation

Solid fills only, alternating so the gallery has rhythm:

| Frame | Background | Headline colour | Emphasis line |
|---|---|---|---|
| 1 | `savantNavy #0E2A50` | white | `savantRed` |
| 2 | `canvas #F2F4F7` | `ink #0B1220` | `savantRed` |
| 3 | `savantNavy` | white | `savantRed` |
| 4 | `canvas` | `ink` | `savantRed` |
| 5 | `savantNavy` | white | `savantRed` |
| 6 | `canvas` | `ink` | `savantRed` |
| 7 | `savantNavy` | white | `savantRed` |
| 8 | `canvas` | `ink` | `savantRed` |

One red line per frame, never two. No gradients, no texture, no field grass, no
diamond graphics.

---

## 5. Frame order and copy

Order is by what converts, not by app navigation. Frames 1–3 carry the install;
ASC shows the first three in the search-results carousel.

| # | Raw file | Headline | Sub-copy |
|---|---|---|---|
| 1 | `raw_01_stats_hitting.png` | Every qualified hitter. / **Ranked.** | Statcast percentiles, refreshed nightly. |
| 2 | `raw_02_player_profile.png` | Read a player / **at a glance.** | One screen. Every metric that matters. |
| 3 | `raw_03_trends.png` | Who's hot / **right now.** | Ranked by how far they've moved, not where they sit. |
| 4 | `raw_04_compare.png` | Settle it. / **Side by side.** | Any two players, any two seasons. |
| 5 | `raw_05_team.png` | Your club, / **one tap in.** | All 30 rosters, hitting through running. |
| 6 | `raw_06_year_compare.png` | Every season / **he's ever had.** | Percentile by percentile, year over year. |
| 7 | `raw_07_standard_running.png` | Old-school numbers. / **New-school speed.** | AVG, ERA, SB — the box score, sorted. |
| 8 | `raw_08_teams_index.png` | 30 clubs. / **Sorted.** | Team xwOBA, ERA, and the rest of it. |

`raw_04b_compare_cross_year.png` is an alternate for frame 4: the same
head-to-head with Ohtani moved to 2023 while Judge stays on 2026. It's the
better *argument* for the subscription and the worse-looking table (two of the
cells fall back to a bare percentile, which is honest but reads as jargon at
thumbnail size). Use 04 unless the frame needs to sell cross-year explicitly.

Copy is a starting point, not a constraint — flag anything that reads awkwardly
rather than guessing. The trademark posture in `BRIEF.md` §3 is not negotiable:
city names only, no MLB or club marks anywhere on the canvas.

---

## 6. Shooting and cropping the raws

Rules the raw files already follow, and that any reshoot must:

- **Scroll position:** every frame is scrolled so a red (hot) value appears in
  the top quarter of the screen. A screenshot whose first visible rows are all
  blue reads as a spreadsheet.
- **Row alignment:** the bottom of the visible content lands on a row divider or
  runs cleanly under the tab bar. Never crop a frame through the middle of a
  line of text.
- **Status bar:** left as the simulator renders it. Don't overpaint the time or
  the battery.
- **Entitlement:** frames 3, 4 and 6 are StatScout+ surfaces and are shot with
  the subscription active, so they show real boards rather than blur gates. That
  is honest — they are what a subscriber sees — but frame 3's sub-copy should
  not imply the board is free.
- **Crop only.** No retouching a number, no splicing two scroll positions into
  one screen, no fake rows.

---

## 7. Deliverables

- `Screenshots/appstore/appstore_preview_<NN>_<slug>.png` × 8, at 1320 × 2868
- The same 8 at 1290 × 2796
- One contact sheet at 25% for review
- Nothing goes to `fastlane/screenshots/en-US/` until the set is approved; that
  directory is what `fastlane upload_metadata` pushes live.
