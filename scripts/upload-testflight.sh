#!/bin/bash
set -e

IPA_PATH="${1:-}"
if [ -z "$IPA_PATH" ]; then
  echo "Usage: $0 <path-to-ipa>"
  exit 1
fi

echo "==> Uploading $IPA_PATH to TestFlight..."

xcrun altool --upload-app --type ios \
  --file "$IPA_PATH" \
  --apple-id "6763945657" \
  --username "jack.wallner@gmail.com" \
  --password "@keychain:App Store Connect"

echo "==> Upload complete!"
