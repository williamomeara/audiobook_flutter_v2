# Smart Synthesis Architecture

Smart Synthesis is the intelligent prefetching system that ensures seamless audiobook playback by predicting and pre-synthesizing audio segments before they're needed.

## Why Smart Synthesis Exists

### Without Smart Synthesis (On-Demand Only)
```
User presses Play
  → Wait 2-5 seconds while segment 1 synthesizes
  → Segment 1 plays (5-10 seconds)
  → PAUSE - Wait 2-5 seconds while segment 2 synthesizes
  → Segment 2 plays
  → PAUSE - Wait 2-5 seconds...
  → Repeat forever
```
**Result:** Stuttery, interrupted listening with pauses every few seconds.

### With Smart Synthesis (Current Implementation)
```
User presses Play
  → Wait 100-500ms while segment 1 synthesizes (cold-start)
  → Segment 1 plays
  → Background: Segments 2, 3, 4, 5 synthesizing ahead
  → Segment 2 plays (already ready!)
  → Background continues prefetching...
  → Seamless playback throughout
```
**Result:** Smooth, uninterrupted audiobook experience.

## Overview

The system eliminates buffering pauses by:
1. **Cold-start preparation** - Pre-synthesizing the first segment synchronously before playback begins
2. **Adaptive prefetching** - Continuously synthesizing upcoming segments based on device capabilities
3. **Resource awareness** - Adjusting behavior based on battery state and device performance

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PLAYBACK LAYER                              │
│  ┌─────────────────┐    ┌──────────────────┐    ┌───────────────┐  │
│  │ PlaybackManager │───▶│  BufferScheduler │───▶│ AudioService  │  │
│  └────────┬────────┘    └────────┬─────────┘    └───────────────┘  │
│           │                      │                                  │
│           │              ┌───────▼────────┐                        │
│           │              │ SynthesisState │                        │
│           │              │    Manager     │                        │
│           │              └───────┬────────┘                        │
└───────────│──────────────────────│──────────────────────────────────┘
            │                      │
            │              ┌───────▼────────────────┐
            │              │  Strategy Selection    │
            │              │  ┌─────────────────┐   │
            │              │  │   Conservative  │   │
            │              │  │     Adaptive    │   │
            │              │  │    Aggressive   │   │
            │              │  └─────────────────┘   │
            │              └───────┬────────────────┘
            │                      │
┌───────────▼──────────────────────▼──────────────────────────────────┐
│                       SYNTHESIS LAYER                               │
│  ┌──────────────────────┐    ┌────────────────────────────────┐    │
│  │ SmartSynthesisManager│───▶│ ParallelSynthesisOrchestrator │    │
│  └──────────┬───────────┘    └────────────────────────────────┘    │
│             │                                                       │
│  ┌──────────▼───────────┐                                          │
│  │    TTS Engines       │                                          │
│  │  ┌─────┐ ┌───────┐   │                                          │
│  │  │Piper│ │Kokoro │   │                                          │
│  │  └─────┘ └───────┘   │                                          │
│  └──────────────────────┘                                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. SmartSynthesisManager
**Location:** `packages/tts_engines/lib/src/smart_synthesis/`

Abstract manager that handles cold-start preparation:
- `prepareForPlayback()` - Called when opening a book/chapter
- Pre-synthesizes first segment **synchronously** (blocks until ready)
- Starts second segment **asynchronously** (fire-and-forget)

```dart
abstract class SmartSynthesisManager {
  Future<SmartSynthesisResult> prepareForPlayback({
    required String text,
    required String voiceId,
    required int chapterIndex,
    int startSegment = 0,
  });
}
```

### 2. BufferScheduler
**Location:** `packages/playback/lib/src/buffer_scheduler.dart`

Core prefetch orchestrator that decides **what** and **when** to synthesize:
- Monitors buffer levels (low watermark/target)
- Triggers prefetch when buffer drops below threshold
- Supports sequential and parallel prefetching
- Handles cancellation on context changes (book/chapter/voice)

### 3. SynthesisStrategyManager
**Location:** `packages/playback/lib/src/strategies/synthesis_strategy_manager.dart`

Automatically selects the optimal strategy based on device state:

| Strategy | Condition | Behavior |
|----------|-----------|----------|
| **Conservative** | Low power mode | Minimal prefetch, battery saving |
| **Adaptive** | Normal operation | Balanced prefetch based on RTF |
| **Aggressive** | Charging | Maximum prefetch for uninterrupted playback |

### 4. ParallelSynthesisOrchestrator
**Location:** `packages/playback/lib/src/synthesis/parallel_orchestrator.dart`

Coordinates concurrent synthesis tasks:
- Uses semaphores to limit concurrent operations
- Tracks incremental progress even with parallel synthesis
- Falls back to sequential if disabled or unavailable

## State Machine

See [STATE_MACHINE.md](./STATE_MACHINE.md) for the complete state diagram.

## Performance Metrics

### Real-Time Factor (RTF)
```
RTF = synthesis_time / audio_duration
```
- RTF < 1.0 = Faster than real-time (good)
- RTF > 1.0 = Slower than real-time (may cause buffering)

### Device Tiers
The system calibrates itself based on device performance:

| Tier | RTF Benchmark | Example Devices |
|------|---------------|-----------------|
| Flagship | < 0.3 | High-end phones |
| Mid-Range | 0.3 - 0.6 | Modern budget phones |
| Budget | 0.6 - 1.0 | Older devices |
| Legacy | > 1.0 | Very old devices |

## Cancellation & Safety

### CancellationToken
Allows immediate abort of synthesis operations:
- Book change → Cancel all pending synthesis
- Chapter change → Cancel and restart for new chapter
- Voice change → Cancel and restart with new voice

### AsyncLock
Protects atomic buffer updates:
```dart
await _prefetchLock.synchronized(() async {
  // Protected buffer manipulation
});
```

## Configuration

### Buffer Thresholds
```dart
const lowWatermarkSegments = 2;   // Trigger prefetch below this
const targetBufferSegments = 5;   // Prefetch until reaching this
```

### Parallel Synthesis
```dart
const maxConcurrentSynthesis = 3; // Semaphore limit
```

## Usage Example

```dart
// Cold-start: Open book
final result = await smartSynthesisManager.prepareForPlayback(
  text: chapterText,
  voiceId: selectedVoice,
  chapterIndex: 0,
  startSegment: 0,
);

// Start playback with first segment ready
await playbackManager.play();

// BufferScheduler automatically handles ongoing prefetch
```

## Related Documentation

- [State Machine](./STATE_MACHINE.md) - Complete state diagram
- [TTS Engines](../tts-engines/) - Engine-specific implementations
- [Playback System](../playback/) - Audio playback architecture

## Future Improvements

### High Priority
1. **Smarter chapter transitions** - Pre-synthesize first segment of next chapter while finishing current chapter (eliminates cold-start delay at chapter boundaries)

### Medium Priority
2. **Cache warming on Wi-Fi** - Pre-synthesize entire chapters when on Wi-Fi + charging overnight
3. **Reading direction awareness** - Cache segments behind current position if user frequently rewinds

### Low Priority
4. **Time-of-day adaptation** - More aggressive prefetch at bedtime (user likely falling asleep)
5. **Chapter structure priority** - Detect chapter starts/dialogue sections, prioritize caching
6. **Live cache indicator** - Show real-time "X segments ready" counter during playback
