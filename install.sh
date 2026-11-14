#!/bin/bash
# Installs the latest Oralis from GitHub, with no macOS security warning.
#
#   curl -fsSL https://raw.githubusercontent.com/raja-763/Oralis/main/install.sh | bash
#
# Why there is no warning: macOS only shows its "unidentified developer" prompt for files
# that carry the "downloaded from the internet" mark. A download made by curl is not marked,
# so Oralis opens normally. This script is short and open: read it before you run it.
#
# Optional: INSTALL_DIR=/some/folder to install somewhere other than /Applications.
set -euo pipefail

REPO="raja-763/Oralis"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP="$INSTALL_DIR/Oralis.app"

say() { printf '%s\n' "$*"; }
die() { printf 'Oralis install failed: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Oralis is for macOS."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || die "Oralis needs macOS 14 (Sonoma) or later. This Mac has $(sw_vers -productVersion)."

say "Finding the latest Oralis..."
RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" || die "could not reach GitHub."
export RELEASE_JSON
read_field() {
  osascript -l JavaScript -e '
    ObjC.import("stdlib");
    var release = JSON.parse($.getenv("RELEASE_JSON"));
    var asset = release.assets.find(function (a) { return a.name.endsWith(".dmg"); });
    asset ? asset["'"$1"'"] || "" : ""'
}
DMG_URL="$(read_field browser_download_url)"
EXPECTED="$(read_field digest)"
[ -n "$DMG_URL" ] || die "the latest release has no installer."

WORK="$(mktemp -d /tmp/oralis-install.XXXXXX)"
MNT="$WORK/mount"
cleanup() { hdiutil detach "$MNT" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

say "Downloading Oralis..."
curl -fL --progress-bar -o "$WORK/Oralis.dmg" "$DMG_URL" || die "download failed."

if [ -n "$EXPECTED" ]; then
  ACTUAL="sha256:$(shasum -a 256 "$WORK/Oralis.dmg" | cut -d' ' -f1)"
  [ "$ACTUAL" = "$EXPECTED" ] || die "the download did not match its checksum. Nothing was installed."
  say "Checksum matches."
fi

mkdir -p "$MNT"
hdiutil attach "$WORK/Oralis.dmg" -nobrowse -readonly -mountpoint "$MNT" >/dev/null || die "could not open the download."
[ -d "$MNT/Oralis.app" ] || die "the download does not contain Oralis."

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "com.oralis.app" to quit' >/dev/null 2>&1 || true
sleep 1

say "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
ditto "$MNT/Oralis.app" "$APP" || die "could not copy Oralis to $INSTALL_DIR (try: sudo bash)."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true   # belt and braces

codesign --verify --deep --strict "$APP" || die "the installed app did not pass its signature check."

say ""
say "Oralis is installed in $INSTALL_DIR."
say "Next: open Oralis, choose Settings, and paste your own Anthropic API key to turn on the AI."
say "Optional: add your own ElevenLabs key for natural voices."
[ "$INSTALL_DIR" = "/Applications" ] && open "$APP" || true
