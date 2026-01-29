# System Media Controls Implementation Plan

## Overview

This document outlines the implementation plan for integrating system media controls (lock screen player and notification shade controls) into the Flutter audiobook app. The implementation uses Flutter's recommended packages for background audio playback and system integration.

## Current State

- ✅ `just_audio: ^0.10.5` - Core audio playback
- ✅ `audio_service: ^0.18.18` - Background audio and media controls framework
- ❌ Media session integration not fully implemented
- ❌ Lock screen artwork display
- ❌ Notification shade controls

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter App                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  PlaybackController                        │  │
│  │  (packages/playback/lib/src/playback_controller.dart)     │  │
│  └─────────────────────────┬─────────────────────────────────┘  │
│                            │                                     │
│  ┌─────────────────────────▼─────────────────────────────────┐  │
│  │              AudioServiceHandler                           │  │
│  │        (Implements BaseAudioHandler)                       │  │
│  │  - Manages media session                                   │  │
│  │  - Handles system media button events                      │  │
│  │  - Updates notification metadata                           │  │
│  └─────────────────────────┬─────────────────────────────────┘  │
└────────────────────────────┼─────────────────────────────────────┘
                             │
                             ▼
        ┌────────────────────────────────────────┐
        │         Platform Media Controls         │
        │                                        │
        │  ┌──────────────┐  ┌────────────────┐ │
        │  │  Lock Screen │  │ Notification   │ │
        │  │    Player    │  │    Shade       │ │
        │  └──────────────┘  └────────────────┘ │
        │                                        │
        │  ┌──────────────┐  ┌────────────────┐ │
        │  │  Bluetooth   │  │  Android Auto  │ │
        │  │  Controls    │  │ / CarPlay      │ │
        │  └──────────────┘  └────────────────┘ │
        └────────────────────────────────────────┘
