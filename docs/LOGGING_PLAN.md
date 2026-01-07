# Comprehensive Logging Plan

## Overview
This document defines the logging strategy for the Audiobook Flutter app, with extensive logging in development mode and minimal logging in production.

## Logging Framework

### Current State
- Using `print()` statements for debugging
- `Logger` from `package:logging` in playback controller
- No centralized logging configuration

### Proposed Implementation
Use `package:logging` throughout with different levels:
- **FINE**: Detailed trace information
- **INFO**: General informational messages  
- **WARNING**: Warning messages for unexpected but handled situations
- **SEVERE**: Error messages for failures

## Development Mode Configuration

### Setup in main.dart
```dart
import 'package:logging/logging.dart';

void main() {
  // Configure logging based on build mode
  if (kDebugMode) {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      print('[${record.loggerName}] ${record.level.name}: ${record.message}');
      if (record.error != null) {
        print('[${record.loggerName}] Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        print('[${record.loggerName}] Stack: ${record.stackTrace}');
      }
    });
  } else {
    // Production: Only warnings and errors
    Logger.root.level = Level.WARNING;
    Logger.root.onRecord.listen((record) {
      // Log to crash reporting service (e.g., Sentry, Firebase Crashlytics)
      debugPrint('[${record.loggerName}] ${record.level.name}: ${record.message}');
    });
  }

  runApp(const ProviderScope(child: MyApp()));
}
```

## Logging by Component

### 1. **Book Import & Library** (`lib/app/library_controller.dart`)

**Logger:** `LibraryController`

**Events to Log:**
- **INFO**: Book import started/completed
- **INFO**: Book added to library
- **INFO**: Book removed from library
- **INFO**: Progress updated
- **WARNING**: Book already exists (skip)
- **SEVERE**: Import failed (with exception)
- **FINE**: EPUB parsing details
- **FINE**: File operations (copy, save)

**Example:**
```dart
final _logger = Logger('LibraryController');

Future<String> importBookFromPath(...) async {
  _logger.info('Importing book: $fileName');
  _logger.fine('Source: $sourcePath');
  
  try {
    // ... import logic
    _logger.info('Book imported successfully: $bookId');
    return bookId;
  } catch (e, st) {
    _logger.severe('Failed to import book', e, st);
    rethrow;
  }
}
```

### 2. **Playback** (`lib/app/playback_providers.dart`, `packages/playback/`)

**Logger:** `PlaybackProvider`, `AudiobookPlaybackController`

**Events to Log:**
- **INFO**: Playback controller initialized
- **INFO**: Chapter loaded (with segment count)
- **INFO**: Playback started/paused
- **INFO**: Track changed
- **INFO**: Playback rate changed
- **WARNING**: Controller not initialized
- **WARNING**: Invalid chapter index
- **SEVERE**: Initialization failed
- **SEVERE**: Chapter load failed
- **FINE**: Segmentation timing
- **FINE**: Audio track creation
- **FINE**: Queue state changes

**Example:**
```dart
final _logger = Logger('PlaybackProvider');

Future<void> loadChapter(...) async {
  _logger.info('Loading chapter $chapterIndex for "${book.title}"');
  _logger.fine('Chapter content: ${chapter.content.length} chars');
  
  final start = DateTime.now();
  final segments = segmentText(chapter.content);
  final duration = DateTime.now().difference(start);
  
  _logger.fine('Segmented into ${segments.length} segments in ${duration.inMilliseconds}ms');
  // ...
}
```

### 3. **TTS & Synthesis** (`lib/app/tts_providers.dart`, `packages/tts_engines/`)

**Logger:** `TtsProvider`, `RoutingEngine`, `KokoroAdapter`, etc.

**Events to Log:**
- **INFO**: Engine initialized
- **INFO**: Synthesis started/completed (with timing)
- **INFO**: Voice model loaded
- **INFO**: Cache hit/miss
- **WARNING**: Voice not ready
- **WARNING**: Model not downloaded
- **SEVERE**: Synthesis failed
- **SEVERE**: Engine initialization failed
- **FINE**: Model file paths
- **FINE**: Synthesis parameters (text length, voice, rate)
- **FINE**: Audio output details (duration, file size)

**Example:**
```dart
final _logger = Logger('KokoroAdapter');

Future<SynthesisResult> synthesize(...) async {
  _logger.info('Synthesizing with Kokoro voice: $voiceId');
  _logger.fine('Text length: ${request.text.length} chars');
  _logger.fine('Playback rate: ${request.playbackRate}x');
  
  final start = DateTime.now();
  try {
    final result = await _synthesize(request);
    final duration = DateTime.now().difference(start);
    
    _logger.info('Synthesis complete in ${duration.inMilliseconds}ms');
    _logger.fine('Output: ${result.durationMs}ms audio, ${result.fileSize} bytes');
    
    return result;
  } catch (e, st) {
    _logger.severe('Kokoro synthesis failed', e, st);
    rethrow;
  }
}
```

### 4. **Downloads** (`lib/app/granular_download_manager.dart`, `packages/downloads/`)

**Logger:** `DownloadManager`, `AtomicAssetManager`, `ResilientDownloader`

**Events to Log:**
- **INFO**: Download started/completed
- **INFO**: Download progress (every 10%)
- **INFO**: Download verified (checksum)
- **INFO**: Asset installed
- **WARNING**: Download retry attempt
- **WARNING**: Checksum mismatch
- **SEVERE**: Download failed (max retries exceeded)
- **SEVERE**: Asset installation failed
- **FINE**: Download URL
- **FINE**: File sizes
- **FINE**: Temp file paths

