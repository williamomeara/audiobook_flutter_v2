# Flutter Download Best Practices & FormatException Analysis

## Overview
Research on best practices for downloading files in Flutter apps (iOS and Android), plus diagnosis of the `FormatException: Unexpected extension byte at offset 127` error when downloading Supertonic on iPhone.

---

## 1. Flutter Download Best Practices

### 1.1 Recommended Download Packages

| Package | Best For | Platform Support | Key Features |
|---------|----------|------------------|--------------|
| **background_downloader** ⭐ | Production apps | iOS, Android, macOS, Windows, Linux | Native URLSession (iOS) + WorkManager (Android), true background downloads, resume support, progress tracking |
| **flutter_downloader** | Simple use cases | iOS, Android | NSURLSessionDownloadTask + WorkManager, but has had SQL injection vulnerabilities |
| **dio** | Custom HTTP control | All platforms | Powerful interceptors, but no native background download |
| **http** | Basic requests | All platforms | Simple, no background support |

### 1.2 General Best Practices (Already Implemented ✅)

Your current implementation follows these patterns correctly:

1. **Atomic Downloads Pattern**
   - Download to temp file (`.tmp`) first
   - Verify integrity (checksum)
   - Atomic rename to final location
   - Write manifest marker file

2. **Resume Support**
   - Using HTTP Range headers for partial downloads
   - Handling server 206 (Partial Content) responses

3. **Progress Reporting**
   - Tracking bytes downloaded vs total expected
   - Showing distinct phases (downloading, extracting, verifying)

---

## 2. iOS-Specific Considerations

### 2.1 Background Downloads

```swift
// iOS uses NSURLSessionDownloadTask for background downloads
// background_downloader wraps this properly
```

**Key Constraints:**
- Background downloads limited to **4 hours maximum**
- Must enable "Background Fetch" capability in Xcode
- iOS aggressively kills memory-hungry background processes
- App may be terminated during download - must handle gracefully

### 2.2 Configuration Required

Add to `ios/Runner/Info.plist`:
```xml
<!-- For background downloads -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

Enable in Xcode:
1. Select Runner target
2. Signing & Capabilities tab
3. Click + to add capabilities
4. Select "Background Modes"
5. Enable "Background Fetch"

### 2.3 Storage Locations

- **Documents Directory**: Persistent, backed up to iCloud
- **Cache Directory**: Temporary, can be cleared by system
- **Application Support**: For data files not visible to user

```dart
import 'package:path_provider/path_provider.dart';

final cacheDir = await getApplicationCacheDirectory(); // Best for downloads
final docsDir = await getApplicationDocumentsDirectory(); // For permanent files
```

### 2.4 App Transport Security (ATS)

iOS requires HTTPS by default. For HTTP (not recommended):
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

---

## 3. Android-Specific Considerations

### 3.1 WorkManager Constraints

```dart
// WorkManager has default 9-minute timeout for background work
// Use allowPause: true for auto-resume on timeout
```

**Key Constraints:**
- Default timeout: 9 minutes
- Set `allowPause: true` to auto-resume when timeout occurs
- On Android 14+, can use User Initiated Data Transfer (UIDT) service

### 3.2 Permissions

In `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />

<!-- For external storage (deprecated in API 29+) -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
    android:maxSdkVersion="28" />
