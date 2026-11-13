#!/usr/bin/env python3
"""Compose 13-inch iPad store frames (2064x2752) from raw/ipad captures.

Usage: ipad_compose.py [store_locale ...]
Reads copy/headers.json and raw/ipad/<locale>/<route>.png, writes
out/ipad/<locale>/0N_*.png. Same headline copy as the iPhone set.
"""
import json
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import headline, paste_screen  # noqa: E402

KIT = Path(__file__).resolve().parent.parent
ROOT = KIT.parent.parent.parent
CANVAS = (2064, 2752)
BG = (14, 42, 80)
BEZEL = (10, 14, 26)
FRAMES = [
    ("01_stats_hitting.png", "01"),
    ("02_player_profile.png", "02"),
    ("03_trends.png", "03"),
    ("04_compare.png", "04"),
]
LINES = [
    {"role": "line1", "box": [141, 100, 1782, 170], "font": "AvenirNext-Heavy", "color": [255, 255, 255], "max": 135},
    {"role": "line2", "box": [141, 262, 1782, 160], "font": "AvenirNext-HeavyItalic", "color": [215, 25, 32], "max": 128},
    {"role": "desc", "box": [141, 455, 1782, 110], "font": "AvenirNext-DemiBold", "color": [231, 234, 238], "max": 78},
]
SCREEN = [250, 600, 1564, 2086]
BEZEL_PAD = 28


def jobs_for(locale: str, headers: dict, out_dir: Path) -> list:
    jobs = []
    for index, (name, _) in enumerate(FRAMES):
        title = headers[name].split("\n")
        texts = [title[0], title[1] if len(title) > 1 else "", headers[f"{name}#description"]]
        for style, text in zip(LINES, texts):
            if not text.strip():
                continue
            jobs.append({
                "text": text, "locale": locale, "font": style["font"], "color": style["color"],
                "box": style["box"][2:], "maxSize": style["max"], "minSize": 60, "align": "left",
                "role": style["role"], "origin": style["box"][:2], "frame": index,
                "out": str(out_dir / f"{index}-{style['role']}.png"),
            })
    return jobs


def main() -> None:
    headers_all = json.load(open(KIT / "copy/headers.json", encoding="utf-8"))
    locales = sys.argv[1:] or [k for k in headers_all if (KIT / "raw" / k / "ipad").is_dir()]
    for locale in locales:
        headers = headers_all[locale]
        with tempfile.TemporaryDirectory() as tmp:
            jobs = jobs_for(locale, headers, Path(tmp))
            fit = headline([{k: v for k, v in j.items() if k not in ("origin", "frame", "role")} for j in jobs])
            sizes = {}
            for job, res in zip(jobs, fit):
                if not res["fits"] or res["size"] < 60:
                    raise SystemExit(f"{locale}: {job['role']} does not fit: {job['text']!r}")
                sizes[job["role"]] = min(sizes.get(job["role"], res["size"]), res["size"])
            for job in jobs:
                job["maxSize"] = sizes[job["role"]]
                job["size"] = sizes[job["role"]]
            rendered = headline([{k: v for k, v in j.items() if k not in ("origin", "frame", "role")} for j in jobs])
            if not all(r["fits"] for r in rendered):
                raise SystemExit(f"{locale}: shared size does not fit")
            dest = KIT / "out/ipad" / locale
            dest.mkdir(parents=True, exist_ok=True)
            for index, (name, route) in enumerate(FRAMES):
                canvas = Image.new("RGB", CANVAS, BG)
                x, y, w, h = SCREEN
                ImageDraw.Draw(canvas).rounded_rectangle(
                    (x - BEZEL_PAD, y - BEZEL_PAD, x + w + BEZEL_PAD - 1, y + h + BEZEL_PAD - 1),
                    radius=84, fill=BEZEL)
                raw = Image.open(KIT / "raw" / locale / "ipad" / f"{route}.png")
                paste_screen(canvas, raw, SCREEN, 58)
                for job in jobs:
                    if job["frame"] != index:
                        continue
                    with Image.open(job["out"]) as overlay:
                        canvas.paste(overlay, tuple(job["origin"]), overlay)
                canvas.save(dest / name, format="PNG", optimize=True)
            print(locale, "sizes", sizes, flush=True)


if __name__ == "__main__":
    main()
