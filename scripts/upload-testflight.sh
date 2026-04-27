#!/bin/bash
set -eu

IPA_PATH="${1:-}"
if [ -z "$IPA_PATH" ]; then
  echo "Usage: $0 <path-to-ipa>"
  exit 1
fi

: "${APPSTORE_APPLE_ID:?APPSTORE_APPLE_ID env var is required}"
: "${APPSTORE_USERNAME:?APPSTORE_USERNAME env var is required}"

echo "==> Uploading $IPA_PATH to TestFlight..."

xcrun altool --upload-app --type ios \
  --file "$IPA_PATH" \
  --apple-id "$APPSTORE_APPLE_ID" \
  --username "$APPSTORE_USERNAME" \
  --password "@keychain:App Store Connect"

echo "==> Upload complete!"
