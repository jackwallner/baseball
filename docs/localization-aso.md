# Localization ASO — StatScout

## Backups (2026-05-25 go run)

| Snapshot | Path |
|----------|------|
| Pre-edit pull | `fastlane/metadata.bak.20260525-184838/` |
| Pre-upload | `fastlane/metadata.bak.pre-upload-20260525-184854/` |

## Restore a snapshot

```bash
./scripts/restore-appstore-metadata.sh fastlane/metadata.bak.pre-upload-20260525-184854
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
SKIP_SCREENSHOTS=true ./scripts/upload-appstore-metadata.sh
```

## Draft vs live

| Version | State | Notes |
|---------|-------|-------|
| **1.0** | `READY_FOR_SALE` | Live on App Store |
| **1.1.0** | `PREPARE_FOR_SUBMISSION` | Metadata uploaded via `asc-finish-missed.sh` (2026-05-26) |

State file: `scripts/.asc-state.json`

## Upload commands

```bash
# Full gap-closure (draft + API + deliver)
./scripts/asc-finish-missed.sh

# Metadata only (after eval draft version)
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
SKIP_SCREENSHOTS=true ./scripts/upload-appstore-metadata.sh

# With screenshots
SKIP_SCREENSHOTS=false ./scripts/upload-appstore-metadata.sh
```

Use `scripts/fastlane-bin.sh` (fastlane **2.234+**). Do not use `/usr/local/bin/fastlane` 2.230.

## Keyword dedupe rule

Apple indexes **name + subtitle + keywords**. `scripts/aso-apply-locale-optimizations.py` drops keyword tokens already present in name/subtitle so the 100-char field is not wasted on duplicates.
