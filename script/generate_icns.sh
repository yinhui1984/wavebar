#!/usr/bin/env bash
set -euo pipefail

# Find script and root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

INPUT_PNG="/Users/z/.gemini/antigravity/brain/8f73ffa7-5c59-4423-a1f1-958620d0a786/wavebar_app_icon_1779371591897.png"
TEMP_PNG="Sources/AppIcon_transparent.png"
ICONSET_DIR="Sources/AppIcon.iconset"
OUTPUT_ICNS="Sources/AppIcon.icns"

echo "=== Processing Source Icon ==="
swift script/ProcessIcon.swift "$INPUT_PNG" "$TEMP_PNG"

echo "=== Creating Iconset ==="
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Downsample to the required macOS icon resolutions using sips
echo "=== Downsampling with sips ==="
sips -z 16 16     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
sips -z 32 32     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
sips -z 64 64     "$TEMP_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
sips -z 256 256   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
sips -z 512 512   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$TEMP_PNG" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$TEMP_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

echo "=== Compiling Iconset to .icns ==="
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "=== Cleaning Up ==="
rm -rf "$ICONSET_DIR"
rm -f "$TEMP_PNG"

echo "=== Success: Generated ${OUTPUT_ICNS} ==="
ls -lh "$OUTPUT_ICNS"
