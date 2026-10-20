#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ROOT="${ROUTEKEEPER_BUILD_ROOT:-/tmp/routekeeper-release}"
swift build -c release --scratch-path "$BUILD_ROOT"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_ROOT" --show-bin-path)"
APP="$PWD/dist/Routekeeper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Never carry a previously signed extension/profile into an ordinary developer build.
rm -rf "$APP/Contents/Library/SystemExtensions/local.routekeeper.macos.filter.systemextension"
rm -f "$APP/Contents/embedded.provisionprofile"
rm -f "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/Routekeeper" "$APP/Contents/MacOS/Routekeeper"
swift scripts/make-icon.swift "$BUILD_ROOT/Guard.iconset"
iconutil -c icns "$BUILD_ROOT/Guard.iconset" -o "$APP/Contents/Resources/AppIcon-Glass.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.routekeeper.macos</string>
<key>CFBundleName</key><string>Routekeeper</string>
<key>CFBundleDisplayName</key><string>Routekeeper</string>
<key>CFBundleExecutable</key><string>Routekeeper</string>
<key>CFBundleIconFile</key><string>AppIcon-Glass</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.10</string>
<key>CFBundleVersion</key><string>19</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key>
<array>
	<string>en</string>
	<string>zh-Hans</string>
</array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
