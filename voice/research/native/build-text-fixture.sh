#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
APP="$PWD/.cache/native-text/Text Fixture.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O voice/research/native/TextFixture.swift -o "$APP/Contents/MacOS/TextFixture"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.localvoice.TextFixture</string>
<key>CFBundleName</key><string>Text Fixture</string>
<key>CFBundleExecutable</key><string>TextFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
