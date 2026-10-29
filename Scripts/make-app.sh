#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/StepAway.app"

swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/StepAway" "$APP/Contents/MacOS/StepAway"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>StepAway</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.stepaway</string>
    <key>CFBundleName</key>
    <string>StepAway</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>StepAway pauses during calendar events.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built: $APP"
