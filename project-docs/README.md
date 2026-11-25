# Project documentation

Developer notes and historical audits for this repository. The published site remains in the docs directory.

## Android

- [Android release notes](android/README.md): Porting, test evidence, billing, and Play Console state.

## ASO

- [2026-10-28 ASO pass](aso/2026-10-28-aso-pass.md): Metadata, rank and autocomplete audit for priority markets.

## Audits

- [aso827.md](audits/aso827.md): Baseball Savvy StatScout ASO Audit
- [audit823.md](audits/audit823.md): Baseball Savvy StatScout audit
- [ios27StatScout.md](audits/ios27StatScout.md): iOS 27 compatibility audit: Baseball StatScout
- [state-machines-2026-11-06.md](audits/state-machines-2026-11-06.md): State machine audit: 3 bugs proved by test, 1 code path, with repro suite (`state-machines-2026-11-06-repro.swift`)
- [state-machines-2026-11-06-review.md](audits/state-machines-2026-11-06-review.md): Independent review of the state machine audit: verdicts, corrected ranking and method changes
- [state-machines-2026-11-06-fixes.md](audits/state-machines-2026-11-06-fixes.md): Fixes for the state machine audit: 4 fixed with regression tests, 1 held for Jack
- [state-machines-2026-11-06-verify.md](audits/state-machines-2026-11-06-verify.md): Independent verification of the state machine fixes: PASS, 189/189 tests, fail-without-fix proved
- [presubmit-review-2026-11-07.md](audits/presubmit-review-2026-11-07.md): Pre-submit review of 1.5.6 with deep pass: 1 P1 fixed (Duo fold state reset), 2 P2 open
- [2026-11-20-bug-ux.html](audits/2026-11-20-bug-ux.html): Bug and UX catalog, 2026-11-20: 7 bugs (2 medium, 5 low; 6 confirmed), 10 UX items, October audit items rechecked. Catalog only, nothing fixed.
- [rollout-2026-11-24.md](audits/rollout-2026-11-24.md): Ask to Buy pending line, trial_cta remote config and the star prompt at good moments

## Marketing

- [aso-plan.md](marketing/aso-plan.md): aso-plan.md: Baseball Savvy StatScout ASO Plan
- [lpennant817.md](marketing/lpennant817.md): StatScout 2026 Stretch Run Campaign
