#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Wavebar"
EXECUTABLE_NAME="wavebar"
APP_DIR="dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
CONFIGURATION="debug"
BUILD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ "$BUILD_ONLY" -eq 0 ]]; then
    pkill -f "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}" >/dev/null 2>&1 || true
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
fi

PRODUCT_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
rm -rf "${PRODUCT_DIR}/Wavebar_wavebar.bundle"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "${PRODUCT_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
cp -R "${PRODUCT_DIR}/Wavebar_wavebar.bundle" "${APP_DIR}/Wavebar_wavebar.bundle"

# Create Resources directory and copy the compiled AppIcon.icns
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
mkdir -p "$RESOURCES_DIR"
if [[ -f "Sources/AppIcon.icns" ]]; then
    cp "Sources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "Warning: Sources/AppIcon.icns not found! Please run script/generate_icns.sh first." >&2
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>wavebar</string>
    <key>CFBundleIdentifier</key>
    <string>dev.wavebar.app</string>
    <key>CFBundleName</key>
    <string>Wavebar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Wavebar captures audio input to render the realtime spectrum visualizer.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Wavebar captures routed system audio to render the realtime spectrum visualizer.</string>
</dict>
</plist>
PLIST

echo "Built ${APP_DIR}"

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    exit 0
fi

/usr/bin/open -n "$APP_DIR"
