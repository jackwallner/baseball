# Claude Design — StatScout App Store Preview Package

Self-contained handoff for generating App Store preview frames. Everything Claude Design needs to produce the 8 marketing frames lives in this folder.

## Start here

1. Read [`BRIEF.md`](./BRIEF.md) — the main spec. Covers product, brand tokens, frame-by-frame headlines, output specs, and constraints.
2. Skim the three files in [`reference/`](./reference/) for deeper design-system context (only needed if a brand-system question comes up).
3. Use the PNGs in [`screenshots/`](./screenshots/) as the literal source pixels for each device frame — crop only, do not retouch interior content.

## Folder layout

```
claude-design/
├── README.md                            ← you are here
├── BRIEF.md                             ← primary spec; read first
├── screenshots/                         ← raw simulator captures, 1206×2622
│   ├── raw_01_dashboard.png             ← Hitting leaders (Frame 1)
│   ├── raw_02_teams.png                 ← Teams index (Frame 7)
│   ├── raw_03_metrics.png               ← StatScout best/worst (Frame 3)
│   ├── raw_04_boxscore.png              ← Standard stats (Frame 5)
│   ├── raw_05_profile.png               ← Player profile (Frame 2)
│   ├── raw_06_paywall.png               ← Pro upgrade (Frame 8)
│   ├── raw_07_pitching.png              ← Pitching leaders (Frame 4)
│   └── raw_08_team_detail.png           ← Team roster (Frame 6)
└── reference/
    ├── STATSCOUT_SAVANT_HANDOFF.md      ← in-app design system spec
    ├── SAVANT_PLAYER_PAGE_REFERENCE.html← high-fidelity HTML mock
    └── design-brief-for-claude-design.md← broader product context
```

## Deliverables expected back

- 8 PNGs at **1290 × 2796** named `appstore_preview_<NN>_<slug>.png`
- 1 contact-sheet composite at 25% scale for quick review
- Drop into `/Users/jackwallner/baseball/Screenshots/appstore/` (overwrite existing — the current set there is stale)

## Hard constraints (the BRIEF has the full list)

- City-only team identification — never team nicknames (no "Yankees", no "Astros")
- No MLB / team logos, headshots, or stadium imagery
- One red emphasis word per headline, max
- Don't touch pixels inside the screenshot — crop only
