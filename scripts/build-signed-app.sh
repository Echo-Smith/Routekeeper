#!/bin/bash
# Build only. Does not install, activate, notarize, or change network settings.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ROUTEKEEPER_SIGN_IDENTITY:?Set an Apple Development or Developer ID Application signing identity}"
: "${ROUTEKEEPER_TEAM_ID:?Set your Apple Developer Team ID}"
: "${ROUTEKEEPER_APP_PROFILE:?Set the path to the app provisioning profile}"
: "${ROUTEKEEPER_FILTER_PROFILE:?Set the path to the filter provisioning profile}"
[[ "$ROUTEKEEPER_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid Team ID" >&2; exit 1; }
test -f "$ROUTEKEEPER_APP_PROFILE"
test -f "$ROUTEKEEPER_FILTER_PROFILE"
PROFILE_TMP="$(mktemp -d)"
trap 'rm -rf "$PROFILE_TMP"' EXIT
NETWORK_PROVIDER=""
validate_profile() {
  local path expected require_install decoded app_id provider_values provider
  path="$1"
  expected="$2"
  require_install="$3"
  decoded="$PROFILE_TMP/$(basename "$path").plist"
  /usr/bin/openssl cms -inform DER -in "$path" -verify -noverify -out "$decoded" >/dev/null 2>&1
  [[ "$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$decoded")" == "$ROUTEKEEPER_TEAM_ID" ]] || { echo "Provisioning profile Team ID mismatch: $path" >&2; exit 1; }
  app_id="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$decoded" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$decoded")"
  [[ "$app_id" == *".$expected" ]] || { echo "Provisioning profile App ID mismatch: $path" >&2; exit 1; }
  provider_values="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.networking.networkextension" "$decoded")"
  if [[ "$provider_values" == *"content-filter-provider-systemextension"* ]]; then
    provider="content-filter-provider-systemextension"
  elif [[ "$provider_values" == *"content-filter-provider"* ]]; then
    provider="content-filter-provider"
  else
    echo "Provisioning profile lacks content filter entitlement: $path" >&2
    exit 1
  fi
  if [[ -z "$NETWORK_PROVIDER" ]]; then
    NETWORK_PROVIDER="$provider"
  elif [[ "$NETWORK_PROVIDER" != "$provider" ]]; then
    echo "App and filter profiles use different content filter entitlements" >&2
    exit 1
  fi
  if [[ "$require_install" == "yes" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.system-extension.install" "$decoded")" == "true" ]] || { echo "App provisioning profile lacks system-extension.install: $path" >&2; exit 1; }
  fi
}
validate_profile "$ROUTEKEEPER_APP_PROFILE" "local.routekeeper.macos" yes
validate_profile "$ROUTEKEEPER_FILTER_PROFILE" "local.routekeeper.macos.filter" no
bash scripts/build-app.sh
BUILD_ROOT="${ROUTEKEEPER_BUILD_ROOT:-/tmp/routekeeper-release}"
swift build -c release --product RoutekeeperFilter --scratch-path "$BUILD_ROOT"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_ROOT" --show-bin-path)"
APP="$PWD/dist/Routekeeper.app"
EXT="$APP/Contents/Library/SystemExtensions/local.routekeeper.macos.filter.systemextension"
mkdir -p "$EXT/Contents/MacOS"
cp "$BIN_DIR/RoutekeeperFilter" "$EXT/Contents/MacOS/RoutekeeperFilter"
cp NetworkExtension/Info.plist "$EXT/Contents/Info.plist"
cp "$ROUTEKEEPER_FILTER_PROFILE" "$EXT/Contents/embedded.provisionprofile"
cp "$ROUTEKEEPER_APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
/usr/libexec/PlistBuddy -c "Add :NetworkExtension:NEMachServiceName string ${ROUTEKEEPER_TEAM_ID}.local.routekeeper.macos.filter" "$EXT/Contents/Info.plist"
cp NetworkExtension/Filter.entitlements "$PROFILE_TMP/Filter.entitlements"
cp scripts/App.entitlements "$PROFILE_TMP/App.entitlements"
/usr/libexec/PlistBuddy -c "Set :com.apple.developer.networking.networkextension:0 $NETWORK_PROVIDER" "$PROFILE_TMP/Filter.entitlements"
/usr/libexec/PlistBuddy -c "Set :com.apple.developer.networking.networkextension:0 $NETWORK_PROVIDER" "$PROFILE_TMP/App.entitlements"
codesign --force --options runtime --timestamp --sign "$ROUTEKEEPER_SIGN_IDENTITY" --entitlements "$PROFILE_TMP/Filter.entitlements" "$EXT"
codesign --force --options runtime --timestamp --sign "$ROUTEKEEPER_SIGN_IDENTITY" --entitlements "$PROFILE_TMP/App.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "Signed build complete with $NETWORK_PROVIDER. Install in /Applications and obtain system approval before testing."
