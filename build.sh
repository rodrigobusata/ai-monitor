#!/usr/bin/env bash
#
# build.sh — build AI Monitor, re-sign it, install it to /Applications, and
# refresh the running app + widgets.
#
# Why this exists: code signing is OFF in the project (CODE_SIGNING_ALLOWED = NO),
# so `xcodebuild build` alone leaves an unsigned bundle in DerivedData — and macOS
# discovers the widgets from /Applications, not DerivedData. This script does the
# full loop (build → re-sign appex+app with the stable AIMonitorDev identity →
# install → register → relaunch → bounce widget daemons). See README.md for the
# hand-run version and the gotchas.
#
# Usage:
#   ./build.sh            build, install, relaunch, refresh widgets
#   ./build.sh -g         run `tuist generate` first (after add/rename/delete files)
#   ./build.sh --no-open  build + install but don't relaunch the app
#   ./build.sh -h         show this help

set -euo pipefail

SCHEME="AIMonitor"
IDENTITY="AIMonitorDev"
APP_ENTITLEMENTS="Sources/AIMonitor.entitlements"
WIDGET_ENTITLEMENTS="Widget/AIMonitorWidget.entitlements"
WIDGET_BUNDLE_ID="com.aimonitor.app.widget"

GENERATE=false
OPEN_APP=true

while [ $# -gt 0 ]; do
    case "$1" in
        -g|--generate) GENERATE=true ;;
        --no-open)     OPEN_APP=false ;;
        -h|--help)     sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Always run from the repo root (where this script lives).
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fail early with a clear message if the signing identity is missing.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "error: code-signing identity \"$IDENTITY\" not found in the keychain." >&2
    echo "Create it once via Keychain Access -> Certificate Assistant -> Create a" >&2
    echo "Certificate (type: Code Signing, name: $IDENTITY), then re-run." >&2
    exit 1
fi

if [ "$GENERATE" = true ]; then
    echo "==> tuist generate"
    tuist generate --no-open
fi

echo "==> xcodebuild ($SCHEME)"
xcodebuild -scheme "$SCHEME" -destination 'platform=macOS' build

# Resolve the built bundle from xcodebuild itself, so the DerivedData path hash is
# never hardcoded (it changes if the project moves / is regenerated).
SETTINGS="$(xcodebuild -scheme "$SCHEME" -destination 'platform=macOS' -showBuildSettings 2>/dev/null)"
TARGET_BUILD_DIR="$(awk -F' = ' '/ TARGET_BUILD_DIR =/{print $2; exit}' <<<"$SETTINGS")"
FULL_PRODUCT_NAME="$(awk -F' = ' '/ FULL_PRODUCT_NAME =/{print $2; exit}' <<<"$SETTINGS")"

APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
APPEX="$APP/Contents/PlugIns/AIMonitorWidget.appex"

if [ ! -d "$APP" ]; then
    echo "error: built app not found at $APP" >&2
    exit 1
fi

echo "==> re-sign (appex first, then host app)"
codesign --force --sign "$IDENTITY" --entitlements "$WIDGET_ENTITLEMENTS" "$APPEX"
codesign --force --sign "$IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP"

echo "==> install to /Applications"
killall "$SCHEME" 2>/dev/null || true
rm -rf "/Applications/$FULL_PRODUCT_NAME"
cp -R "$APP" "/Applications/"

echo "==> register with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "/Applications/$FULL_PRODUCT_NAME"

echo "==> refresh widgets (bounce widget daemons)"
killall chronod NotificationCenter 2>/dev/null || true
pluginkit -m -i "$WIDGET_BUNDLE_ID" || true

if [ "$OPEN_APP" = true ]; then
    echo "==> launch"
    open "/Applications/$FULL_PRODUCT_NAME"
fi

echo "==> done"
echo "If a placed widget still shows the old layout, remove it and re-add it from the gallery."
