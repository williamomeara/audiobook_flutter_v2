# Sleep Timer State Machine

This document describes the state machine governing the sleep timer feature in the playback screen.

## Overview

The sleep timer allows users to automatically pause playback after a set duration. It's implemented entirely within `PlaybackScreen` using local state and a `Timer`.

**Key behaviors:**
- Timer only counts down while audio is **actively playing**
- Timer **resets to full duration** on any user interaction (navigation, speed change, seek)
- This prevents timer expiry during pauses or buffering

## State Model

### Sleep Timer Properties

| Property | Type | Description |
|----------|------|-------------|
| `_sleepTimerMinutes` | int? | Originally selected duration (null = off) |
| `_sleepTimeRemainingSeconds` | int? | Current countdown value in seconds |
| `_sleepTimer` | Timer? | Active countdown timer instance |

---

## Primary States

```
┌─────────────────────────────────────────────────────────────────┐
│                    SLEEP TIMER STATES                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────┐         ┌─────────────┐         ┌──────────────┐  │
│  │   OFF   │────────▶│   RUNNING   │────────▶│   EXPIRED    │  │
│  └────┬────┘         └──────┬──────┘         └──────┬───────┘  │
│       │                     │                       │          │
│       │              ┌──────┴──────┐                │          │
│       │              │   PAUSED    │                │          │
│       │              │ (not ticking)               │          │
│       │              └──────┬──────┘                │          │
│       │                     │                       │          │
│       │◀────────────────────┘                       │          │
│       │        (cancel)                             │          │
│       │◀────────────────────────────────────────────┘          │
│       │        (auto-reset)                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### State Definitions

| State | Condition | UI Rendering |
|-------|-----------|--------------|
| **OFF** | `_sleepTimerMinutes == null` | Moon icon with no indicator |
| **RUNNING** | `_sleepTimerMinutes != null`, audio playing | Moon icon with countdown badge (decrementing) |
| **PAUSED** | `_sleepTimerMinutes != null`, audio paused/buffering | Moon icon with countdown badge (frozen) |
| **EXPIRED** | `_sleepTimeRemainingSeconds == 0` | Briefly shows 0:00, then resets to OFF |

---

## State Transitions

### Starting Timer (OFF → RUNNING)

```
OFF
  │
  │ _setSleepTimer(minutes)   [minutes != null]
  ▼
RUNNING
  │
  ├─ _sleepTimerMinutes = minutes
  ├─ _sleepTimeRemainingSeconds = minutes * 60
  └─ _sleepTimer = Timer.periodic(1 second)
```

### Countdown Tick (RUNNING → RUNNING)

```
RUNNING
  │
  │ Timer tick (every 1 second)
  │ if (playbackState.isPlaying)  ← Only count when playing!
  │
  │ if (_sleepTimeRemainingSeconds > 0)
  ▼
RUNNING
  │
  └─ _sleepTimeRemainingSeconds -= 1
```

### Pause/Buffering (RUNNING → PAUSED)

```
RUNNING
  │
  │ Timer tick (every 1 second)
  │ if (!playbackState.isPlaying)  ← Audio paused or buffering
  ▼
PAUSED (no decrement)
  │
  └─ Timer continues ticking but skips decrement
```

### User Action Reset (RUNNING/PAUSED → RUNNING with full time)

```
RUNNING (5:23 remaining)
  │
  │ User action: play, pause, next, prev, seek, speed change
  │ _resetSleepTimer() called
  ▼
RUNNING (original duration restored)
  │
  └─ _sleepTimeRemainingSeconds = _sleepTimerMinutes * 60
```

### Timer Expiration (RUNNING → EXPIRED → OFF)

```
RUNNING
  │
  │ Timer tick with _sleepTimeRemainingSeconds == 1
  │ AND playbackState.isPlaying
  ▼
EXPIRED
  │
  ├─ _sleepTimeRemainingSeconds = 0
  ├─ playbackController.pause()
  ├─ _sleepTimerMinutes = null
  ├─ _sleepTimeRemainingSeconds = null
  └─ _sleepTimer.cancel()
  │
  ▼
OFF
```

### Cancel Timer (RUNNING/PAUSED → OFF)

```
RUNNING or PAUSED
  │
  │ _setSleepTimer(null)
  ▼
OFF
  │
  ├─ _sleepTimer.cancel()
  ├─ _sleepTimerMinutes = null
  └─ _sleepTimeRemainingSeconds = null
