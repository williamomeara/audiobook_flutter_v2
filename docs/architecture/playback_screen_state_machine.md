# Playback Screen State Machine

This document describes the state machine governing the playback screen UI and its interactions with the underlying playback controller.

## Overview

The playback screen manages audiobook playback, displaying the current segment, controlling playback, and providing navigation. The state machine coordinates between UI states, synthesis pipeline, and audio player.

## State Model

### PlaybackState Properties

| Property | Type | Description |
|----------|------|-------------|
| `isPlaying` | bool | Audio is actively playing |
| `isBuffering` | bool | Waiting for TTS synthesis |
| `currentTrack` | AudioTrack? | Currently active segment |
| `queue` | List<AudioTrack> | All segments in chapter |
| `bookId` | String? | Current book identifier |
| `playbackRate` | double | Speed multiplier (0.5-2.0) |
| `error` | String? | Error message if playback failed |

### Derived Properties

- `currentIndex`: Index of currentTrack in queue (-1 if not found)
- `hasNextTrack`: currentIndex < queue.length - 1
- `PlaybackState.empty`: Default state with all null/false/empty values

---

## Primary States

```
┌─────────────────────────────────────────────────────────────────┐
│                    PLAYBACK SCREEN STATES                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────┐     ┌─────────┐     ┌───────────┐     ┌─────────┐ │
│  │  IDLE   │────▶│ LOADING │────▶│ BUFFERING │────▶│ PLAYING │ │
│  └─────────┘     └─────────┘     └───────────┘     └────┬────┘ │
│       │                               ▲                  │      │
│       │                               │                  │      │
│       │                               │              ┌───▼───┐  │
│       │                               └──────────────│PAUSED │  │
│       │                                              └───────┘  │
│       │                                                         │
│       │          ┌─────────┐                                    │
│       └─────────▶│  ERROR  │◀───────────(from any state)        │
│                  └─────────┘                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### State Definitions

| State | Condition | UI Rendering |
|-------|-----------|--------------|
| **IDLE** | queue.isEmpty, currentTrack == null | "Select a book" message |
| **LOADING** | queue.isEmpty, loading chapter | Spinner + "Loading chapter..." |
| **BUFFERING** | isBuffering == true | Play button shows spinner |
| **PLAYING** | isPlaying == true, !isBuffering | Play button shows pause icon |
| **PAUSED** | isPlaying == false, !isBuffering, currentTrack != null | Play button shows play icon |
| **ERROR** | error != null | Error banner + disabled controls |

---

## State Transitions

### Chapter Loading Flow

```
IDLE
  │
  │ loadChapter(book, chapterIndex, autoPlay: true)
  ▼
LOADING
  │
  │ Pre-synthesis phase (SmartSynthesisManager)
  │ ├─ Segments created from chapter content
  │ ├─ State: (queue loaded, buffering=true, playing=false)
  │ └─ First segment synthesized
  │
  │ _speakCurrent()
  ▼
BUFFERING
  │
  │ ├─ Voice readiness check
  │ ├─ TTS synthesis
  │ └─ playFile() call
  ▼
PLAYING
  │
  └─ Background prefetch starts
```

### Play/Pause Toggle

```
PLAYING ──────────────────▶ PAUSED
         pause()
         ├─ _playIntent = false
         ├─ audioOutput.pause()
         └─ State: (isPlaying=false, isBuffering=false)

PAUSED ───────────────────▶ PLAYING (same track)
         play() [if _speakingTrackId == currentTrack.id]
         └─ audioOutput.resume()

PAUSED ───────────────────▶ BUFFERING ──────▶ PLAYING (different track)
         play() [if track changed]
         ├─ _speakCurrent()
         └─ Full synthesis required
```

### Segment Navigation

```
PLAYING ─── nextTrack() ───▶ BUFFERING ──────▶ PLAYING
            │
            ├─ _playIntentOverride = true (prevent flicker)
            ├─ Update currentTrack to next segment
            ├─ State: (isPlaying=true, isBuffering=true)
            ├─ _speakCurrent()
            └─ _playIntentOverride = false (after playFile)

PLAYING ─── previousTrack() ───▶ BUFFERING ──────▶ PLAYING
            │
            └─ seekToTrack(idx - 1, play: true)

PLAYING ─── seekToTrack(idx) ───▶ (debounce 200ms) ───▶ BUFFERING ──────▶ PLAYING
            │
            ├─ Stop current playback
            ├─ State: (currentTrack=new, isPlaying=true, isBuffering=true)
            └─ After debounce: _speakCurrent()
```

### End of Chapter

```
PLAYING ─── (last segment completes) ───▶ PAUSED
            │
            │ AudioEvent.completed received
            │ nextTrack() called
            │ idx >= queue.length - 1
            │
            └─ pause()
