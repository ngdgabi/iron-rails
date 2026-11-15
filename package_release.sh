#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build/universal_pkg"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Iron Rails.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_PATH="$DIST_DIR/IronRails-Installer-v1.0.0.dmg"
ZIP_PATH="$DIST_DIR/IronRails-macOS-v1.0.0.zip"

SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
MAC_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

SOURCES=(
    "$PROJECT_DIR/Sources/PlatformCompat.swift"
    "$PROJECT_DIR/Sources/Models.swift"
    "$PROJECT_DIR/Sources/AudioSynth.swift"
    "$PROJECT_DIR/Sources/SpriteFactory.swift"
    "$PROJECT_DIR/Sources/CampaignEngine.swift"
    "$PROJECT_DIR/Sources/GameScene.swift"
    "$PROJECT_DIR/Sources/AppMain.swift"
)

FRAMEWORKS=(
    -framework AppKit
    -framework SpriteKit
    -framework AVFoundation
    -framework GameController
    -framework CoreGraphics
    -framework CoreText
    -framework CoreMedia
    -framework CoreVideo
)

echo "==> Preparing Universal 2 packaging directories..."
rm -rf "$BUILD_DIR" "$APP_BUNDLE" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$DMG_STAGING" "$ICONSET_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "==> Building Retina macOS AppIcon.icns..."
cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"/icon_*x*.png "$ICONSET_DIR/"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Compiling Universal 2 Binary (Apple Silicon arm64 + Intel x86_64)..."
"$SWIFTC" -O -sdk "$MAC_SDK" -target arm64-apple-macosx14.0 -parse-as-library \
    "${SOURCES[@]}" "${FRAMEWORKS[@]}" \
    -o "$BUILD_DIR/IronRails-arm64"

"$SWIFTC" -O -sdk "$MAC_SDK" -target x86_64-apple-macosx14.0 -parse-as-library \
    "${SOURCES[@]}" "${FRAMEWORKS[@]}" \
    -o "$BUILD_DIR/IronRails-x86_64"

lipo -create \
    "$BUILD_DIR/IronRails-arm64" \
    "$BUILD_DIR/IronRails-x86_64" \
    -output "$APP_BUNDLE/Contents/MacOS/IronRails"

echo "==> Writing Info.plist & signing Universal 2 macOS App Bundle..."
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/MacOS/IronRails"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Creating commercial ZIP archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Creating Drag-to-Applications DMG Installer..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME"
ln -s /Applications "$DMG_STAGING/Applications"
cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$DMG_STAGING/.VolumeIcon.icns"
hdiutil create -volname "Iron Rails" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

rm -rf "$BUILD_DIR"

echo "SUCCESS! Built Universal 2 macOS Release:"
echo "  App Bundle   : $APP_BUNDLE"
echo "  DMG Installer: $DMG_PATH"
echo "  Release ZIP  : $ZIP_PATH"
