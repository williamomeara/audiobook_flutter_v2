#!/bin/bash

# Audiobook Flutter Compression Test Script
# Runs automated verification tests on Pixel 8 device

DEVICE_SERIAL="39081FDJH00FEB"
APP_PACKAGE="io.eist.app"
TEST_RESULTS_FILE="/tmp/compression_test_results.txt"
LOG_FILE="/tmp/compression_test.log"

echo "=== Audiobook Flutter Compression Test Suite ===" | tee "$TEST_RESULTS_FILE"
echo "Device: $DEVICE_SERIAL" | tee -a "$TEST_RESULTS_FILE"
echo "Timestamp: $(date)" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 1: Check if app is installed
echo "TEST 1: Verify App Installation" | tee -a "$TEST_RESULTS_FILE"
echo "================================" | tee -a "$TEST_RESULTS_FILE"
if adb -s "$DEVICE_SERIAL" shell pm list packages | grep -q "$APP_PACKAGE"; then
    echo "✅ PASS: App is installed" | tee -a "$TEST_RESULTS_FILE"
else
    echo "❌ FAIL: App is not installed" | tee -a "$TEST_RESULTS_FILE"
    echo "Install with: flutter build apk && adb install -r build/app/outputs/apk/release/app-release.apk" | tee -a "$TEST_RESULTS_FILE"
    exit 1
fi
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 2: Check cache directory exists
echo "TEST 2: Verify Cache Directory" | tee -a "$TEST_RESULTS_FILE"
echo "===============================" | tee -a "$TEST_RESULTS_FILE"
CACHE_DIR="/data/user/0/$APP_PACKAGE/app_flutter"
if adb -s "$DEVICE_SERIAL" shell test -d "$CACHE_DIR" && echo "exist"; then
    echo "✅ PASS: Cache directory exists at $CACHE_DIR" | tee -a "$TEST_RESULTS_FILE"
else
    echo "⚠️  Cache directory not yet created (will be created on first synthesis)" | tee -a "$TEST_RESULTS_FILE"
fi
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 3: Count existing WAV files
echo "TEST 3: List Existing Audio Cache Files" | tee -a "$TEST_RESULTS_FILE"
echo "=======================================" | tee -a "$TEST_RESULTS_FILE"
echo "Current WAV files:" | tee -a "$TEST_RESULTS_FILE"
adb -s "$DEVICE_SERIAL" shell find "$CACHE_DIR" -name "*.wav" 2>/dev/null | wc -l | xargs echo "  Count:" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"
echo "Current M4A files:" | tee -a "$TEST_RESULTS_FILE"
adb -s "$DEVICE_SERIAL" shell find "$CACHE_DIR" -name "*.m4a" 2>/dev/null | wc -l | xargs echo "  Count:" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 4: Check compression setting in SQLite
echo "TEST 4: Verify Compression Setting" | tee -a "$TEST_RESULTS_FILE"
echo "===================================" | tee -a "$TEST_RESULTS_FILE"
SETTINGS_DB="/data/user/0/$APP_PACKAGE/databases/app_settings.db"
SETTING_QUERY="SELECT value FROM settings WHERE key='compressOnSynthesize';"
COMPRESS_ENABLED=$(adb -s "$DEVICE_SERIAL" shell "sqlite3 $SETTINGS_DB '$SETTING_QUERY' 2>/dev/null" | tr -d '\r')
if [ -z "$COMPRESS_ENABLED" ]; then
    echo "ℹ️  Setting not yet written (will use default: true)" | tee -a "$TEST_RESULTS_FILE"
elif [ "$COMPRESS_ENABLED" = "1" ] || [ "$COMPRESS_ENABLED" = "true" ]; then
    echo "✅ PASS: Compression setting is ENABLED" | tee -a "$TEST_RESULTS_FILE"
else
    echo "❌ FAIL: Compression setting is DISABLED (value: $COMPRESS_ENABLED)" | tee -a "$TEST_RESULTS_FILE"
