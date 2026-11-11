#!/bin/bash
# build_dmg.sh — Build, sign, and package Oralis as a Gatekeeper-safe DMG.
# No popup on open: quarantine flag is stripped before packaging.
set -euo pipefail

APP_NAME="Oralis"
DMG_NAME="Oralis 4"
DERIVED_DATA="$(pwd)/build"
BUILD_DIR="$DERIVED_DATA/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$(pwd)/build/$DMG_NAME.dmg"

echo "▶ Regenerating Xcode project..."
xcodegen generate

echo "▶ Building $APP_NAME (Release / arm64)..."
xcodebuild \
  -project Oralis.xcodeproj \
  -scheme Oralis \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Build succeeded but $APP_PATH not found. Check DerivedData path."
  exit 1
fi

echo "▶ Stripping extended attributes (quarantine, resource forks)..."
find "$APP_PATH" -exec xattr -c {} \; 2>/dev/null || true

echo "▶ Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_PATH"

echo "▶ Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "▶ Stripping quarantine from DMG..."
xattr -c "$DMG_PATH"

echo ""
echo "✅  Done!"
echo "    $DMG_PATH"
echo ""
echo "    To install: open the DMG → drag Oralis to Applications."
echo "    No Gatekeeper popup — quarantine flag removed."
