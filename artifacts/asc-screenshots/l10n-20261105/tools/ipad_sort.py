#!/usr/bin/env python3
"""Copy store captures from gh-sim result dirs into raw/<locale>/ipad/NN.png.

Usage: ipad_sort.py <result_id> [...]
"""
import json
import re
import shutil
import sys
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
pattern = re.compile(r"^(.*)__(\d\d)(?:_0_[A-Fa-f0-9-]+)?(?:\.png)?$")
for rid in sys.argv[1:]:
    att = Path.home() / ".gh-sim/results" / rid / "attachments"
    for entry in json.load(open(att / "manifest.json", encoding="utf-8")):
        for item in entry.get("attachments", []):
            match = pattern.match(item.get("suggestedHumanReadableName", ""))
            src = att / item.get("exportedFileName", "")
            if not match or not src.is_file() or src.suffix.lower() != ".png":
                continue
            dest = KIT / "raw" / match.group(1) / "ipad" / f"{match.group(2)}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
            print("saved", match.group(1), match.group(2))