```

### Error Transitions

```
ANY STATE ─── (error occurs) ───▶ ERROR
              │
              ├─ Voice not ready: "Please download voice in Settings"
              ├─ Synthesis failure: e.toString()
              ├─ File not found: "Audio file does not exist"
              └─ Device TTS selected: "Please select AI voice"

ERROR ─── (user action) ───▶ PAUSED/IDLE
          │
          └─ Navigate away, reload chapter, or fix issue
```

---

## User Actions

| Action | Method | Transition |
|--------|--------|------------|
| Play | `play()` | PAUSED → PLAYING or BUFFERING → PLAYING |
| Pause | `pause()` | PLAYING → PAUSED |
| Next | `nextTrack()` | PLAYING → BUFFERING → PLAYING |
| Previous | `previousTrack()` | PLAYING → BUFFERING → PLAYING |
| Seek | `seekToTrack(idx)` | ANY → BUFFERING → PLAYING |
| Speed | `setPlaybackRate(rate)` | Resets prefetch, stays in current state |
| Navigate away | dispose() | Cleanup, state preserved |

---

## Prefetch States (Background)

The prefetch system runs independently to ensure smooth transitions:

```
┌─────────────────────────────────────────────────────────────┐
│                    PREFETCH PIPELINE                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌─────────────┐ │
│  │ PRE-SYNTHESIS│────▶│   IMMEDIATE  │────▶│ BACKGROUND  │ │
│  │ (1 segment)  │     │ NEXT (n+1)   │     │   PREFETCH  │ │
│  └──────────────┘     └──────────────┘     └─────────────┘ │
│                                                             │
│  Phase 1: Chapter    Phase 2: Before    Phase 3: Watermark │
│  load with autoPlay  playFile returns   based buffering    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Prefetch Segment States

| State | Meaning |
|-------|---------|
| `notQueued` | Not in prefetch queue yet |
| `queued` | In prefetch queue, awaiting synthesis |
| `synthesizing` | Currently being synthesized |
| `ready` | Fully synthesized and cached |
| `failed` | Synthesis failed (will retry) |

---

## Media Control Integration

System media controls (lock screen, notifications) are synchronized via AudioServiceHandler:

```
PlaybackController ────────────────▶ AudioServiceHandler ────▶ System UI
                                     │
                                     ├─ playingStream
                                     ├─ positionStream
                                     ├─ processingStateStream
                                     └─ _playIntentOverride (prevents flicker)
```

### Override During Transitions

```
nextTrack() called
  │
  ├─ setPlayIntentOverride(true)   ◀── Media shows "playing"
  │
  ├─ Synthesis + setFilePath()
  │   └─ Player briefly shows not playing ◀── OVERRIDDEN
  │
  ├─ playFile() completes
  │
  └─ setPlayIntentOverride(false)  ◀── Resume normal state
```

---

## UI Rendering Logic

```dart
// Main render decision tree
Widget build() {
  return playbackState.when(
    loading: () => LoadingSpinner(),
    error: (e) => ErrorView(e),
    data: (state) {
      if (state.queue.isEmpty) {
        return LoadingChapterSpinner();
      }
      
      if (state.error != null) {
        return Column(children: [
          ErrorBanner(state.error),
          PlaybackControls(disabled: true),
        ]);
      }
      
      return Column(children: [
        CoverOrTextView(),
        PlayButton(
          icon: state.isBuffering 
              ? CircularProgressIndicator()
              : (state.isPlaying ? Icons.pause : Icons.play),
        ),
        ProgressIndicator(
          current: state.currentIndex + 1,
          total: state.queue.length,
        ),
      ]);
    },
  );
}
```

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Rapid seeking | Debounced by 200ms, only last seek triggers synthesis |
| Operation cancellation | `_opId` pattern ensures stale results ignored |
| Same-track resume | Skips synthesis, calls `audioOutput.resume()` |
| Voice download needed | Transitions to ERROR with download prompt |
| Chapter has no content | Single "empty" track created, autoPlay disabled |
| Low battery | ResourceMonitor limits prefetch window |
| Screen rotation | State preserved, layout adapts |

---

## Implementation Files

| File | Purpose |
|------|---------|
| `playback_screen.dart` | UI rendering based on state |
| `playback_state.dart` | State model definition |
| `playback_controller.dart` | State transitions and business logic |
| `playback_providers.dart` | Riverpod integration |
| `audio_output.dart` | Audio player wrapper |
| `audio_service_handler.dart` | System media control sync |
| `buffer_scheduler.dart` | Prefetch logic |

---

## State Invariants

1. **isPlaying = true implies isBuffering = false** (can't be both)
2. **isBuffering = true implies _playIntent = true** (only buffer if user wants to play)
3. **currentTrack != null when PLAYING/PAUSED** (always have a track when active)
4. **error != null clears on next successful operation**
5. **_speakingTrackId tracks actual playing segment** (separate from currentTrack for transitions)
