#!/bin/bash
# Builds the app and installs it as "/Applications/Live Captions.app", then opens it.
# The app is ad-hoc signed, so macOS asks for system audio access again after each install.
# Set CODESIGN_IDENTITY to a stable signing identity to avoid that.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/LiveCaptions.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LiveCaptions "$APP/Contents/MacOS/LiveCaptions"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"

INSTALLED="/Applications/Live Captions.app"
# Quit the running copy before replacing it.
pkill -x LiveCaptions || true
sleep 1
rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"
# Nudge Finder and the Dock to pick up a changed icon.
touch "$INSTALLED"
echo "Installed $INSTALLED"
open "$INSTALLED"
