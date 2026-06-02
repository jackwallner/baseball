#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="StatScout"
ARCHIVE_PATH="$PROJECT_DIR/build/StatScout.xcarchive"

cd "$PROJECT_DIR"

# Supabase config is injected into Info.plist at build time from the environment
# (project.yml: SUPABASE_URL/SUPABASE_ANON_KEY = $(...)). If these aren't set the
# archive bakes in empty/garbage values and the shipped app can't reach the
# backend. Auto-source the canonical creds file, then hard-fail if still missing.
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  [ -f "$HOME/.baseball_credentials" ] && source "$HOME/.baseball_credentials"
fi
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "error: SUPABASE_URL / SUPABASE_ANON_KEY not set and not found in ~/.baseball_credentials." >&2
  echo "       Set them in the environment or that file before shipping." >&2
  exit 1
fi
export SUPABASE_URL SUPABASE_ANON_KEY

# Auto-increment build number so TestFlight never rejects a duplicate
echo "==> Bumping build number..."
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *"\(.*\)".*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
echo "    $CURRENT_BUILD -> $NEXT_BUILD"

echo "==> Regenerating Xcode project..."
if command -v xcodegen &> /dev/null; then
  xcodegen generate
else
  echo "warning: xcodegen not found. Using existing StatScout.xcodeproj."
fi

echo "==> Cleaning..."
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" clean

echo "==> Archiving..."
xcodebuild -project StatScout.xcodeproj -scheme "$SCHEME" -configuration Release archive -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS" -allowProvisioningUpdates

echo "==> Exporting & Uploading..."
exec "$DIR/upload-testflight.sh" "$ARCHIVE_PATH"
