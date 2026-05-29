#!/usr/bin/env bash
# Build StreakTracker and assemble a menu-bar-only .app bundle (no full Xcode needed).
set -euo pipefail

APP_NAME="StreakTracker"
DISPLAY_NAME="Streak Tracker"
BUNDLE_ID="com.saltxd.streaktracker"
VERSION="1.0.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/.build/release/$APP_NAME"
APP="$ROOT/$APP_NAME.app"

echo "▶ Building (release)…"
swift build -c release

echo "▶ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▶ Ad-hoc signing…"
codesign --force --sign - "$APP"

echo ""
echo "✅ Built $APP"
echo ""
echo "  Try it now:   open \"$APP\""
echo "  Install it:   cp -R \"$APP\" /Applications/ && open \"/Applications/$APP_NAME.app\""
echo ""
echo "  (For 'Launch at login' to stick, run it from /Applications and approve it"
echo "   in System Settings › General › Login Items if macOS asks.)"
