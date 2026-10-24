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
rm -f "$APP/Contents/Resources/Assets.car"
rm -f "$APP/Contents/Resources/AppIcon-Glass.icns"
rm -f "$APP/Contents/Resources/AppIcon-Routekeeper.icns"
cp "$BIN_DIR/Routekeeper" "$APP/Contents/MacOS/Routekeeper"
# SwiftPM currently records the deployment target in LC_BUILD_VERSION's SDK
# field. Correct it so AppKit can opt into the SDK's current window appearance.
xcrun vtool -set-build-version macos 14.0 "$(xcrun --sdk macosx --show-sdk-version)" \
    -replace -output "$APP/Contents/MacOS/Routekeeper.sdk" \
    "$APP/Contents/MacOS/Routekeeper"
mv "$APP/Contents/MacOS/Routekeeper.sdk" "$APP/Contents/MacOS/Routekeeper"
rm -rf "$BUILD_ROOT/Guard.iconset" "$BUILD_ROOT/AppIcon.icon" "$BUILD_ROOT/IconCompile"
swift scripts/make-icon.swift "$BUILD_ROOT/Guard.iconset" "$BUILD_ROOT/AppIcon.icon"
mkdir -p "$BUILD_ROOT/IconCompile"
xcrun actool \
    --compile "$BUILD_ROOT/IconCompile" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --standalone-icon-behavior all \
    --output-partial-info-plist "$BUILD_ROOT/IconCompile/partial-info.plist" \
    --output-format human-readable-text \
    "$BUILD_ROOT/AppIcon.icon"
cp "$BUILD_ROOT/IconCompile/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD_ROOT/IconCompile/Assets.car" "$APP/Contents/Resources/Assets.car"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.routekeeper.macos</string>
<key>CFBundleName</key><string>Routekeeper</string>
<key>CFBundleDisplayName</key><string>Routekeeper</string>
<key>CFBundleExecutable</key><string>Routekeeper</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.12</string>
<key>CFBundleVersion</key><string>24</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key>
<array>
	<string>en</string>
	<string>zh-Hans</string>
</array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict>
<key>NSAllowsLocalNetworking</key><true/>
</dict>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
if [[ -n "${ROUTEKEEPER_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
        --sign "$ROUTEKEEPER_SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
