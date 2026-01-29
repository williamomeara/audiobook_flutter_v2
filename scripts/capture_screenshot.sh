#!/bin/bash
# Screenshot capture script for Play Store assets
# Usage: ./capture_screenshot.sh [name]

DEVICE="-s 39081FDJH00FEB"
OUTPUT_DIR="/home/william/Projects/audiobook_flutter_v2/assets/store/screenshots/phone"

# Get screenshot name from argument or use timestamp
NAME="${1:-screenshot_$(date +%Y%m%d_%H%M%S)}"

# Capture screenshot
OUTPUT_FILE="$OUTPUT_DIR/${NAME}.png"
adb $DEVICE exec-out screencap -p > "$OUTPUT_FILE"

# Verify and show info
if [ -f "$OUTPUT_FILE" ]; then
    SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    DIMS=$(file "$OUTPUT_FILE" | grep -oE '[0-9]+ x [0-9]+')
    echo "✅ Saved: $OUTPUT_FILE"
    echo "   Size: $SIZE"
    echo "   Dimensions: $DIMS"
else
    echo "❌ Failed to capture screenshot"
    exit 1
fi
