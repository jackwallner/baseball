#!/usr/bin/env bash
# Upload to TestFlight via xcodebuild -exportArchive with AppStoreUploadOptions.plist
# (destination=upload, method=app-store-connect) and -allowProvisioningUpdates,
# so Xcode uses your local App Store Connect / Apple ID session (no password needed).
#
# Same pattern as ../vitals/scripts/upload-testflight.sh
#
# Prerequisites: Xcode signed in (Xcode → Settings → Accounts) with team YXG4MP6W39.
#
# Usage:
#   ./scripts/upload-testflight.sh [path/to/StatScout.xcarchive]
#
# Default archive: ./build/StatScout.xcarchive

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/StatScout.xcarchive}"
STAGING="$ROOT/build/upload-staging"
PLIST="$ROOT/AppStoreUploadOptions.plist"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  echo "Create one first, e.g.:" >&2
  cat >&2 <<'EOF'
  cd baseball && bash scripts/testflight.sh
EOF
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "error: missing $PLIST" >&2
  exit 1
fi

mkdir -p "$STAGING"
echo "Uploading archive via App Store Connect (local Xcode session)..."
echo "  archive: $ARCHIVE"
echo "  plist:   $PLIST"

# The Xcode account session expires without warning ("App Store Connect access
# for YXG4MP6W39 is required"). The shared ASC API key doesn't, so use it when
# ~/.baseball_credentials provides one.
AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_API_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_API_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STAGING" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates \
  "${AUTH[@]}"

echo "If upload succeeded, check App Store Connect → TestFlight for \"Processing\"."
