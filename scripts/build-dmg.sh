#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="$PWD/dist/Routekeeper.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# A versioned volume name prevents Finder from configuring an older mounted
# Routekeeper image when both share the same default volume title.
VOLUME_NAME="Routekeeper ${VERSION}"
OUTPUT="$PWD/dist/Routekeeper-v${VERSION}.dmg"
WORK="$(mktemp -d /tmp/routekeeper-dmg.XXXXXX)"
STAGING="$WORK/staging"
RW_IMAGE="$WORK/Routekeeper-rw.dmg"
MOUNT=""

cleanup() {
    if [[ -n "$MOUNT" ]] && mount | grep -Fq "on $MOUNT "; then
        diskutil eject force "$MOUNT" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

test -d "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$STAGING/.background"
swift scripts/make-dmg-background.swift "$STAGING/.background/background.png"
ditto "$APP" "$STAGING/Routekeeper.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    -quiet \
    "$RW_IMAGE"

ATTACH_OUTPUT="$(hdiutil attach "$RW_IMAGE" -readwrite -noverify)"
MOUNT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '$3 ~ /^\// { print $3; exit }')"
if [[ -z "$MOUNT" || ! -d "$MOUNT" ]]; then
    echo "Could not determine the mounted DMG path." >&2
    exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {220, 120, 860, 540}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to (POSIX file "$MOUNT/.background/background.png" as alias)
        set position of item "Routekeeper.app" of container window to {165, 175}
        set position of item "Applications" of container window to {475, 175}
        update without registering applications
        delay 1
        set the bounds of container window to {220, 120, 860, 540}
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet
rm -f "$OUTPUT"
hdiutil convert "$RW_IMAGE" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" -quiet
hdiutil verify "$OUTPUT"

printf '%s\n' "$OUTPUT"
