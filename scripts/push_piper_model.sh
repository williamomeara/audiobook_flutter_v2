#!/bin/bash
# Push Piper voice model to ReDroid device
# 
# The voice model files can come from:
# 1. /host_models (mounted via docker-compose volume) - PREFERRED
# 2. /sdcard/piper_lessac_us_v1 (manually pushed earlier)
#
# This script copies from whichever source is available.

set -e

DEVICE="localhost:5555"
PACKAGE="io.eist.app"
TARGET_DIR="/data/user/0/$PACKAGE/app_flutter/voice_assets/piper/piper_lessac_us_v1"

echo "=== Pushing Piper voice model to $DEVICE ==="

# Determine source directory by checking docker exec (for mounted /host_models)
if docker exec redroid-redroid-1 test -d /host_models/piper/piper_lessac_us_v1 2>/dev/null; then
    SOURCE_TYPE="docker"
    SOURCE_DIR="/host_models/piper/piper_lessac_us_v1"
    echo "Using docker-mounted /host_models directory"
elif adb -s $DEVICE shell "test -d /sdcard/piper_lessac_us_v1" 2>/dev/null; then
    SOURCE_TYPE="adb"
    SOURCE_DIR="/sdcard/piper_lessac_us_v1"
    TAR_FILE="/sdcard/espeak-ng-data.tar"
    echo "Using manually pushed files on /sdcard"
else
    echo "ERROR: No source voice model found!"
    echo "Please either:"
    echo "  1. Restart ReDroid with docker-compose (mounts /host_models)"
    echo "  2. Manually push files to /sdcard/piper_lessac_us_v1"
    exit 1
fi

# Create target directory
echo "Creating target directory..."
adb -s $DEVICE shell "run-as $PACKAGE mkdir -p $TARGET_DIR"

if [ "$SOURCE_TYPE" = "docker" ]; then
    # Use docker exec to copy from mounted volume
    echo "Copying ONNX model (63MB) via docker..."
    docker exec redroid-redroid-1 sh -c "cat $SOURCE_DIR/en_US-lessac-medium.onnx" | \
        adb -s $DEVICE shell "run-as $PACKAGE sh -c 'cat > $TARGET_DIR/en_US-lessac-medium.onnx'"
    
    echo "Copying JSON config..."
    docker exec redroid-redroid-1 sh -c "cat $SOURCE_DIR/en_US-lessac-medium.onnx.json" | \
        adb -s $DEVICE shell "run-as $PACKAGE sh -c 'cat > $TARGET_DIR/en_US-lessac-medium.onnx.json'"
    
    echo "Copying tokens.txt..."
    docker exec redroid-redroid-1 sh -c "cat $SOURCE_DIR/tokens.txt" | \
        adb -s $DEVICE shell "run-as $PACKAGE sh -c 'cat > $TARGET_DIR/tokens.txt'"
    
    echo "Copying espeak-ng-data directory..."
    docker exec redroid-redroid-1 sh -c "cd $SOURCE_DIR && tar cf - espeak-ng-data" | \
        adb -s $DEVICE shell "run-as $PACKAGE sh -c 'cd $TARGET_DIR && tar xf -'"
else
    # Use adb to copy from /sdcard
    echo "Copying ONNX model (63MB)..."
    adb -s $DEVICE shell "cat $SOURCE_DIR/en_US-lessac-medium.onnx | run-as $PACKAGE sh -c 'cat > $TARGET_DIR/en_US-lessac-medium.onnx'"

    echo "Copying JSON config..."
    adb -s $DEVICE shell "cat $SOURCE_DIR/en_US-lessac-medium.onnx.json | run-as $PACKAGE sh -c 'cat > $TARGET_DIR/en_US-lessac-medium.onnx.json'"

    echo "Copying tokens.txt..."
    adb -s $DEVICE shell "cat $SOURCE_DIR/tokens.txt | run-as $PACKAGE sh -c 'cat > $TARGET_DIR/tokens.txt'"

    echo "Extracting espeak-ng-data from tar..."
    adb -s $DEVICE shell "cat $TAR_FILE | run-as $PACKAGE sh -c 'cd $TARGET_DIR && tar xf -'"
fi

# Create manifest
echo "Creating .manifest..."
adb -s $DEVICE shell "run-as $PACKAGE sh -c 'echo -e \"key=piper/piper_lessac_us_v1\nversion=1\nsha256=unknown\ninstalledAt=\$(date -Iseconds)\" > $TARGET_DIR/.manifest'"

# Verify installation
echo ""
echo "=== Verifying installation ==="
adb -s $DEVICE shell "run-as $PACKAGE ls -la $TARGET_DIR/"

echo ""
echo "=== Done! ==="
echo ""
echo "Restart the app to detect the voice model:"
echo "  adb -s $DEVICE shell am force-stop $PACKAGE"
echo "  adb -s $DEVICE shell am start -n $PACKAGE/com.ryanheise.audioservice.AudioServiceActivity"