fi
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 5: Monitor app logs during synthesis
echo "TEST 5: Prepare for Live Synthesis Test" | tee -a "$TEST_RESULTS_FILE"
echo "=======================================" | tee -a "$TEST_RESULTS_FILE"
echo "This test requires manual interaction:" | tee -a "$TEST_RESULTS_FILE"
echo "1. Open the app on Pixel 8 (should auto-launch)" | tee -a "$TEST_RESULTS_FILE"
echo "2. Navigate to any book with chapters" | tee -a "$TEST_RESULTS_FILE"
echo "3. Press PLAY to start synthesis" | tee -a "$TEST_RESULTS_FILE"
echo "4. Watch for 'Scheduled background compression' in logs" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 6: Capture live logs
echo "TEST 6: Capture Device Logs" | tee -a "$TEST_RESULTS_FILE"
echo "============================" | tee -a "$TEST_RESULTS_FILE"
echo "Starting 30-second log capture..." | tee -a "$TEST_RESULTS_FILE"
echo "Look for messages containing:" | tee -a "$TEST_RESULTS_FILE"
echo "  - 'Scheduled background compression'" | tee -a "$TEST_RESULTS_FILE"
echo "  - 'Background compressed'" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Capture logs
adb -s "$DEVICE_SERIAL" logcat -c 2>/dev/null
echo "Logs cleared. Monitoring for 30 seconds..." | tee -a "$TEST_RESULTS_FILE"
timeout 30s adb -s "$DEVICE_SERIAL" logcat -v threadtime 2>/dev/null | tee -a "$LOG_FILE" &
LOGCAT_PID=$!

# Wait a bit for logs to start
sleep 2
echo "To see compression in action, manually trigger synthesis on the device now." | tee -a "$TEST_RESULTS_FILE"
echo "Press PLAY in a book to start synthesis..." | tee -a "$TEST_RESULTS_FILE"

# Wait for logcat to finish
wait $LOGCAT_PID 2>/dev/null

echo "" | tee -a "$TEST_RESULTS_FILE"
echo "Log capture complete. Analyzing results..." | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 7: Analyze captured logs
echo "TEST 7: Analyze Compression Log Messages" | tee -a "$TEST_RESULTS_FILE"
echo "========================================" | tee -a "$TEST_RESULTS_FILE"

SCHEDULED_COUNT=$(grep -c "Scheduled background compression" "$LOG_FILE" 2>/dev/null || echo "0")
COMPRESSED_COUNT=$(grep -c "Background compressed" "$LOG_FILE" 2>/dev/null || echo "0")
SYNTHESIZE_COUNT=$(grep -c "Synthesizing text" "$LOG_FILE" 2>/dev/null || echo "0")

echo "Synthesis events found: $SYNTHESIZE_COUNT" | tee -a "$TEST_RESULTS_FILE"
echo "Compression scheduled messages: $SCHEDULED_COUNT" | tee -a "$TEST_RESULTS_FILE"
echo "Compression completed messages: $COMPRESSED_COUNT" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

if [ "$SCHEDULED_COUNT" -gt 0 ]; then
    echo "✅ PASS: Compression scheduler messages found" | tee -a "$TEST_RESULTS_FILE"
    echo "Sample messages:" | tee -a "$TEST_RESULTS_FILE"
    grep "Scheduled background compression" "$LOG_FILE" 2>/dev/null | head -3 | sed 's/^/  /' | tee -a "$TEST_RESULTS_FILE"
else
    echo "⚠️  No compression scheduler messages found" | tee -a "$TEST_RESULTS_FILE"
    echo "This could mean:" | tee -a "$TEST_RESULTS_FILE"
    echo "  - No synthesis occurred yet" | tee -a "$TEST_RESULTS_FILE"
    echo "  - Compression setting is disabled" | tee -a "$TEST_RESULTS_FILE"
    echo "  - Different log tag is used" | tee -a "$TEST_RESULTS_FILE"
