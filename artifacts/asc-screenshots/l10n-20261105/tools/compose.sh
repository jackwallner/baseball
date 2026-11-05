#!/bin/bash
set -euo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$KIT/../../.." && pwd)"
PY="$KIT/.venv/bin/python"
mkdir -p "$KIT/sheets"

LOCALES=()
if (($#)); then
  LOCALES=("$@")
else
  while IFS= read -r locale; do
    LOCALES+=("$locale")
  done < <("$PY" - "$KIT/app.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1], encoding='utf-8'))['targets']:
    print(item['store_locale'])
PY
)
fi

for locale in "${LOCALES[@]}"; do
  rm -rf "$KIT/out/$locale"
  lang=$("$PY" - "$KIT/app.json" "$locale" <<'PY'
import json, sys
target = next(x for x in json.load(open(sys.argv[1], encoding='utf-8'))['targets'] if x['store_locale'] == sys.argv[2])
print(target['lang'])
PY
)
  "$PY" "$KIT/tools/reskin.py" --config "$KIT/frames.json" --raw-root "$KIT/raw" \
    --headers "$KIT/copy/headers.json" --locale "$locale" --out "$KIT/out"
  "$PY" "$KIT/tools/sheet.py" --config "$KIT/frames.json" --locale "$locale" --out-root "$KIT/out"
  "$PY" "$KIT/tools/gate.py" --config "$KIT/frames.json" --raw-root "$KIT/raw" \
    --headers "$KIT/copy/headers.json" --out-root "$KIT/out" --locale "$locale" \
    --catalog "$ROOT/StatScout/Resources/Localizable.xcstrings" --lang "$lang"
  mkdir -p "$KIT/sheets"
  cp "$KIT/out/sheets/$locale-phone.jpg" "$KIT/sheets/"
done

for locale in "${LOCALES[@]}"; do
  destination="$ROOT/fastlane/screenshots/$locale"
  mkdir -p "$destination"
  find "$destination" -maxdepth 1 -type f -name '*.png' -delete
  cp "$KIT/out/$locale/phone"/*.png "$destination/"
done
