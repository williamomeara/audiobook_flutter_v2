#!/bin/bash
# Script to pull the latest database from the device and open in DB Browser

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DB_DEBUG_DIR="$PROJECT_DIR/local_dev/db_debug"
DB_FILE="$DB_DEBUG_DIR/eist_audiobook.db"

# Create directory if needed
mkdir -p "$DB_DEBUG_DIR"

# Get the device ID (prefer physical device over emulator)
DEVICE=$(adb devices | grep -v "emulator" | grep "device$" | head -1 | cut -f1)
if [ -z "$DEVICE" ]; then
    DEVICE=$(adb devices | grep "device$" | head -1 | cut -f1)
fi

if [ -z "$DEVICE" ]; then
    echo "❌ No device connected"
    exit 1
fi

echo "📱 Using device: $DEVICE"
echo "📂 Pulling database..."

# Pull the database
adb -s "$DEVICE" exec-out run-as io.eist.app cat app_flutter/eist_audiobook.db > "$DB_FILE"

# Verify it's a valid SQLite database
FILE_TYPE=$(file "$DB_FILE")
if [[ "$FILE_TYPE" == *"SQLite"* ]]; then
    echo "✅ Database pulled successfully: $DB_FILE"
    echo "📊 Size: $(ls -lh "$DB_FILE" | awk '{print $5}')"
    
    # Show quick summary
    echo ""
    echo "📋 Quick Summary:"
    sqlite3 "$DB_FILE" "SELECT 'Books: ' || count(*) FROM books"
    sqlite3 "$DB_FILE" "SELECT 'Chapters: ' || count(*) FROM chapters"
    sqlite3 "$DB_FILE" "SELECT 'Segments: ' || count(*) FROM segments"
    sqlite3 "$DB_FILE" "SELECT 'Cache entries: ' || count(*) FROM cache_entries"
    
    # Open in DB Browser if available and we have a display
    if command -v sqlitebrowser &> /dev/null; then
        if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
            echo ""
            echo "🚀 Opening in DB Browser for SQLite..."
            sqlitebrowser "$DB_FILE" &
        else
            echo ""
            echo "ℹ️  No display available. Open manually with:"
            echo "    sqlitebrowser $DB_FILE"
        fi
    else
        echo ""
        echo "⚠️  sqlitebrowser not installed. Install with:"
        echo "    sudo apt install sqlitebrowser"
    fi
else
    echo "❌ Failed to pull database. File type: $FILE_TYPE"
    echo "    Check that the app is installed and has been run at least once."
fi
