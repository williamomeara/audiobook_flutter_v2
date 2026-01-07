# Development Environment Setup

## Prerequisites

Before you begin, ensure you have the following installed:

### Required
- **Flutter SDK**: Version 3.10+
  - [Download Flutter](https://flutter.dev/docs/get-started/install)
- **Dart SDK**: Included with Flutter
- **Git**: For version control
- **Android SDK**: API Level 24+ (for Android development)
- **JDK**: Java Development Kit 11+

### For Android Development
- **Android Studio** or Android SDK Command-line Tools
- **Android NDK**: For native code compilation
- **Gradle**: Included with Android SDK

### For iOS Development (macOS only)
- **Xcode**: Latest version
- **CocoaPods**: For dependency management
- **iOS Deployment Target**: 12.0+

## Installation Steps

### 1. Flutter SDK

#### macOS / Linux
```bash
# Download Flutter
git clone https://github.com/flutter/flutter.git ~/flutter
cd ~/flutter
git checkout [stable-version]

# Add to PATH
export PATH="$PATH:~/flutter/bin"

# Verify installation
flutter --version
```

#### Windows
```bash
# Download Flutter from GitHub releases
# Extract to C:\flutter

# Add to PATH environment variable
# Verify installation
flutter --version
```

### 2. Android Setup

#### macOS / Linux
```bash
# Download Android Command-line Tools
# Extract and set ANDROID_HOME
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools"

# Install necessary SDK components
sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0" "ndk;25.1.8937393"

# Accept licenses
sdkmanager --licenses
```

#### Windows
```cmd
# Set ANDROID_HOME environment variable
setx ANDROID_HOME C:\Users\YourUsername\AppData\Local\Android\sdk

# Add to PATH
setx PATH "%PATH%;%ANDROID_HOME%\tools;%ANDROID_HOME%\platform-tools"

# Accept licenses
sdkmanager --licenses
```

### 3. iOS Setup (macOS only)

```bash
# Install CocoaPods
sudo gem install cocoapods

# Update pods
pod repo update

# Install Xcode command-line tools
xcode-select --install
```

## Project Setup

### Clone the Repository

```bash
# Clone the project
git clone https://github.com/yourusername/audiobook_flutter_v2.git
cd audiobook_flutter_v2

# Switch to development branch
git checkout develop
```

### Get Dependencies

```bash
# Get Flutter dependencies
flutter pub get

# Generate code (for Riverpod, etc.)
flutter pub run build_runner build --delete-conflicting-outputs

# Or use watch mode for development
flutter pub run build_runner watch
```

### Build Local Packages

```bash
# The project uses local packages
# They're automatically built with pub get, but you can verify:
cd packages/core_domain
flutter pub get

cd ../downloads
flutter pub get

cd ../playback
flutter pub get

cd ../tts_engines
flutter pub get

cd ../platform_android_tts
flutter pub get
```

## Verify Installation

```bash
# Check if everything is set up correctly
flutter doctor

# Should output something like:
# ✓ Flutter (X.X.X)
# ✓ Android SDK (XX.X)
# ✓ Xcode (XX.X) - macOS only
# ✓ Android SDK Tools
```

## IDE Setup

### Android Studio / IntelliJ

1. Install Flutter plugin: Plugins → Search "Flutter" → Install
2. Install Dart plugin: Plugins → Search "Dart" → Install
3. Configure Flutter SDK:
   - File → Settings → Languages & Frameworks → Flutter
   - Set Flutter SDK Path to your Flutter installation
4. Restart IDE

### Visual Studio Code

1. Install Flutter extension by Dart Code
2. Install Dart extension by Dart Code
3. Configure Flutter SDK:
   - Cmd/Ctrl + Shift + P → "Flutter: Change Device SDK Path"
   - Select your Flutter SDK path

## Running the App

### Android

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d device_id

# Run with specific build variant
flutter run --flavor dev

# Hot reload during development
# Press 'r' in console
```

### iOS (macOS only)

```bash
# Install pod dependencies first
cd ios
pod install
cd ..

# Run on device
flutter run -d device_id

# Run on simulator
flutter run
```

## Development Tips

### Code Generation

This project uses code generation for Riverpod and other packages:

```bash
# Watch mode - auto-regenerate on file changes
flutter pub run build_runner watch

# One-time build
flutter pub run build_runner build

# Clean generated files
flutter pub run build_runner clean
```

### Debugging

```bash
# Run with debugging
flutter run

# Enable verbose output
flutter run -v

# Connect debugger in IDE
# Set breakpoints and use IDE's debugger
```

### Hot Reload

During development, use hot reload for fast iteration:
- Press 'r' in console
- Or use IDE's hot reload button
- Keeps app state while reloading code

### Emulator Troubleshooting

If you encounter slow emulator performance:

```bash
# Use host GPU acceleration
emulator -avd your_avd_name -gpu on

# Or check available GPU options
emulator -avd your_avd_name -gpu auto
```

## Next Steps

1. Read the [Architecture Guide](../ARCHITECTURE.md)
2. Follow [Running Locally](./running-locally.md)
3. Check out [Troubleshooting](./troubleshooting.md) if issues arise
4. Review [How to Add Features](../guides/adding-new-features.md)

## Common Issues

### "Flutter not found"
- Ensure Flutter is in your PATH
- Restart your terminal/IDE
- Run `flutter --version` to verify

### "Android SDK not found"
- Set `ANDROID_HOME` environment variable
- Run `flutter doctor` to see what's missing
- Install required SDK components with sdkmanager

### "Pod install" fails on macOS
- Update CocoaPods: `sudo gem install cocoapods`
- Clear pods: `rm -rf ios/Pods ios/Podfile.lock`
- Try again: `cd ios && pod install && cd ..`

For more issues, see [Troubleshooting Guide](./troubleshooting.md).

## Additional Resources

- [Flutter Official Documentation](https://flutter.dev/docs)
- [Dart Language Guide](https://dart.dev/guides)
- [Riverpod Documentation](https://riverpod.dev)
- [Android Development](https://developer.android.com)

---

**Last Updated**: January 7, 2026