fi
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 8: Verify cache file conversion
echo "TEST 8: Verify Cache File Conversion (WAV → M4A)" | tee -a "$TEST_RESULTS_FILE"
echo "================================================" | tee -a "$TEST_RESULTS_FILE"
echo "Checking for converted audio files..." | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

WAV_FILES=$(adb -s "$DEVICE_SERIAL" shell find "$CACHE_DIR" -name "*.wav" 2>/dev/null)
M4A_FILES=$(adb -s "$DEVICE_SERIAL" shell find "$CACHE_DIR" -name "*.m4a" 2>/dev/null)

echo "WAV files found:" | tee -a "$TEST_RESULTS_FILE"
echo "$WAV_FILES" | sed 's/^/  /' | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

echo "M4A files found:" | tee -a "$TEST_RESULTS_FILE"
echo "$M4A_FILES" | sed 's/^/  /' | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 9: Calculate cache compression ratio
echo "TEST 9: Cache Compression Ratio" | tee -a "$TEST_RESULTS_FILE"
echo "===============================" | tee -a "$TEST_RESULTS_FILE"

if [ -n "$M4A_FILES" ]; then
    echo "Calculating file sizes..." | tee -a "$TEST_RESULTS_FILE"
    TOTAL_WAV=0
    TOTAL_M4A=0
    
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        SIZE=$(adb -s "$DEVICE_SERIAL" shell stat -c%s "$file" 2>/dev/null)
        TOTAL_WAV=$((TOTAL_WAV + SIZE))
    done <<< "$WAV_FILES"
    
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        SIZE=$(adb -s "$DEVICE_SERIAL" shell stat -c%s "$file" 2>/dev/null)
        TOTAL_M4A=$((TOTAL_M4A + SIZE))
    done <<< "$M4A_FILES"
    
    echo "Total WAV size: $((TOTAL_WAV / 1024)) KB" | tee -a "$TEST_RESULTS_FILE"
    echo "Total M4A size: $((TOTAL_M4A / 1024)) KB" | tee -a "$TEST_RESULTS_FILE"
    
    if [ "$TOTAL_WAV" -gt 0 ] && [ "$TOTAL_M4A" -gt 0 ]; then
        RATIO=$((TOTAL_WAV / TOTAL_M4A))
        echo "✅ Compression Ratio: $RATIO:1 (expected ~17:1)" | tee -a "$TEST_RESULTS_FILE"
    fi
else
    echo "No M4A files yet - synthesis/compression may not have completed" | tee -a "$TEST_RESULTS_FILE"
fi
echo "" | tee -a "$TEST_RESULTS_FILE"

# Test 10: Performance assessment
echo "TEST 10: Performance Assessment" | tee -a "$TEST_RESULTS_FILE"
echo "===============================" | tee -a "$TEST_RESULTS_FILE"
echo "Manual checks needed:" | tee -a "$TEST_RESULTS_FILE"
echo "  ✓ Synthesis started immediately after pressing PLAY?" | tee -a "$TEST_RESULTS_FILE"
echo "  ✓ Audio played without stuttering?" | tee -a "$TEST_RESULTS_FILE"
echo "  ✓ No noticeable pause when compression started?" | tee -a "$TEST_RESULTS_FILE"
echo "  ✓ UI remained responsive?" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"

# Summary
echo "=== Test Summary ===" | tee -a "$TEST_RESULTS_FILE"
echo "Results saved to: $TEST_RESULTS_FILE" | tee -a "$TEST_RESULTS_FILE"
echo "Full logs saved to: $LOG_FILE" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"
echo "To review compression messages:" | tee -a "$TEST_RESULTS_FILE"
echo "  grep 'compress' $LOG_FILE" | tee -a "$TEST_RESULTS_FILE"
echo "" | tee -a "$TEST_RESULTS_FILE"
cat "$TEST_RESULTS_FILE"
