# Playback State Machine

> **Last Updated:** January 2026  
> **Location:** `lib/app/playback/state/`

Pure function state machine for playback navigation. Separates state transitions from side effects.

## States (Sealed Hierarchy)

```dart
sealed class PlaybackViewState
├── IdleState          // No active playback
├── LoadingState       // Transitioning to new content  
├── ActiveState        // User viewing & controlling current audio
└── PreviewState       // Browsing different content while audio plays
```

### State Definitions

| State | Description | UI Characteristics |
|-------|-------------|-------------------|
| **IdleState** | No audio loaded | No mini player, no controls, "Start Listening" available |
| **LoadingState** | Preparing audio | Loading indicator, previous audio continues, can cancel |
| **ActiveState** | Viewing current playback | Full controls, auto-scroll, position auto-saves (30s) |
| **PreviewState** | Browsing while audio plays | Mini player, tap to commit, no auto-scroll/save |

---

## State Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  ┌───────────┐                                                      │
│  │   IDLE    │◀────────────────────────────────────────────────┐    │
│  └─────┬─────┘                                                 │    │
│        │ StartListeningPressed                                 │    │
│        │ ChapterSelected                                       │    │
│        │ RestorePlayback                                       │    │
│        ▼                                                       │    │
│  ┌───────────┐   LoadingComplete   ┌───────────┐               │    │
│  │  LOADING  │────────────────────▶│  ACTIVE   │◀──────────┐   │    │
│  └───────────┘                     └─────┬─────┘           │   │    │
│        │                                 │                 │   │    │
│        │ LoadingFailed                   │ ChapterSelected │   │    │
│        │ BackPressed                     │ (same book)     │   │    │
│        ▼                                 ▼                 │   │    │
│  (recover to previous)             ┌───────────┐           │   │    │
│                                    │  PREVIEW  │───────────┘   │    │
│                                    └─────┬─────┘               │    │
│                                          │ MiniPlayerTapped    │    │
│                                          │ SegmentTapped       │    │
│                                          │ StopPressed         │    │
│                                          └─────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Events (21 Types)

### User-Initiated Events
| Event | Description |
|-------|-------------|
| `StartListeningPressed` | Main button on Book Details |
| `ChapterSelected` | Tap chapter in list |
| `SegmentTapped` | Tap text segment (seek or commit) |
| `MiniPlayerTapped` | Return to active playback |
| `BackPressed` | Navigation back |
| `PlayPauseToggled` | Toggle playback |
| `StopPressed` | Stop and return to idle |
| `UserScrolled` | Manual scroll (disables auto-scroll) |
| `JumpToAudioPressed` | Re-enable auto-scroll |
| `SkipForward/SkipBackward` | Navigation |
| `SpeedChanged` | Playback rate change |
| `SleepTimerSet` | Set/cancel sleep timer |

### System Events
| Event | Description |
|-------|-------------|
| `LoadingComplete` | Chapter ready with segments |
| `LoadingFailed` | Load error |
| `PreviewSegmentsLoaded` | Preview content ready |
| `ChapterEnded` | Current chapter finished |
| `NoMorePlayableContent` | Book complete |
| `AudioError` | Playback error |
| `SegmentAdvanced` | Auto-advance to next segment |
| `PlaybackStateChanged` | External state change (audio service) |
| `AutoSaveTriggered` | 30-second save timer |
| `SleepTimerExpired` | Timer finished |
| `RestorePlayback` | App recovery |

---

## Transition Function

```dart
// Pure function: (state, event) → (newState, sideEffects)
TransitionResult transition(PlaybackViewState state, PlaybackEvent event);
```

### Key Transitions

**Idle → Loading:**
```dart
(IdleState(), StartListeningPressed e) → (
  LoadingState(bookId: e.bookId, chapterIndex: e.chapterIndex),
  [LoadChapter(e.bookId, e.chapterIndex, autoPlay: true)]
)
```

**Loading → Active:**
```dart
(LoadingState s, LoadingComplete e) → (
  ActiveState(bookId: s.bookId, chapterIndex: s.chapterIndex, ...),
  [StartPlayback(s.bookId, s.chapterIndex, segmentIndex)]
)
```

**Active → Preview (same book, different chapter):**
```dart
(ActiveState s, ChapterSelected e) when e.chapterIndex != s.chapterIndex → (
  PreviewState(viewingChapterIndex: e.chapterIndex, playing...),
  [LoadPreviewSegments(e.bookId, e.chapterIndex)]
)
```

**Preview → Active (commit to playing):**
```dart
(PreviewState s, SegmentTapped segmentIndex) → (
  LoadingState(...),
  [LoadChapter(viewingBookId, viewingChapterIndex, autoPlay: true)]
)
```

---

## Side Effects

Side effects are computed by transitions but executed by `PlaybackViewNotifier`:

| Side Effect | Action |
|------------|--------|
| `LoadChapter` | Fetch segments from DB, prepare synthesis |
| `StartPlayback` | Begin audio playback |
| `PlayAudio/PauseAudio` | Audio control |
| `StopAudio` | Stop and cleanup |
| `SeekToSegment` | Jump to specific segment |
| `SavePosition` | Persist to SQLite |
| `MarkChapterComplete` | Update completed_chapters table |
| `MarkBookComplete` | Update reading_progress table |

---

## UI Derivation

Extension methods on `PlaybackViewState` derive all UI decisions:

```dart
extension PlaybackViewStateUI on PlaybackViewState {
  bool get showMiniPlayerGlobally;      // Show on library/book details
  bool get showMiniPlayerOnPlaybackScreen;  // Show on playback screen
  bool get showFullPlaybackControls;    // Full control panel
  bool get showLoadingIndicator;        // Loading spinner
  bool get shouldAutoScroll;            // Follow audio position
  bool get showJumpToAudioButton;       // Re-sync button
  bool get shouldAutoSavePosition;      // Periodic save
  bool get segmentTapSeeks;             // Seek vs commit behavior
}
```

---

## SQLite Persistence

Position tracking uses two DAOs:

**ChapterPositionDao:**
```sql
chapter_positions(book_id, chapter_index, segment_index, is_primary, updated_at)
```
- Per-chapter positions with "primary" flag for resume support

**ProgressDao:**
```sql
reading_progress(book_id, chapter_index, segment_index, last_played_at, total_listen_time_ms)
```
- Overall book progress and listening time

---

## Files

| File | Purpose |
|------|---------|
| `playback_view_state.dart` | State definitions (sealed hierarchy) |
| `playback_event.dart` | Event definitions (21 types) |
| `playback_state_machine.dart` | Pure transition function (~450 lines) |
| `playback_side_effect.dart` | Side effect definitions |
