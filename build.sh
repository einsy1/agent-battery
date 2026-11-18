#!/bin/zsh
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$ROOT/agent battery.app"
TASK_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$TASK_BUILD_DIR"' EXIT
APP="$TASK_BUILD_DIR/agent battery.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macos15.0 \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/CodexBattery" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
SWITCHER="$APP/Contents/Resources/ModelSwitcher"
mkdir -p "$SWITCHER"
cp "$ROOT/Resources/ModelSwitcher/switcher.py" "$SWITCHER/"
python3 -m pip --disable-pip-version-check install --no-compile --target "$SWITCHER" \
  -r "$ROOT/Resources/ModelSwitcher/requirements.txt"
mkdir -p "$APP/Contents/Resources/QuotaKeeper"
cp "$ROOT/Resources/QuotaKeeper/"*.py "$APP/Contents/Resources/QuotaKeeper/"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
xattr -cr "$APP"
codesign --force --sign - --identifier local.neil.codexbattery "$APP"
ditto --noextattr --norsrc "$APP" "$OUTPUT"
# Existing output directories can retain Finder metadata and quarantine attributes.
xattr -cr "$OUTPUT"
codesign --force --sign - --identifier local.neil.codexbattery "$OUTPUT"
codesign --verify --deep --strict "$OUTPUT"
echo "$OUTPUT"
