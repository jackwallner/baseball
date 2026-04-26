#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="StatScout"
ARCHIVE_PATH="$PROJECT_DIR/build/StatScout.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/StatScout-export"
OPTIONS_PLIST="$PROJECT_DIR/AppStoreUploadOptions.plist"

cd "$PROJECT_DIR"

# Clean
echo "==> Cleaning..."
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" clean

# Archive
echo "==> Archiving..."
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" -configuration Release archive -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS"

# Export
echo "==> Exporting..."
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist "$OPTIONS_PLIST"

# Upload
echo "==> Uploading to TestFlight..."
"$DIR/upload-testflight.sh" "$EXPORT_PATH/StatScout.ipa"

echo "==> Done!"
