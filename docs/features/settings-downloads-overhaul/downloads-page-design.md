# Downloads Page Design Specification

## Overview

A robust, cross-platform voice downloads manager supporting three TTS engines (Piper, Supertonic, Kokoro) on both iOS and Android. This document outlines best practices and architecture for a reliable, user-friendly downloads experience.

---

## Platform Considerations

### iOS vs Android Differences

| Aspect | Android | iOS |
|--------|---------|-----|
| **Kokoro Model** | `kokoro-int8-multi-lang-v1_0.tar.bz2` (126MB quantized) | `kokoro-multi-lang-v1_0.tar.bz2` (335MB full precision) |
| **Supertonic Model** | ONNX Runtime (~234MB) | CoreML optimized (~61MB) |
| **Piper Models** | Same across platforms | Same across platforms |
| **Background Downloads** | More flexible | Requires background task registration |
| **Storage Access** | App cache directory | App containers only |

### Platform-Aware Download Selection

```
┌─────────────────────────────────────────┐
│           Manifest Lookup               │
│  "kokoro_core" → platform detection     │
│  iOS → kokoro_core_ios_v1               │
│  Android → kokoro_core_android_v1       │
└─────────────────────────────────────────┘
```

---

## Engine-Specific Download Architecture

### 1. Piper (Fastest, Self-Contained)
- **Model Structure**: Each voice IS the complete model
- **No Shared Core**: Each Piper voice download is standalone
- **Size**: ~63MB per voice
- **Download Flow**: Direct - download voice model, extract, ready

```
piper/
├── vits-piper-en_GB-alan-medium/
│   ├── model.onnx
│   ├── tokens.txt
│   ├── espeak-ng-data/
│   └── .manifest
└── vits-piper-en_US-lessac-medium/
    └── ...
```

### 2. Supertonic (Balanced)
- **Model Structure**: Shared core + speaker embeddings
- **Core Required**: Must download core before voices work
- **Core Size**: ~234MB (Android) / ~61MB (iOS)
- **Voices**: Built-in speaker IDs (no separate downloads)

```
supertonic/
├── supertonic_core_android_v1/  OR  supertonic_core_ios_v1/
│   ├── model.onnx  OR  model.mlmodelc/
│   ├── espeak-ng-data/
│   └── .manifest
```

### 3. Kokoro (Highest Quality)
- **Model Structure**: Large shared core with built-in speaker embeddings
- **Core Required**: Must download before any voices work
- **Core Size**: ~126MB (Android int8) / ~335MB (iOS full)
- **Voices**: Speaker IDs within single model
- **Warning**: Requires high-end device

```
kokoro/
├── kokoro_core_android_v1/  OR  kokoro_core_ios_v1/
│   ├── kokoro-v1_0.onnx
│   ├── voices/
│   └── .manifest
```

---

## UI/UX Best Practices

### 1. Clear Download States (ROBUST)

The download process has **distinct visual phases** so users always know what's happening:

| State | Visual | Status Text | Action |
|-------|--------|-------------|--------|
| **Not Downloaded** | ⬇️ Cloud icon (primary) | "63 MB" | Tap to start |
| **Queued** | ⏳ Clock icon (muted) | "Waiting..." | Tap to cancel |
| **Downloading** | Progress bar + % | "45% · 28 MB / 63 MB" | Tap to cancel |
| **Extracting** | Spinner (animated) | "Unpacking files..." | Non-interactive |
| **Verifying** | Spinner (animated) | "Verifying..." | Non-interactive |
| **Initializing** | Spinner (animated) | "Loading model..." | Non-interactive |
| **Ready** | ✅ Green checkmark | "Ready" | Tap to delete |
| **Failed** | ⚠️ Red warning | "Failed - Tap to retry" | Tap to retry |
| **Locked** | 🔒 Padlock (muted) | "Install core first" | Disabled |

### 2. Progress Indication (ROBUST)

**Phase-Aware Progress Display:**