```

### 3.3 Storage Locations

- **App Cache Directory**: Best for downloads, no permissions needed
- **External Storage**: Complex permissions, deprecated
- **App-specific Directories**: Use `path_provider` for compatibility

---

## 4. FormatException Analysis

### 4.1 The Error

```
FormatException: Unexpected extension byte at offset 127
```

### 4.2 Root Cause

This is a **UTF-8 decoding error**:
- "Unexpected extension byte" = binary data being decoded as UTF-8 text
- Offset 127 = the byte position where decoding fails
- Binary archive data is being incorrectly interpreted as text

### 4.3 Where It Occurs

The error happens during **extraction**, not download. In `atomic_asset_manager.dart`:

```dart
// Line 651-653
decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
```

The `GZipDecoder` expects valid gzip bytes. If it receives something else (like HTML), it fails.

### 4.4 Most Likely Causes

1. **GitHub Returns HTML Error Page** 🎯 Most Likely
   - Rate limiting response
   - 404 Not Found page
   - Authentication/access error
   - The first 127 bytes look like text, then non-ASCII HTML content triggers the error

2. **Corrupted/Incomplete Download**
   - Network interruption
   - iOS killed the download mid-stream
   - Resume logic failed

3. **Wrong File Format**
   - Server returned unexpected content
   - Content-Type mismatch

### 4.5 How to Verify

Check if Hugging Face URL is accessible (current Supertonic source):
```
https://huggingface.co/Supertone/supertonic/resolve/main/onnx/duration_predictor.onnx
```

Test manually in browser or with curl:
```bash
curl -L -I "https://huggingface.co/Supertone/supertonic/resolve/main/onnx/duration_predictor.onnx"
```

---

## 5. Recommended Fixes

### 5.1 Add Archive Validation Before Extraction

In `atomic_asset_manager.dart`, add validation in `_extractArchiveIsolate`:

```dart
Future<void> _extractArchiveIsolate(_ExtractParams params) async {
  final archive = File(params.archivePath);
  final bytes = await archive.readAsBytes();
  
  final lower = archive.path.toLowerCase();
  final lowerNoTmp = lower.endsWith('.tmp') 
      ? lower.substring(0, lower.length - 4) 
      : lower;
  
  // Validate GZip format before decompressing
  if (lowerNoTmp.endsWith('.tar.gz') || lowerNoTmp.endsWith('.tgz')) {
    if (bytes.length < 2 || bytes[0] != 0x1F || bytes[1] != 0x8B) {
      // Check if it's an HTML error page
      final preview = String.fromCharCodes(bytes.take(200));
      if (preview.toLowerCase().contains('<!doctype') || 
          preview.toLowerCase().contains('<html')) {
        throw Exception(
          'Download failed: Server returned HTML error page instead of archive. '
          'Check if the release URL is accessible and the file exists.'
        );
      }
      throw Exception(
        'Invalid GZip format. Expected magic bytes [0x1F, 0x8B], '
        'got [${bytes[0].toRadixString(16)}, ${bytes[1].toRadixString(16)}]. '
        'File size: ${bytes.length} bytes.'
      );
    }
  }
  
  // ... rest of existing extraction code ...
}
```

### 5.2 Add Download Validation

In `_downloadWithResume`, add post-download validation:

```dart
// After download completes, before extraction
final downloadedSize = await destFile.length();

// Check if file is suspiciously small (likely HTML error page)
if (expectedSize != null && downloadedSize < (expectedSize * 0.5)) {
  final header = await destFile.openRead(0, 200).toList();
  final headerBytes = header.expand((x) => x).toList();
  final preview = String.fromCharCodes(headerBytes);
  
  if (preview.toLowerCase().contains('<!doctype') || 
      preview.toLowerCase().contains('not found') ||
      preview.toLowerCase().contains('rate limit')) {
    await destFile.delete();
    throw Exception(
      'Download returned error page (${downloadedSize} bytes instead of expected ${expectedSize}). '
      'Preview: ${preview.substring(0, 100)}...'
    );
  }
}
```

### 5.3 Consider background_downloader Package

For more robust iOS downloads, consider migrating to `background_downloader`:

```yaml
# pubspec.yaml
dependencies:
  background_downloader: ^8.5.5
```

```dart
import 'package:background_downloader/background_downloader.dart';

final task = DownloadTask(
  url: 'https://huggingface.co/Supertone/supertonic/resolve/main/onnx/duration_predictor.onnx',
  filename: 'duration_predictor.onnx',
  baseDirectory: BaseDirectory.applicationSupport,
  directory: 'downloads',
  updates: Updates.statusAndProgress,
  retries: 3,
  requiresWiFi: true,  // Optional: wait for WiFi for large files
);

final result = await FileDownloader().download(task,
  onProgress: (progress) => updateProgress(progress),
  onStatus: (status) => print('Status: $status'),
);

switch (result.status) {
  case TaskStatus.complete:
    // Now extract the archive
    break;
  case TaskStatus.failed:
    print('Download failed: ${result.exception}');
    break;
  default:
    break;
}
```

**Benefits:**
- Native URLSession on iOS (proper background handling)
- Native WorkManager on Android
- Built-in resume and retry
- Handles iOS app termination gracefully

---

## 6. Immediate Actions Checklist

- [x] Verify Hugging Face URL is accessible: `https://huggingface.co/Supertone/supertonic/resolve/main/onnx/duration_predictor.onnx`
- [x] Add GZip magic byte validation before extraction
- [x] Add HTML detection for better error messages
- [x] Add file size validation (compare to manifest)
- [ ] Consider adding detailed logging during iOS downloads
- [x] Switched to multi-file download from Hugging Face (no archive extraction needed for ONNX files)

---

## 7. Related Files

| File | Purpose |
|------|---------|
| `packages/downloads/lib/src/atomic_asset_manager.dart` | Main download logic |
| `lib/app/granular_download_manager.dart` | Download state management |
| `packages/downloads/lib/manifests/voices_manifest.json` | Download URLs and sizes |
| `docs/features/settings-downloads-overhaul/downloads-page-design.md` | UI design spec |

---

## References

- [background_downloader package](https://pub.dev/packages/background_downloader)
- [flutter_downloader package](https://pub.dev/packages/flutter_downloader)
- [dio package](https://pub.dev/packages/dio)
- [archive package](https://pub.dev/packages/archive)
- [Flutter networking cookbook](https://docs.flutter.dev/cookbook/networking/fetch-data)
