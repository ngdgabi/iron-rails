#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
ARCHIVE_PATH="$PROJECT_DIR/build/IronRailsMobile.xcarchive"
EXPORT_DIR="$PROJECT_DIR/dist/AppStore_Export_iOS"
EXPORT_PLIST="$PROJECT_DIR/build/ExportOptions-iOS.plist"
TEAM_ID="${TEAM_ID:-KFDG3WVG6N}"

mkdir -p "$PROJECT_DIR/build" "$EXPORT_DIR"

AUTH_ARGS=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    AUTH_ARGS+=(
        -authenticationKeyPath "$ASC_KEY_PATH"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    )
fi

echo "==> Step 1/2: Archiving Universal iOS & iPadOS Release build (Team: $TEAM_ID)..."
"$XCODEBUILD" archive \
    -project "$PROJECT_DIR/IronRails.xcodeproj" \
    -scheme IronRailsMobile \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGNING_ALLOWED=NO

/usr/libexec/PlistBuddy -c "Set :ApplicationProperties:Team $TEAM_ID" "$ARCHIVE_PATH/Info.plist"

echo "==> Step 2/2: Cloud-Signing & Uploading iOS/iPadOS IPA to App Store Connect..."
"$XCODEBUILD" -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_DIR" \
    "${AUTH_ARGS[@]}"

echo "SUCCESS! Iron Rails: Blue & Gray (Universal iOS & iPadOS) uploaded to App Store Connect!"
