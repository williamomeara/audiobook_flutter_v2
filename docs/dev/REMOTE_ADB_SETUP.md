# Remote ADB Setup: Linux Server → Mac → Android Phone

This guide explains how to build the Flutter Android app on a remote Linux server (via SSH) and deploy it to an Android phone connected to your Mac via USB.

## Overview

```
┌─────────────────┐      SSH        ┌─────────────────┐      USB       ┌─────────────────┐
│  Linux Server   │ ──────────────▶ │    Mac Host     │ ─────────────▶ │  Android Phone  │
│  (Build here)   │                 │ (ADB Forwarding)│                │   (Run app)     │
└─────────────────┘                 └─────────────────┘                └─────────────────┘
```

## Prerequisites

### On Linux Server
- Flutter SDK installed
- Android SDK installed (for `adb`)
- SSH access configured

### On Mac
- Android SDK Platform Tools installed (`adb`)
- USB debugging enabled on the phone

### On Android Phone
- Developer Options enabled
- USB Debugging enabled
- Computer authorized for debugging

---

## Method 1: ADB over TCP/IP (Recommended)

This method connects the Linux server directly to the phone over the network.

### Step 1: Connect Phone to Mac via USB

```bash
# On Mac - verify device is connected
adb devices
```

### Step 2: Enable TCP/IP Mode on Phone

```bash
# On Mac - switch device to TCP/IP mode
adb tcpip 5555
```

### Step 3: Get Phone's IP Address

Either:
- Go to **Settings → About phone → Status → IP address** on the phone
- Or run on Mac: `adb shell ip addr show wlan0 | grep "inet "`

### Step 4: Connect from Linux Server

```bash
# On Linux Server - connect to phone via network
adb connect <PHONE_IP>:5555

# Verify connection
adb devices
# Should show: <PHONE_IP>:5555    device
```

### Step 5: Build and Deploy

```bash
# On Linux Server
cd /home/william/Projects/audiobook_flutter_v2
flutter run
```

### Disconnecting

```bash
# On Linux Server
adb disconnect <PHONE_IP>:5555

# On Mac - restore USB mode (optional)
adb usb
```

---

## Method 2: SSH Reverse Port Forwarding

This method tunnels ADB traffic through SSH when the phone isn't on the same network.

### Step 1: Enable TCP/IP on Phone (from Mac)

```bash
# On Mac
adb tcpip 5555
```

### Step 2: Set Up SSH Tunnel from Linux Server

```bash
# On Linux Server - create tunnel to Mac
ssh -R 5555:localhost:5555 <mac_user>@<mac_ip>
```

Or, if you want the tunnel in the background:

```bash
ssh -fN -R 5555:localhost:5555 <mac_user>@<mac_ip>
```

### Step 3: Forward from Mac to Phone

On the Mac (in the SSH session or separately):

```bash
# On Mac - forward to phone's IP
socat TCP-LISTEN:5555,reuseaddr,fork TCP:<PHONE_IP>:5555
```

Or use ADB's built-in forwarding:

```bash
# On Mac
adb forward tcp:5555 tcp:5555
```

### Step 4: Connect from Linux Server

```bash
# On Linux Server
adb connect localhost:5555
```

---

## Method 3: ADB Server Forwarding via SSH

Forward the entire ADB server connection through SSH.

### Step 1: Start ADB Server on Mac

```bash
# On Mac
adb start-server
adb devices  # Ensure phone is listed
```

### Step 2: Forward ADB Port via SSH

```bash
# On Linux Server - forward ADB server port
ssh -L 5037:localhost:5037 <mac_user>@<mac_ip>
```

### Step 3: Use ADB on Linux

```bash
# On Linux Server (in a new terminal, same SSH session)
# Kill any local adb server first
adb kill-server

# Now adb commands will use the forwarded connection
adb devices
```

**Note:** This method forwards the Mac's ADB server, so you're essentially using Mac's ADB remotely.

---

## Quick Start Script

Create this script on the Linux server for convenience:

### `scripts/remote_adb_connect.sh`

```bash
#!/bin/bash
# Remote ADB Connection Script
# Usage: ./remote_adb_connect.sh <phone_ip>

PHONE_IP=${1:-"192.168.1.100"}  # Default IP, change as needed
PORT=5555

echo "Connecting to Android device at $PHONE_IP:$PORT..."
adb connect "$PHONE_IP:$PORT"

if adb devices | grep -q "$PHONE_IP:$PORT"; then
    echo "✅ Connected successfully!"
    echo ""
    echo "Run your Flutter app with:"
    echo "  flutter run"
    echo ""
    echo "To disconnect:"
    echo "  adb disconnect $PHONE_IP:$PORT"
else
    echo "❌ Connection failed. Troubleshooting:"
    echo "  1. Ensure phone is on same network as this server"
    echo "  2. On Mac, run: adb tcpip 5555"
    echo "  3. Check phone's IP address"
    echo "  4. Verify no firewall blocking port $PORT"
fi
```

Make it executable:

```bash
chmod +x scripts/remote_adb_connect.sh
```

---

## Troubleshooting

### Device shows "unauthorized"
- Check phone for authorization prompt
- Revoke USB debugging authorizations on phone and re-authorize

### Connection refused
- Verify phone is in TCP/IP mode: `adb tcpip 5555` (on Mac)
- Check firewall settings on phone/router
- Ensure devices are on same network (for Method 1)

### Device goes offline after a while
- Re-run `adb connect <PHONE_IP>:5555`
- Check if phone went to sleep (disable sleep during development)
- Keep phone plugged in to prevent battery optimization disconnects

### Multiple devices
- Use `-s` flag to specify device: `flutter run -d <PHONE_IP>:5555`

### ADB version mismatch
- Ensure ADB versions match on both Mac and Linux server
- Update both to latest: `brew install android-platform-tools` (Mac)

---

## Development Workflow

### Daily Workflow

1. **Morning Setup (once per session)**
   ```bash
   # On Mac - ensure phone is in TCP mode
   adb tcpip 5555
   ```

2. **On Linux Server**
   ```bash
   # Connect to phone
   adb connect <PHONE_IP>:5555
   
   # Navigate to project
   cd /home/william/Projects/audiobook_flutter_v2
   
   # Build and run
   flutter run
   ```

3. **Hot Reload/Restart**
   - Press `r` for hot reload
   - Press `R` for hot restart
   - Press `q` to quit

### Building Release APK

```bash
# On Linux Server
flutter build apk --release

# Copy to Mac for distribution (if needed)
scp build/app/outputs/flutter-apk/app-release.apk <mac_user>@<mac_ip>:~/Downloads/
```

---

## Environment Variables

Add to your `.bashrc` or `.zshrc` on the Linux server:

```bash
# Android development
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Default phone IP (update with your phone's IP)
export PHONE_ADB_IP="192.168.1.100"

# Alias for quick connect
alias adb-connect='adb connect $PHONE_ADB_IP:5555'
alias adb-disconnect='adb disconnect $PHONE_ADB_IP:5555'
```

---

## Security Considerations

- TCP/IP debugging exposes your phone to the network
- Only use on trusted networks
- Disable TCP/IP mode when not debugging: `adb usb` (from Mac)
- Consider using SSH tunneling (Method 2/3) for added security
- Don't leave debugging enabled on production devices
