#!/bin/bash
set -euo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$KIT/../../.." && pwd)"
PY="$KIT/.venv/bin/python"
TEST_CONFIG="$ROOT/StatScoutUITests/StoreScreenshotLocales.json"

if [[ ! -x "$PY" ]]; then
  echo "Create the kit venv first: python3 -m venv $KIT/.venv" >&2
  exit 1
fi

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

BACKUP="$(mktemp)"
cp "$TEST_CONFIG" "$BACKUP"
restore() { cp "$BACKUP" "$TEST_CONFIG"; rm -f "$BACKUP"; }
trap restore EXIT

"$PY" - "$KIT/app.json" "$ROOT/StatScout/Resources/Localizable.xcstrings" "$KIT/frames.json" "$TEST_CONFIG" "${LOCALES[@]}" <<'PY'
import json, os, sys
from pathlib import Path

app_path, catalog_path, frames_path, dest, *requested = sys.argv[1:]
app = json.load(open(app_path, encoding='utf-8'))
catalog = json.load(open(catalog_path, encoding='utf-8'))
frames = json.load(open(frames_path, encoding='utf-8'))
all_scenes = [int(frame['raw']) for frame in frames['sets']['phone']['frames']]
scene_filter = os.environ.get('SCREENSHOT_SCENES', '')
if scene_filter.strip():
    requested_scenes = {int(value.strip()) for value in scene_filter.split(',') if value.strip()}
    unknown_scenes = requested_scenes - set(all_scenes)
    if unknown_scenes:
        raise SystemExit(f'Unknown scenes: {sorted(unknown_scenes)}')
    scenes = [scene for scene in all_scenes if scene in requested_scenes]
else:
    scenes = all_scenes
if not scenes:
    raise SystemExit('No screenshot scenes selected')
allowed = {item['store_locale'] for item in app['targets']}
wanted = set(' '.join(requested).replace(',', ' ').split())
if wanted - allowed:
    raise SystemExit(f'Unknown locales: {sorted(wanted - allowed)}')

def localized(key, lang):
    entry = catalog.get('strings', {}).get(key, {})
    node = entry.get('localizations', {}).get(lang, {})
    if not node and '-' in lang:
        node = entry.get('localizations', {}).get(lang.split('-')[0], {})
    def value(node):
        if isinstance(node, dict):
            unit = node.get('stringUnit')
            if isinstance(unit, dict) and 'value' in unit:
                return unit['value']
            for child in node.values():
                found = value(child)
                if found is not None:
                    return found
        return None
    return value(node) or key

keys = {
    'seasonPicker': 'Season and season type',
    'yearCompare': 'Year Compare',
    'teamFooter': 'Weighted by PA across the hitting roster',
    'swingLength': 'Swing Length',
    'versus': 'vs',
}
records = []
baseline = dict(store_locale='en-US', lang='en', apple_languages='(en)', apple_locale='en_US')
for target in [baseline] + app['targets']:
    if target['store_locale'] not in wanted and target['store_locale'] != 'en-US':
        continue
    lang = target['lang']
    language = target['apple_languages'].strip('()').split()[0]
    records.append(dict(
        store=target['store_locale'], language=language,
        region=target['apple_locale'], scenes=scenes,
        **{field: localized(key, lang) for field, key in keys.items()},
    ))
Path(dest).write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

"$PY" - "$TEST_CONFIG" "$KIT/raw" <<'PY'
import json, sys
from pathlib import Path

locales = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
root = Path(sys.argv[2])
for locale in locales:
    for scene in locale['scenes']:
        (root / locale['store'] / 'phone' / f'{scene:02d}.png').unlink(missing_ok=True)
PY

ID_FILE="$(mktemp)"
cd "$ROOT"
gh-sim test --scheme StatScoutUITests --device "iPhone 17 Pro Max" \
  --only StatScoutUITests/LocalizedStoreScreenshotUITests \
  --xcarg SUPABASE_URL=https://example.invalid \
  --xcarg SUPABASE_ANON_KEY=store-screenshot-fixture \
  --id-file "$ID_FILE"
ID="$(cat "$ID_FILE")"
rm -f "$ID_FILE"

"$PY" - "$HOME/.gh-sim/results/$ID/attachments" "$KIT/raw" "$TEST_CONFIG" <<'PY'
import json, re, shutil, sys
from pathlib import Path

attachments, destination, config = map(Path, sys.argv[1:])
locales = json.loads(config.read_text(encoding='utf-8'))
allowed = {item['store'] for item in locales}
manifest = json.loads((attachments / 'manifest.json').read_text(encoding='utf-8'))
pattern = re.compile(r'^(.*)__(\d\d)(?:_0_[A-Fa-f0-9-]+)?(?:\.png)?$')
count = 0
seen = set()
for entry in manifest:
    for item in entry.get('attachments', []):
        match = pattern.match(item.get('suggestedHumanReadableName', ''))
        source = attachments / item.get('exportedFileName', '')
        if not match or match.group(1) not in allowed or not source.is_file() or source.suffix.lower() != '.png':
            continue
        locale, scene = match.groups()
        target = destination / locale / 'phone' / f'{scene}.png'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        seen.add((locale, scene))
        count += 1
expected = {
    (locale['store'], f'{scene:02d}')
    for locale in locales
    for scene in locale['scenes']
}
print(f'phone: sorted {count} captures from {len(locales)} locales')
if seen != expected:
    missing = sorted(expected - seen)
    extra = sorted(seen - expected)
    raise SystemExit(f'Expected {len(expected)} captures, found {len(seen)}; missing={missing} extra={extra}')
PY

echo "gh-sim job $ID, iPhone 17 Pro Max"