```

## Phase 1: Audio Handler Setup (1-2 days)

### 1.1 Create AudioServiceHandler

Create a new file: `lib/app/audio_service_handler.dart`

```dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  
  AudioServiceHandler(this._player) {
    // Forward player state changes to media session
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    // Forward current item to media session
    _player.currentIndexStream.listen((index) {
      if (index != null) {
        _updateMediaItem();
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Implement chapter/segment skip
  }

  @override
  Future<void> skipToPrevious() async {
    // Implement chapter/segment skip back
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  void _updateMediaItem() {
    // Update with current book/chapter info
  }
}
```

### 1.2 Initialize Audio Service

Update `main.dart` to initialize the audio service:

```dart
late AudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  audioHandler = await AudioService.init(
    builder: () => AudioServiceHandler(AudioPlayer()),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.audiobook.channel.audio',
      androidNotificationChannelName: 'Audio Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  
  runApp(const MyApp());
}
```

### 1.3 Tasks

- [ ] Create `AudioServiceHandler` class extending `BaseAudioHandler`
- [ ] Implement all required playback controls
- [ ] Wire up player state to `playbackState` stream
- [ ] Initialize audio service in `main.dart`
- [ ] Test basic play/pause from notification

---

## Phase 2: Media Metadata (1-2 days)

### 2.1 MediaItem Updates

When starting playback, update the media item with book information:

```dart
void updateNowPlaying({
  required String bookId,
  required String bookTitle,
  required String author,
  required String chapterTitle,
  required int chapterIndex,
  required int totalChapters,
  String? artworkPath,
  Duration? duration,
}) {
  mediaItem.add(MediaItem(
    id: bookId,
    title: chapterTitle,
    album: bookTitle,
    artist: author,
    artUri: artworkPath != null ? Uri.file(artworkPath) : null,
    duration: duration,
    extras: {
      'chapterIndex': chapterIndex,
      'totalChapters': totalChapters,
    },
  ));
}
```

### 2.2 Artwork Handling

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<Uri?> getArtworkUri(String? coverPath) async {
  if (coverPath == null) return null;
  
  final file = File(coverPath);
  if (await file.exists()) {
    return file.uri;
  }
  
  // Fallback to a bundled asset
  return null;
}
```

### 2.3 Tasks

- [ ] Implement `updateNowPlaying()` method
- [ ] Handle artwork URI conversion
- [ ] Add fallback for missing artwork
- [ ] Test lock screen displays correct metadata

---

## Phase 3: Playback Controls Integration (2-3 days)

### 3.1 Connect to PlaybackController

Integrate the audio handler with the existing `PlaybackController`:

```dart
// In playback_providers.dart
final audioHandlerProvider = Provider<AudioHandler>((ref) {
  return audioHandler; // Global instance from main.dart
});

// In PlaybackController
class PlaybackController extends AsyncNotifier<PlaybackState> {
  late AudioHandler _audioHandler;
  
  @override
  Future<PlaybackState> build() async {
    _audioHandler = ref.watch(audioHandlerProvider);
    // ... existing initialization
  }
  
  Future<void> play() async {
    await _audioHandler.play();
    // Update internal state
  }
  
  Future<void> pause() async {
    await _audioHandler.pause();
    // Update internal state
  }
}
```

### 3.2 Handle Media Button Events

```dart
class AudioServiceHandler extends BaseAudioHandler {
  final void Function()? onSkipToNext;
  final void Function()? onSkipToPrevious;
  
  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }
  
  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }
}
```

### 3.3 Speed Control Button (Android)

Add a custom action for playback speed:

```dart
PlaybackState _transformEvent(PlaybackEvent event) {
  return PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (_player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      const MediaControl(
        androidIcon: 'drawable/ic_speed',
        label: 'Speed',
        action: MediaAction.setSpeed,
      ),
    ],
    // ...
  );
}
```

### 3.4 Tasks

- [ ] Integrate audio handler with PlaybackController
- [ ] Implement skip next/previous for chapters
- [ ] Add 30-second skip forward/back actions
- [ ] Test all controls work from lock screen
- [ ] Test controls work from notification

---

## Phase 4: Android Configuration (1 day)

### 4.1 Manifest Updates

`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest>
  <!-- Permissions -->
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
  
  <application>
    <!-- Audio Service -->
    <service android:name="com.ryanheise.audioservice.AudioService"
        android:foregroundServiceType="mediaPlayback"
        android:exported="true">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>
    
    <!-- Media Button Receiver -->
    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
        android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver>
  </application>
</manifest>
```

### 4.2 Notification Icon

Create a notification icon at:
- `android/app/src/main/res/drawable/ic_notification.xml`

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
  <path
      android:fillColor="#FFFFFF"
      android:pathData="M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM10,16.5v-9l6,4.5 -6,4.5z"/>
</vector>
```

### 4.3 Tasks

- [ ] Update AndroidManifest.xml with required services
- [ ] Add FOREGROUND_SERVICE_MEDIA_PLAYBACK permission
- [ ] Create notification icons
- [ ] Test on various Android versions (API 26+)

---

## Phase 5: iOS Configuration (1 day)

### 5.1 Info.plist Updates

`ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### 5.2 AppDelegate Updates (if needed)

```swift
// ios/Runner/AppDelegate.swift
import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure audio session for background playback
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio)
      try audioSession.setActive(true)
    } catch {
      print("Failed to set audio session: \(error)")
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### 5.3 Tasks

- [ ] Add audio background mode to Info.plist
- [ ] Configure audio session for spoken audio
- [ ] Test lock screen controls on iOS
- [ ] Test Control Center playback controls

---

## Phase 6: Enhanced Features (2-3 days)

### 6.1 Chapter Navigation

Display chapter info in the notification:

```dart
MediaItem createMediaItem({
  required Book book,
  required int chapterIndex,
}) {
  final chapter = book.chapters[chapterIndex];
  return MediaItem(
    id: '${book.id}:$chapterIndex',
    title: chapter.title,
    album: book.title,
    artist: book.author,
    artUri: book.coverImagePath != null ? Uri.file(book.coverImagePath!) : null,
    extras: {
      'chapterIndex': chapterIndex,
      'totalChapters': book.chapters.length,
    },
  );
}
```

### 6.2 Seek Bar Progress

Update position regularly:

```dart
Timer.periodic(const Duration(seconds: 1), (_) {
  if (_player.playing) {
    playbackState.add(playbackState.value.copyWith(
      updatePosition: _player.position,
    ));
  }
});
```

### 6.3 Custom Actions

Add bookmark and sleep timer quick actions:

```dart
final customActions = {
  'bookmark': const MediaControl(
    androidIcon: 'drawable/ic_bookmark',
    label: 'Bookmark',
    action: MediaAction.custom,
  ),
  'sleep': const MediaControl(
    androidIcon: 'drawable/ic_sleep',
    label: 'Sleep Timer',
    action: MediaAction.custom,
  ),
};

@override
Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
  switch (name) {
    case 'bookmark':
      onBookmark?.call();
      break;
    case 'sleep':
      onSleepTimer?.call();
      break;
  }
}
```

### 6.4 Tasks

- [ ] Implement chapter info in media metadata
- [ ] Add seek bar position updates
- [ ] Consider custom actions for bookmarks/sleep timer
- [ ] Test with Bluetooth headphones
- [ ] Test with Android Auto (if applicable)

---

## Phase 7: Testing & Edge Cases (1-2 days)

### 7.1 Test Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| App in foreground | Notification visible, controls work |
| App in background | Playback continues, notification visible |
| Screen locked | Lock screen controls work |
| Notification shade | All buttons functional |
| Bluetooth connect | Auto-resume if was playing |
| Bluetooth disconnect | Pause playback |
| Phone call incoming | Pause playback, duck audio |
| Phone call ends | Resume playback |
| App killed by system | Playback may stop, restart gracefully |
| Headphone unplug | Pause playback |

### 7.2 Error Handling

```dart
try {
  await audioHandler.play();
} catch (e) {
  // Handle audio focus issues
  if (e is PlatformException) {
    // May need to request audio focus again
  }
}
```

### 7.3 Tasks

- [ ] Test all scenarios in table above
- [ ] Handle audio focus interruptions
- [ ] Test on multiple Android versions
- [ ] Test on iOS devices
- [ ] Verify battery usage is reasonable

---

## Estimated Timeline

| Phase | Description | Duration |
|-------|-------------|----------|
| 1 | Audio Handler Setup | 1-2 days |
| 2 | Media Metadata | 1-2 days |
| 3 | Playback Controls Integration | 2-3 days |
| 4 | Android Configuration | 1 day |
| 5 | iOS Configuration | 1 day |
| 6 | Enhanced Features | 2-3 days |
| 7 | Testing & Edge Cases | 1-2 days |
| **Total** | | **9-14 days** |

---

## Package Dependencies

Already in `pubspec.yaml`:
```yaml
dependencies:
  just_audio: ^0.10.5
  audio_service: ^0.18.18
```

Optional additional packages:
```yaml
dependencies:
  audio_session: ^0.1.21  # Already included - for audio focus
```

---

## Files to Create/Modify

### New Files

```
lib/app/audio_service_handler.dart     # Main audio handler implementation
android/app/src/main/res/drawable/ic_notification.xml  # Notification icon
android/app/src/main/res/drawable/ic_speed.xml         # Speed control icon
android/app/src/main/res/drawable/ic_bookmark.xml      # Bookmark icon (optional)
```

### Modified Files

```
lib/main.dart                                  # Initialize AudioService
lib/app/playback_providers.dart               # Add audio handler provider
packages/playback/lib/src/playback_controller.dart  # Integrate with handler
android/app/src/main/AndroidManifest.xml      # Add service and permissions
ios/Runner/Info.plist                          # Add background audio mode
```

---

## References

- [audio_service package](https://pub.dev/packages/audio_service)
- [just_audio package](https://pub.dev/packages/just_audio)
- [Audio Service Example](https://github.com/ryanheise/audio_service/blob/master/audio_service/example/lib/main.dart)
- [Android Media Session Guide](https://developer.android.com/guide/topics/media-apps/audio-app/building-a-mediabrowserservice)
- [iOS Background Audio Guide](https://developer.apple.com/documentation/avfoundation/media_playback/controlling_background_audio)

---

## Success Criteria

- [ ] Play/pause works from lock screen on Android and iOS
- [ ] Skip next/previous works for chapter navigation
- [ ] Book title, chapter name, and author display correctly
- [ ] Cover art displays on lock screen
- [ ] Seek bar shows progress and allows seeking
- [ ] Notification persists during background playback
- [ ] Audio focus handled correctly (pause on calls, etc.)
- [ ] Battery impact is minimal
- [ ] Controls work with Bluetooth devices
