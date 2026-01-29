#!/bin/bash
# Touch Control Script for ADB
# 
# NOTE: Without root, there's no way to fully disable physical touch.
# This script uses TalkBack as a workaround - it requires double-tap for actions.
# scrcpy injected touches work normally regardless.
#
# For full touch blocking without root, install a touch blocker app.

DEVICE="${ADB_DEVICE:--s 39081FDJH00FEB}"

case "$1" in
  disable-touch|disable|off)
    echo "🔒 Disabling physical touch (TalkBack method)..."
    adb $DEVICE shell settings put secure enabled_accessibility_services "com.android.talkback/com.google.android.marvin.talkback.TalkBackService"
    adb $DEVICE shell settings put secure accessibility_enabled 1
    echo ""
    echo "✅ TalkBack enabled"
    echo "   - Physical touch now requires DOUBLE-TAP to work"
    echo "   - scrcpy touches bypass this and work normally"
    echo ""
    echo "To fully block touch without root, install a touch blocker app."
    ;;
    
  enable-touch|enable|on)
    echo "🔓 Restoring physical touch..."
    adb $DEVICE shell settings put secure enabled_accessibility_services null
    adb $DEVICE shell settings put secure accessibility_enabled 0
    echo "✅ Physical touch restored"
    ;;
    
  status)
    echo "📊 Touch Control Status:"
    echo ""
    ENABLED=$(adb $DEVICE shell settings get secure accessibility_enabled 2>/dev/null)
    SERVICES=$(adb $DEVICE shell settings get secure enabled_accessibility_services 2>/dev/null)
    
    if [ "$ENABLED" = "1" ] && [[ "$SERVICES" == *"TalkBack"* ]]; then
      echo "🔒 Physical touch: BLOCKED (TalkBack mode)"
    else
      echo "🔓 Physical touch: ENABLED"
    fi
    echo ""
    echo "Raw values:"
    echo "  accessibility_enabled: $ENABLED"
    echo "  enabled_services: $SERVICES"
    ;;
    
  *)
    echo "Usage: $0 {disable-touch|enable-touch|status}"
    echo ""
    echo "Commands:"
    echo "  disable-touch, disable, off  - Block physical touch (TalkBack)"
    echo "  enable-touch, enable, on     - Restore physical touch"
    echo "  status                       - Show current status"
    echo ""
    echo "Environment:"
    echo "  ADB_DEVICE  - Override device selection (default: $DEVICE)"
    exit 1
    ;;
esac
