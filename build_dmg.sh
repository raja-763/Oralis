#!/bin/bash
# build_dmg.sh — build a DMG of Oralis that is safe to give to other people.
#
#   ./build_dmg.sh
#       Keyless, universal (Apple silicon + Intel), ad-hoc signed DMG. macOS shows a
#       one-time "unidentified developer" warning, which the README inside the DMG
#       explains how to pass.
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="oralis-notary" ./build_dmg.sh
#       Once you have an Apple Developer Program membership: signs with Developer ID,
#       notarizes and staples, so there is no warning at all. Create the profile once with
#       xcrun notarytool store-credentials oralis-notary
#
# Your personal API keys (Secrets.xcconfig) are NEVER put into this build: every secret is
# overridden to empty, and the script fails if any secret value is found in the app.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Oralis"
# Build and sign in a temporary folder OUTSIDE iCloud Drive. Folders such as Desktop and
# Documents are synced by iCloud, which silently adds Finder attributes to the .app folder;
# those break the code signature and make macOS call the app "damaged" on other Macs.
WORK="$(mktemp -d /private/tmp/oralis-dmg.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
DERIVED="$WORK/derived"
APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
STAGING="$WORK/staging"
WORK_DMG="$WORK/$APP_NAME.dmg"
DMG_PATH="$(pwd)/build/$APP_NAME.dmg"
ENTITLEMENTS="Sources/Aria/Resources/Oralis.entitlements"

echo "▶ Regenerating Xcode project..."
xcodegen generate >/dev/null

echo "▶ Building $APP_NAME (Release, universal, no secrets)..."
rm -rf "$DERIVED"
xcodebuild \
  -project Oralis.xcodeproj -scheme Oralis -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ANTHROPIC_API_KEY="" ANTHROPIC_WORKSPACE_ID="" ELEVENLABS_API_KEY="" \
  GOOGLE_OAUTH_CLIENT_SECRET="" ELEVENLABS_PROXY_URL="" ORALIS_PROXY_URL="" \
  build | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

[ -d "$APP_PATH" ] || { echo "❌ Build failed: $APP_PATH not found."; exit 1; }

echo "▶ Cleaning extended attributes..."
xattr -cr "$APP_PATH"

# Release entitlements only: no debug entitlements (get-task-allow), which other Macs reject.
SIGN_ID="${DEVELOPER_ID:--}"
echo "▶ Signing with: ${DEVELOPER_ID:-ad-hoc}..."
TIMESTAMP_FLAG="--timestamp=none"
[ -n "${DEVELOPER_ID:-}" ] && TIMESTAMP_FLAG="--timestamp"
codesign --force --deep --options runtime $TIMESTAMP_FLAG \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP_PATH"

echo "▶ Verifying the app..."
fail() { echo "❌ $1"; exit 1; }

codesign --verify --deep --strict "$APP_PATH" || fail "Code signature is not valid."

ARCHS_FOUND="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
[[ "$ARCHS_FOUND" == *arm64* && "$ARCHS_FOUND" == *x86_64* ]] || fail "Not universal (found: $ARCHS_FOUND)."

ENT="$(codesign -d --entitlements - "$APP_PATH" 2>&1)"
echo "$ENT" | grep -q "get-task-allow" && fail "Debug entitlement get-task-allow is present."

PLIST="$APP_PATH/Contents/Info.plist"
for KEY in ANTHROPIC_API_KEY ELEVENLABS_API_KEY GOOGLE_OAUTH_CLIENT_SECRET ANTHROPIC_WORKSPACE_ID; do
  VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$PLIST" 2>/dev/null || true)"
  [ -z "$VALUE" ] || fail "$KEY is set inside the app."
done

# Every secret value from the personal config must be absent from the whole bundle.
if [ -f Secrets.xcconfig ]; then
  while IFS= read -r VALUE; do
    [ ${#VALUE} -ge 8 ] || continue
    if grep -rqF -- "$VALUE" "$APP_PATH" 2>/dev/null; then fail "A secret from Secrets.xcconfig is inside the app."; fi
  done < <(grep -E '^(ANTHROPIC_API_KEY|ELEVENLABS_API_KEY|GOOGLE_OAUTH_CLIENT_SECRET|ANTHROPIC_WORKSPACE_ID)[[:space:]]*=' Secrets.xcconfig \
           | sed -E 's/^[^=]+=[[:space:]]*//' | tr -d ' \r')
fi
echo "   ✓ valid signature  ✓ universal ($ARCHS_FOUND)  ✓ no debug entitlement  ✓ no secrets inside"

echo "▶ Building the DMG contents..."
mkdir -p "$STAGING"
ditto --noextattr --norsrc "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/READ ME FIRST.txt" <<'EOF'
OPENING ORALIS FOR THE FIRST TIME
=================================

1. Drag Oralis onto the Applications folder, next to it in this window.

2. Open your Applications folder, find Oralis, then Control-click it (with VoiceOver,
   press Control+Option+Shift+M to open its menu) and choose Open.

3. macOS will say it cannot verify the developer. Choose Open. You only do this once.

If there is no Open button (macOS 15 or later):
   a. Open System Settings, then Privacy & Security.
   b. Scroll to the Security section and choose "Open Anyway" next to Oralis.
   c. Enter your password, then choose Open.

Or, in Terminal, run this once and then open Oralis normally:
   xattr -dr com.apple.quarantine /Applications/Oralis.app

WHY THIS APPEARS
Oralis is not sold through the App Store and is not yet registered with Apple, so macOS
asks you to confirm the first time. Nothing is wrong with the download.

REQUIREMENTS
- macOS 14 (Sonoma) or later, Apple silicon or Intel.
- To use the AI, open Oralis, choose Settings, and paste your own Anthropic API key
  (create one at console.anthropic.com). It is stored only on your Mac.
- Oralis asks for the microphone, speech recognition, contacts and calendar the first
  time each is needed. Choose Allow.
EOF

echo "▶ Creating the DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$WORK_DMG" >/dev/null
hdiutil verify "$WORK_DMG" >/dev/null || fail "The DMG did not verify."

echo "▶ Checking the app as users will receive it (mounted from the DMG)..."
MNT="$(mktemp -d /private/tmp/oralis-mnt.XXXXXX)"
hdiutil attach "$WORK_DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
codesign --verify --deep --strict "$MNT/$APP_NAME.app" || fail "The app inside the DMG has an invalid signature."
echo "   ✓ the app inside the DMG verifies"
hdiutil detach "$MNT" >/dev/null
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$(dirname "$DMG_PATH")"
cp "$WORK_DMG" "$DMG_PATH"

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▶ Signing the DMG and notarizing with Apple (this takes a few minutes)..."
  codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  echo "   ✓ notarized and stapled: opens with no warning"
else
  echo "   ℹ Not notarized: macOS shows a one-time warning (explained in READ ME FIRST.txt)."
fi

echo ""
echo "✅ Done: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
