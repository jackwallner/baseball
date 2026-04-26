#!/bin/bash
set -e
exec > >(tee /tmp/testflight.log)
exec 2>&1

echo "=== TestFlight Pipeline Started at $(date) ==="
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="StatScout"
ARCHIVE_PATH="$PROJECT_DIR/build/StatScout.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/StatScout-export"
OPTIONS_PLIST="$PROJECT_DIR/AppStoreUploadOptions.plist"

cd "$PROJECT_DIR"

echo "==> Step 1: Clean"
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" clean 2>&1 || true

echo "==> Step 2: Archive"
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" -configuration Release archive -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS" -allowProvisioningUpdates 2>&1

echo "==> Step 3: Export & Upload"
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist "$OPTIONS_PLIST" -allowProvisioningUpdates 2>&1

echo "==> Done at $(date) ==="
echo "IPA location: $EXPORT_PATH"
ls -la "$EXPORT_PATH" 2>&1 || echo "No export found"
