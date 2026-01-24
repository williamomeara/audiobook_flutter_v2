# playback

Audio playback engine for the audiobook_flutter application.

## Overview

This package provides the core playback functionality:

- **PlaybackController**: Orchestrates segment playback, queuing, and state
- **AudioOutput**: just_audio wrapper with audio session management
- **Prefetch System**: Intelligent lookahead synthesis for smooth playback
- **Device Profiler**: Benchmarks device performance for optimal settings

## Key Features

- Gapless playback between segments
- Adaptive prefetch based on device performance
- Audio session handling (interruptions, becoming noisy)
- Background playback support via audio_service integration
- Speed control and seeking

## Usage

```dart
import 'package:playback/playback.dart';

final controller = PlaybackController(
  ttsAdapter: routingEngine,
  cacheDir: cachePath,
);

await controller.loadChapter(segments);
await controller.play();
```

## Part of audiobook_flutter_v2

This is an internal package for the audiobook_flutter_v2 project and is not published to pub.dev.