**Example:**
```dart
final _logger = Logger('DownloadManager');

Future<void> downloadVoice(VoiceInfo voice) async {
  _logger.info('Starting download: ${voice.name}');
  _logger.fine('URL: ${voice.downloadUrl}');
  _logger.fine('Expected size: ${voice.downloadSize} bytes');
  
  try {
    await _downloader.download(
      url: voice.downloadUrl,
      onProgress: (progress) {
        if (progress % 10 == 0) {
          _logger.fine('Download progress: $progress%');
        }
      },
    );
    _logger.info('Download complete: ${voice.name}');
  } catch (e, st) {
    _logger.severe('Download failed: ${voice.name}', e, st);
    rethrow;
  }
}
```

### 5. **UI Screens** (`lib/ui/screens/`)

**Logger:** Per-screen loggers (e.g., `PlaybackScreen`, `LibraryScreen`)

**Events to Log:**
- **INFO**: Screen opened
- **INFO**: User action (button press, navigation)
- **WARNING**: Invalid state
- **SEVERE**: Render error
- **FINE**: State updates
- **FINE**: Navigation events

**Example:**
```dart
final _logger = Logger('PlaybackScreen');

@override
void initState() {
  super.initState();
  _logger.info('PlaybackScreen opened for book: ${widget.bookId}');
  
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _logger.fine('Initializing playback...');
    _initializePlayback();
  });
}
```

### 6. **Settings & Persistence** (`lib/app/settings_controller.dart`)

**Logger:** `SettingsController`

**Events to Log:**
- **INFO**: Settings loaded
- **INFO**: Setting changed (name, old value, new value)
- **INFO**: Settings saved
- **WARNING**: Settings migration
- **SEVERE**: Settings load/save failed
- **FINE**: Settings file path

### 7. **EPUB Parsing** (`lib/infra/epub_parser.dart`)

**Logger:** `EpubParser`

**Events to Log:**
- **INFO**: Parsing started/completed
- **INFO**: Chapters extracted (count)
- **INFO**: Cover image extracted
- **WARNING**: Fallback to zip parse
- **WARNING**: Cover image not found
- **SEVERE**: Parse failed
- **FINE**: Chapter details (title, content length)
- **FINE**: Metadata extraction

## Log Message Guidelines

### Formatting
- **Start with verb**: "Loading...", "Initialized", "Failed to..."
- **Include context**: IDs, names, counts, sizes
- **Use quotes**: For user-visible strings like titles
- **Include units**: "500ms", "2.5MB", "15 segments"

### Examples
✅ **Good:**
```dart
_logger.info('Loading chapter 3 for "1984"');
_logger.info('Segmented into 47 segments in 12ms');
_logger.severe('Failed to download kokoro_af_bella: Network timeout');
```

❌ **Bad:**
```dart
_logger.info('loading');
_logger.info('done');
_logger.severe('error');
```

### Performance Considerations
- Use `FINE` for high-frequency events (progress updates, state changes)
- Limit string interpolation in production (use lazy evaluation)
- Don't log sensitive data (paths may contain usernames)

## Testing Logging

### Dev Mode Verification
1. Run app with `flutter run --debug`
2. Open each major screen
3. Trigger each major action
4. Verify logs appear with correct levels
5. Verify error paths log stack traces

### Production Verification
1. Build release: `flutter build apk --release`
2. Verify only WARNING/SEVERE logs appear
3. Verify no performance impact

## Integration with Crash Reporting

### Future Enhancement
When crash reporting is added (e.g., Sentry):
```dart
// In production logger setup
Logger.root.onRecord.listen((record) {
  if (record.level >= Level.WARNING) {
    Sentry.captureMessage(
      '${record.loggerName}: ${record.message}',
      level: record.level == Level.WARNING 
        ? SentryLevel.warning 
        : SentryLevel.error,
    );
    
    if (record.error != null) {
      Sentry.captureException(
        record.error,
        stackTrace: record.stackTrace,
      );
    }
  }
});
```

## Migration Plan

### Phase 1: Core Systems (Current)
- ✅ PlaybackProvider
- ✅ PlaybackController
- ✅ PlaybackScreen
- ⬜ LibraryController
- ⬜ TTS Providers

### Phase 2: Supporting Systems
- ⬜ DownloadManager
- ⬜ EpubParser
- ⬜ SettingsController
- ⬜ All UI Screens

### Phase 3: Engines & Adapters
- ⬜ RoutingEngine
- ⬜ KokoroAdapter
- ⬜ PiperAdapter
- ⬜ SupertonicAdapter

### Phase 4: Utilities
- ⬜ ResilientDownloader
- ⬜ TextSegmenter
- ⬜ Cache implementations

## Implementation Checklist

For each component:
- [ ] Add `Logger` instance
- [ ] Replace `print()` with appropriate log level
- [ ] Add INFO logs for major operations
- [ ] Add FINE logs for detailed flow
- [ ] Add WARNING logs for handled errors
- [ ] Add SEVERE logs with stack traces for failures
- [ ] Test in debug mode
- [ ] Test in release mode

## Example Complete Migration

**Before:**
```dart
Future<void> doSomething() async {
  print('Starting...');
  try {
    final result = await operation();
    print('Done: $result');
  } catch (e) {
    print('Error: $e');
    rethrow;
  }
}
```

**After:**
```dart
final _logger = Logger('MyClass');

Future<void> doSomething() async {
  _logger.info('Starting operation');
  _logger.fine('Current state: $_state');
  
  try {
    final start = DateTime.now();
    final result = await operation();
    final duration = DateTime.now().difference(start);
    
    _logger.info('Operation complete in ${duration.inMilliseconds}ms');
    _logger.fine('Result: $result');
  } catch (e, st) {
    _logger.severe('Operation failed', e, st);
    rethrow;
  }
}
```
