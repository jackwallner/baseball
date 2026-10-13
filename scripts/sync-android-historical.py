#!/usr/bin/env python3
"""Copy the exact iOS historical payload into a reproducible Android gzip asset."""
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    source = ROOT / "StatScout/Data/players-historical.json"
    rows = json.loads(source.read_text())
    target = ROOT / "android/app/src/main/assets/players-historical.bin"
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode()
    with target.open("wb") as output:
        with gzip.GzipFile(filename="", fileobj=output, mode="wb", mtime=0) as compressed:
            compressed.write(payload)
    print(f"Synced {len(rows)} historical players ({target.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
