#!/usr/bin/env python3
"""Capture localized iPad frames on gh-sim, six screens per run.

Usage: ipad_capture.py [store_locale ...]
Writes raw/ipad/<store_locale>/<route>.png under the kit folder.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
ROOT = KIT.parent.parent.parent
ROUTES = ["stats", "player", "trends", "playercompare"]
BASE = "-DuoSeed -ScreenshotData -StoreScreenshotData -DuoTour -DuoTourStep 600 -DuoTourFirst 600 -hasCompletedOnboarding YES"
PER_RUN = 6


def main() -> None:
    cases = json.load(open(ROOT / "StatScoutUITests/StoreScreenshotLocales.json", encoding="utf-8"))
    wanted = set(sys.argv[1:])
    cases = [c for c in cases if not wanted or c["store"] in wanted]
    jobs = [(c, r) for c in cases for r in ROUTES]
    jobs = [j for j in jobs if not (KIT / "raw/ipad" / j[0]["store"] / f"{j[1]}.png").is_file()]
    for start in range(0, len(jobs), PER_RUN):
        batch = jobs[start:start + PER_RUN]
        id_file = Path("/tmp/ipad-cap.id")
        cmd = ["gh-sim", "launch", "--device", "iPad Pro 13-inch (M5)", "--wait", "12", "--id-file", str(id_file),
               "--xcarg", "SUPABASE_URL=https://example.invalid", "--xcarg", "SUPABASE_ANON_KEY=dummy",
               "--env", "STATSCOUT_FORCE_PRO=1", "--env", "FORCE_PRO=1", "--env", "SCREENSHOT_MODE=1"]
        for case, route in batch:
            cmd += ["--screen", f"{BASE} -AppleLanguages ({case['language']}) -AppleLocale {case['region']} -DuoRoutes {route}"]
        print("batch", [(c["store"], r) for c, r in batch], flush=True)
        subprocess.run(cmd)
        rid = id_file.read_text().strip()
        shots = Path.home() / ".gh-sim/results" / rid / "shots"
        if not shots.is_dir():
            print("no shots for", rid, flush=True)
            continue
        found = sorted(shots.glob("screen*.png"), key=lambda p: int(p.name.split("-")[0][6:]))
        for path, (case, route) in zip(found, batch):
            dest = KIT / "raw/ipad" / case["store"] / f"{route}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(path, dest)
        print("saved", len(found), "of", len(batch), rid, flush=True)


if __name__ == "__main__":
    main()
