#!/bin/sh
set -eu
cd "$(dirname "$0")"
# Check signing before compilation or staging model resources. A stable
# certificate-backed identity preserves the app's designated requirement.
if [ -z "${VOICE_SIGN_IDENTITY:-}" ]; then
    VOICE_SIGN_CANDIDATES=$(security find-identity -v -p codesigning 2>/dev/null || true)
    VOICE_SIGN_IDENTITY=$(printf '%s\n' "$VOICE_SIGN_CANDIDATES" | sed -n '/"Apple Development:/s/.*) \([A-F0-9]*\) .*/\1/p' | head -n 1)
    if [ -z "$VOICE_SIGN_IDENTITY" ]; then
        VOICE_SIGN_IDENTITY=$(printf '%s\n' "$VOICE_SIGN_CANDIDATES" | sed -n '/"Developer ID Application:/s/.*) \([A-F0-9]*\) .*/\1/p' | head -n 1)
    fi
fi
if [ -z "$VOICE_SIGN_IDENTITY" ] || [ "$VOICE_SIGN_IDENTITY" = "-" ]; then
    echo "A certificate-backed code-signing identity is required to preserve macOS permissions. Install a signing certificate or set VOICE_SIGN_IDENTITY to an existing identity. Apple Development and Developer ID Application identities are detected automatically." >&2
    exit 1
fi
swift build -c release
mkdir -p "$PWD/dist"
FINAL_APP="$PWD/dist/Local Voice.app"
STAGING=$(mktemp -d "$PWD/dist/.voice-build-XXXXXX")
INSTALLED=0
cleanup() {
    if [ -d "$STAGING/previous.app" ] && [ "$INSTALLED" -ne 1 ]; then
        if [ -e "$FINAL_APP" ] || ! mv "$STAGING/previous.app" "$FINAL_APP"; then
            printf 'Previous app preserved at: %s\n' "$STAGING/previous.app" >&2
            return
        fi
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
APP="$STAGING/Local Voice.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LocalVoice "$APP/Contents/MacOS/LocalVoice"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.localvoice.prototype</string>
<key>CFBundleName</key><string>Local Voice</string>
<key>CFBundleExecutable</key><string>LocalVoice</string>
<key>LSUIElement</key><true/>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>NSMicrophoneUsageDescription</key><string>Listen to your explicitly enabled voice commands on this Mac.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Transcribe commands using on-device recognition only.</string>
<key>NSAppleEventsUsageDescription</key><string>Create notes, browser tabs, and documents when you explicitly request these actions.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources"
# Workers and command-model weights travel with the app. The selected Python and
# GoClick environment remain machine-local dependencies.
"${VOICE_PYTHON:-python3}" tools/stage_runtime.py --resources "$APP/Contents/Resources" --vision "${VOICE_VISION:-required}"
codesign --force --sign "$VOICE_SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
if [ -d "$FINAL_APP" ]; then mv "$FINAL_APP" "$STAGING/previous.app"; fi
if ! mv "$APP" "$FINAL_APP"; then
    exit 1
fi
INSTALLED=1
printf '%s\n' "$FINAL_APP"