```

---

## User Actions That Reset Timer

| Action | Method | Resets Timer |
|--------|--------|--------------|
| Play/Pause toggle | `_togglePlay()` | ✅ Yes |
| Next segment | `_nextSegment()` | ✅ Yes |
| Previous segment | `_previousSegment()` | ✅ Yes |
| Next chapter (manual) | `_nextChapter()` | ✅ Yes |
| Previous chapter (manual) | `_previousChapter()` | ✅ Yes |
| Auto-advance chapter | `_autoAdvanceToNextChapter()` | ❌ No |
| Seek to segment | `_seekToSegment()` | ✅ Yes |
| Increase speed | `_increaseSpeed()` | ✅ Yes |
| Decrease speed | `_decreaseSpeed()` | ✅ Yes |
| Set sleep timer | `_setSleepTimer()` | Resets to new value |
| Turn off timer | `_setSleepTimer(null)` | Cancels timer |

---

## UI Components

### Sleep Timer Picker (Bottom Sheet)

```
┌─────────────────────────────────────────────────┐
│               ═══ (drag handle)                 │
│                                                 │
│              Sleep Timer                        │
│                                                 │
│  ○  Off                                         │
│  ○  5 min                                       │
│  ○  10 min                                      │
│  ●  15 min         ← selected (highlighted)     │
│  ○  30 min                                      │
│  ○  1 hour                                      │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Countdown Display (In Playback UI)

```
Portrait Mode:                    Landscape Mode:
┌─────────────────┐              ┌────────────────────────┐
│                 │              │                        │
│     🌙 14:32    │              │  🌙 14:32  |  ⏩  ⏸  │
│                 │              │                        │
└─────────────────┘              └────────────────────────┘
```

---

## Widget Mounting Behavior

The timer must handle component disposal gracefully:

```dart
_sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
  if (!mounted) {      // ← Check if widget is still mounted
    timer.cancel();
    return;
  }
  
  // Only decrement when audio is playing
  final playbackState = ref.read(playbackStateProvider);
  if (!playbackState.isPlaying) {
    return; // Skip this tick, don't decrement
  }
  
  // ... countdown logic
});
```

---

## Time Formatting

```dart
String _formatSleepTime(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}
```

**Examples:**
- 900 seconds → "15:00"
- 125 seconds → "2:05"
- 45 seconds → "0:45"

---

## State Invariants

1. **_sleepTimerMinutes == null implies _sleepTimeRemainingSeconds == null** (both null together)
2. **_sleepTimer != null implies _sleepTimerMinutes != null** (timer only exists when active)
3. **Timer only decrements when isPlaying == true** (paused audio doesn't count)
4. **User actions reset to original duration** (extends timer automatically)
5. **Timer expiration always triggers pause()** (core functionality)

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| User navigates away during countdown | Timer cancelled in dispose() |
| User closes app | Timer stopped, not persisted |
| App backgrounded | Timer continues (not pause-aware in background) |
| Playback paused by user | Timer pauses countdown (no decrement) |
| Playback buffering | Timer pauses countdown (isPlaying = false during buffering) |
| User seeks while timer active | Timer resets to full duration |
| Rapid user actions | Each action resets timer |
| Widget unmounted mid-tick | `!mounted` check prevents setState crash |
| Same duration re-selected | Timer reset to full duration |

---

## Implementation Files

| File | Purpose |
|------|---------|
| `playback_screen.dart` | Sleep timer state and UI (lines 50-53, 404-457, 459-536) |

---

## Comparison: Standard vs Enhanced Behavior

| Feature | Previous Behavior | Current Behavior |
|---------|-------------------|------------------|
| Countdown during pause | Continues counting | ✅ Pauses (no decrement) |
| User action handling | No reset | ✅ Resets to full duration |
| Buffering handling | Counted as playing | ✅ Pauses (isPlaying = false) |

---

## Future Enhancements

Based on the `how_it_works.md` specification, potential improvements include:

| Feature | Description | Current Status |
|---------|-------------|----------------|
| End of Chapter | Stop at chapter end instead of time | Not implemented |
| Audio Fade-Out | Gradual volume reduction before stop | Not implemented |
| Shake to Extend | Reset timer by shaking device | Partially (user actions reset) |
| Smart Rewind | Rewind 30s on resume after timer | Not implemented |
| Warning Phase | Volume ducking before expiration | Not implemented |