```
┌─────────────────────────────────────────────────┐
│  Alan 🇬🇧 ♂️                                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 73%     │
│  Downloading · 46 MB / 63 MB                    │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Alan 🇬🇧 ♂️                                    │
│  [⟳ spinner]                                    │
│  Unpacking files...                             │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Alan 🇬🇧 ♂️                                    │
│  [⟳ spinner]                                    │
│  Loading model...                               │
└─────────────────────────────────────────────────┘
```

**Key Improvements:**
1. **Distinct visual for extraction** - Spinner instead of progress bar (since extraction progress can't be tracked)
2. **Clear status text** - Always shows what's happening: "Downloading", "Unpacking files...", "Loading model..."
3. **Size display during download** - Shows actual bytes downloaded/total
4. **Separate phases** - User knows if they're waiting for network vs CPU extraction

### 3. State Machine

```dart
enum DownloadPhase {
  idle,           // Not started
  queued,         // Waiting in queue
  downloading,    // Network transfer (show progress bar)
  extracting,     // Unpacking archive (show spinner)
  verifying,      // Checking checksums (show spinner)
  initializing,   // Loading into TTS engine (show spinner)
  ready,          // Complete
  failed,         // Error occurred
}
```

### 4. Phase Durations (User Expectations)

| Phase | Typical Duration | UI Guidance |
|-------|------------------|-------------|
| Downloading | 30s - 5min (network dependent) | Show progress bar, size, speed |
| Extracting | 10s - 90s (tar.bz2 decompression) | "This may take a minute..." |
| Verifying | 1-5s | Brief spinner |
| Initializing | 5-30s (model loading) | "Preparing voice engine..." |

### 5. Large Archive Warning

For archives >100MB, show estimated time:
```
┌─────────────────────────────────────────────────┐
│  Kokoro Engine                                  │
│  [⟳ spinner]                                    │
│  Unpacking files... (usually takes ~1 minute)   │
└─────────────────────────────────────────────────┘
```

### 3. Hierarchical Display

```
┌─────────────────────────────────────────────┐
│  🗂 Piper - Fast and lightweight            │
│     2/2 voices ready                        │
│  ┌─────────────────────────────────────┐    │
│  │ ▼ EXPANDED                          │    │
│  │  🎤 Alan (British)    [✓]  ▶️       │    │
│  │  🎤 Lessac (American) [✓]  ▶️       │    │
│  └─────────────────────────────────────┘    │
├─────────────────────────────────────────────┤
│  🗂 Supertonic - Advanced synthesis         │
│     0/10 voices ready                       │
│  ┌─────────────────────────────────────┐    │
│  │ ▼ EXPANDED                          │    │
│  │                                     │    │
│  │ ┌─ CORE COMPONENTS ───────────────┐ │    │
│  │ │ ☁️ Supertonic Core    [⬇ 234MB] │ │    │
│  │ └─────────────────────────────────┘ │    │
│  │                                     │    │
│  │ ┌─ VOICES (locked until core) ────┐ │    │
│  │ │ 🔒 Male 1                       │ │    │
│  │ │ 🔒 Female 1                     │ │    │
│  │ └─────────────────────────────────┘ │    │
│  └─────────────────────────────────────┘    │
├─────────────────────────────────────────────┤
│  🗂 Kokoro - Neural synthesis  ⚠️ High-end  │
│     0/11 voices ready                       │
└─────────────────────────────────────────────┘
```

### 4. Voice Preview

- **Play Button**: Each voice row has a preview play button
- **Audio Sample**: 3-5 second sample clip demonstrating voice
- **Streaming**: Samples hosted remotely, streamed on demand
- **Currently Playing**: Visual indicator for active preview

### 5. Batch Operations

- **"Download All"**: Per-engine batch download
- **Queue Management**: Downloads processed sequentially
- **Priority**: User-initiated downloads take priority
- **Cancellation**: Individual or batch cancel support

---

## Download Reliability Best Practices

### 1. Atomic Downloads

All downloads use atomic move pattern:
1. Download to `.downloading/` temp directory
2. Verify integrity (checksum if available)
3. Atomic move to final location
4. Write `.manifest` marker file

```dart
// AtomicAssetManager pattern
await downloadToTemp(url, tempPath);
await verifyChecksum(tempPath, expectedHash);
await atomicMove(tempPath, finalPath);
await writeManifest(finalPath);
```

### 2. Resume Support

- **Partial Downloads**: Track bytes downloaded for resume
- **Range Requests**: Use HTTP Range headers when supported
- **Retry Logic**: Exponential backoff on failure
- **Network Change**: Pause on disconnect, auto-resume on reconnect

### 3. Storage Management

Display and manage storage:
- **Total Used**: Sum of all installed models
- **Per-Engine**: Breakdown by engine type
- **Available Space**: Warn if low
- **Cleanup**: Option to delete unused models

### 4. Error Handling

| Error Type | User Message | Recovery Action |
|------------|--------------|-----------------|
| **Network Error** | "Connection lost. Will retry when online." | Auto-retry queue |
| **Storage Full** | "Not enough space. Free 234MB to continue." | Show storage manager |
| **Corrupted Download** | "Download failed. Tap to retry." | Re-download from start |
| **Server Error** | "Download temporarily unavailable." | Retry with backoff |

---

## State Management

### GranularDownloadState

```dart
class GranularDownloadState {
  final Map<String, CoreDownloadState> cores;
  final Map<String, VoiceDownloadState> voices;
  final int totalInstalledSize;
  
  // Computed helpers
  List<VoiceDownloadState> get readyVoices;
  List<VoiceDownloadState> getVoicesForEngine(String engineId);
  List<CoreDownloadState> getCoresForEngine(String engineId);
  bool isCoreReady(String coreId);
}

enum DownloadPhase {
  notDownloaded,
  queued,
  downloading,
  extracting,
  verifying,
  initializing,
  ready,
  failed,
}

class CoreDownloadState {
  final String coreId;
  final String displayName;
  final String engineType;
  final DownloadPhase phase;         // Changed from status
  final double progress;             // 0.0-1.0 for downloading phase
  final int sizeBytes;               // Total size
  final int downloadedBytes;         // Current downloaded bytes
  final String? statusText;          // Human-readable status
  final String? errorMessage;
  final DateTime? startTime;         // For ETA calculation
  
  bool get isReady => phase == DownloadPhase.ready;
  bool get isActive => phase == DownloadPhase.downloading || 
                       phase == DownloadPhase.extracting ||
                       phase == DownloadPhase.verifying ||
                       phase == DownloadPhase.initializing;
  
  /// Human-readable status text based on current phase
  String get displayStatus {
    return switch (phase) {
      DownloadPhase.notDownloaded => _formatBytes(sizeBytes),
      DownloadPhase.queued => 'Waiting...',
      DownloadPhase.downloading => '${(progress * 100).toStringAsFixed(0)}% · ${_formatBytes(downloadedBytes)} / ${_formatBytes(sizeBytes)}',
      DownloadPhase.extracting => 'Unpacking files...',
      DownloadPhase.verifying => 'Verifying...',
      DownloadPhase.initializing => 'Loading model...',
      DownloadPhase.ready => 'Ready',
      DownloadPhase.failed => errorMessage ?? 'Failed - Tap to retry',
    };
  }
}

class VoiceDownloadState {
  final String voiceId;
  final String displayName;
  final String engineId;
  final String language;
  final List<String> requiredCoreIds;
  
  bool allCoresReady(Map<String, CoreDownloadState> cores);
  bool anyDownloading(Map<String, CoreDownloadState> cores);
  double getDownloadProgress(Map<String, CoreDownloadState> cores);
}
```

### Provider Structure

```dart
// Main state provider
final granularDownloadManagerProvider = AsyncNotifierProvider<
    GranularDownloadManager, GranularDownloadState>();

// Individual download actions
class GranularDownloadManager extends AsyncNotifier<GranularDownloadState> {
  Future<void> downloadCore(String coreId);
  Future<void> downloadVoice(String voiceId);
  Future<void> downloadAllForEngine(String engineId);
  Future<void> cancelDownload(String itemId);
  Future<void> deleteCore(String coreId);
  void checkPendingControllerRefresh();
}
```

---

## Manifest-Driven Architecture

### voices_manifest.json Structure

```json
{
  "version": 2,
  "lastUpdated": "2026-01-25",
  "cores": [
    {
      "id": "kokoro_core_android_v1",
      "engineType": "kokoro",
      "displayName": "Kokoro TTS Core (Android int8)",
      "url": "https://...",
      "sizeBytes": 131839838,
      "required": true,
      "extractType": "tar.bz2",
      "platform": "android"
    },
    {
      "id": "kokoro_core_ios_v1",
      "engineType": "kokoro",
      "platform": "ios",
      ...
    }
  ],
  "voices": [
    {
      "id": "kokoro_af_alloy",
      "engineId": "kokoro",
      "displayName": "Kokoro - Alloy (US Female)",
      "language": "en-US",
      "gender": "female",
      "speakerId": 0,
      "coreRequirements": ["kokoro_core_v1"]  // Resolved at runtime
    }
  ]
}
```

### Platform Resolution

The manifest uses platform-agnostic `coreRequirements` that resolve at runtime:
- `kokoro_core_v1` → `kokoro_core_android_v1` OR `kokoro_core_ios_v1`
- `supertonic_core_v1` → `supertonic_core_android_v1` OR `supertonic_core_ios_v1`

---

## Network Considerations

### Background Downloads (iOS)

```dart
// Use URLSession background task on iOS
final task = await NSURLSession.backgroundSession.downloadTask(url);
await task.resume();
// Handle via AppDelegate callbacks
```

### WiFi-Only Option

User preference for large downloads:
- **WiFi Only**: Downloads >100MB wait for WiFi
- **Any Network**: Download immediately
- **User Override**: "Download anyway" button

### Bandwidth Management

- **Concurrent Limit**: Max 1 download at a time (configurable)
- **Rate Limiting**: Respect server limits
- **Pause on Call**: Option to pause during phone calls

---

## Testing Checklist

### Functional Tests
- [ ] Download each engine type on Android
- [ ] Download each engine type on iOS
- [ ] Verify platform-specific core selection
- [ ] Cancel mid-download and verify cleanup
- [ ] Resume interrupted download
- [ ] Download with poor network (simulate)

### Edge Cases
- [ ] Storage full during download
- [ ] App killed during extraction
- [ ] Network change during download
- [ ] Corrupted download detection
- [ ] Manifest version mismatch

### UI Tests
- [ ] Progress updates smoothly
- [ ] Voice preview plays correctly
- [ ] Batch download shows queue
- [ ] Delete confirmation works
- [ ] Error states display properly

---

## Implementation Priority

### Phase 1: Core Improvements
1. Add download queue status visibility
2. Add cancel/pause functionality
3. Improve error messaging
4. Add retry functionality

### Phase 2: UX Enhancements
1. Voice preview improvements (loading state, error handling)
2. Storage management (per-engine breakdown, delete options)
3. Download speed/ETA display
4. Network preference settings

### Phase 3: Advanced Features
1. Background download support (iOS)
2. WiFi-only option
3. Auto-update for new model versions
4. Checksum verification display

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/ui/screens/download_manager_screen.dart` | Main UI overhaul |
| `lib/app/granular_download_manager.dart` | Add cancel/pause, queue status |
| `packages/downloads/lib/src/download_queue.dart` | Queue visibility API |
| `packages/downloads/lib/manifests/voices_manifest.json` | Keep in sync |
| `lib/ui/screens/settings_screen.dart` | Add storage management entry |

---

## Related Documentation

- [Settings Screen Overhaul](./settings-page-design.md)
- [TTS Engine Architecture](../../tts/README.md)
- [Downloads Package](../../../packages/downloads/README.md)
