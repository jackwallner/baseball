# aso-plan.md — Baseball Savvy StatScout ASO Plan

> Written 2026-06-25. App: **Baseball Savvy StatScout** (ID `6763945657`, repo `~/baseball`). Methodology: `~/Desktop/aso.md`.

---

## 0. TL;DR

- **Positioning:** MLB Statcast percentile ranks for hitters/pitchers/fielders — NOT fantasy, NOT live scores.
- **Entire niche at pop-5 floor** except homograph walls (`scout` pop 58, `mlb` pop 62, `savant` pop 7 non-baseball).
- **Strong early authority:** `statcast` #2, `baseball savant` #3, `mlb savant` #24 (↑85).
- **US edit:** subtitle add `Ranks`; swap `era,leaderboard` → `percentile,analytics` (~18%).

---

## 1. Competitor tiers

| Tier | Apps |
|---|---|
| **WALL** | MLB app (849k★), Ballpark, theScore, ESPN/Yahoo Fantasy, Sleeper |
| **WINNABLE PEERS** | FanGraphs (279★), Ball Knowers (43★), StatMuse (69★), Baseball Lab (6★) |
| **ADJACENT** | HOF Sports Stats, RotoGrinders, betting/DFS apps |

---

## 2. US metadata change (staged)

**Current:**
- subtitle: `MLB Statcast Percentiles`
- keywords: `savant,xwoba,oaa,wrc,wrcplus,barrel,era,exit,velocity,hitting,pitching,fielding,metrics,leaderboard`

**Change to:**
- subtitle → `MLB Statcast Percentile Ranks`
- keywords → `savant,xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,percentile,analytics`

| OUT | IN | Why |
|---|---|---|
| era | percentile | era = pop 9 homograph (non-baseball); strengthens percentile cluster |
| leaderboard | analytics | `baseball analytics` newly covered #99 |

90/100 chars · ~18% swap.

**Never field-slot:** `mlb`, `scout`, `velo`, `sports`, `war` as standalone heads — homograph/generic walls despite pop.

---

## 3. Astro state (done 2026-06-25, tag migration complete)

**US:** 58 keywords · **global:** ~164. Legacy `priority`/`phrase` retired; homograph walls re-tracked.

| Tag | Keywords |
|---|---|
| `deployed` | savant, xwoba, oaa, wrc, wrcplus, barrel, exit, velocity, hitting, pitching, fielding, metrics, percentile, analytics |
| `target` | baseball savant, mlb savant, statcast, statcast percentiles, baseball percentiles, savant stats, baseball analytics |
| `wall` | mlb, scout, velo, sports, war, sports analytics, baseball app |

---

## 4. Growth lever

`mlb savant` climbing on authority alone — prioritize ratings/reviews from stat-nerd audience over further keyword churn.

---

## 5. Rollout

Next version. Manual release.
