# Playback Navigation State Machine (Proposed Design)

**Version**: 1.0 (Draft)  
**Date**: 2026-01-30  
**Status**: For Review

---

## Executive Summary

This document defines the complete state machine for audiobook playback navigation. The design uses **sealed classes** and **explicit events** to ensure impossible states cannot occur and all transitions are predictable and testable.

---

## Core Principles

1. **Single Source of Truth**: One state object determines all UI behavior
2. **Impossible States Are Impossible**: Sealed classes prevent invalid combinations
3. **Explicit Intent**: User actions are modeled as events, not inferred from context
4. **Pure Transitions**: State changes are deterministic functions of (current state, event)
5. **Derived UI**: All UI decisions flow from the current state, not scattered conditionals

---

## States

### PlaybackViewState (Sealed Hierarchy)

```
PlaybackViewState
├── Idle           - No playback active, no preview
├── Loading        - Transitioning to new content
├── Active         - Actively playing/paused, viewing same content
└── Preview        - Viewing different content while audio plays elsewhere
```

### State Definitions

#### 1. Idle
**Description**: No audio is loaded. User is browsing the app without active playback.

**Context Data**:
- None

**UI Characteristics**:
- No mini player anywhere in app
- No playback controls
- "Start Listening" available on book details

**Entered From**:
- App launch (no previous session)
- Audio stopped/completed
- User explicitly stops playback

---

#### 2. Loading
**Description**: Transitioning to new content. Audio is being prepared.

**Context Data**:
- `bookId`: Book being loaded
- `chapterIndex`: Chapter being loaded
- `segmentIndex`: Starting segment (optional)

**UI Characteristics**:
- Loading indicator shown
- Previous audio (if any) continues until load completes
- User can cancel (back navigation)

**Entered From**:
- User initiates playback from any state
- Automatic chapter advance (next chapter loading)

---

#### 3. Active
**Description**: User is viewing and controlling the currently playing (or paused) audio.

**Context Data**:
- `bookId`: Currently playing book
- `chapterIndex`: Currently playing chapter
- `segmentIndex`: Current segment index
- `isPlaying`: true/false for play/pause state
- `autoScrollEnabled`: Whether text auto-scrolls to current segment

**UI Characteristics**:
- Full playback controls (play/pause, skip, speed, sleep timer)
- Segment seek slider
- Auto-scroll follows audio (when enabled)
- "Jump to Audio" button (when auto-scroll disabled by user scroll)
- Position auto-saved every 30 seconds

**Entered From**:
- Loading completes successfully
- User taps segment in Preview mode (commits to that position)
- User taps "Start Listening" / "Continue Listening" button

---

#### 4. Preview
**Description**: User is browsing content different from what's currently playing. Audio continues in background.

**Context Data**:
- **Viewing Context**:
  - `viewingBookId`: Book being browsed
  - `viewingChapterIndex`: Chapter being viewed
  - `viewingSegments`: Loaded segments for display
- **Playing Context**:
  - `playingBookId`: Book currently playing
  - `playingChapterIndex`: Chapter currently playing
  - `playingSegmentIndex`: Current playing segment

**UI Characteristics**:
- Mini player at bottom (shows what's playing, NOT what's being viewed)
- Text display shows viewed chapter (tappable to commit)
- No full playback controls (only mini player has play/pause)
- No auto-scroll (user is browsing, not following audio)
- NO "Jump to Audio" button (use mini player instead)
- Position NOT auto-saved (just browsing)

**Entered From**:
- User navigates to different chapter while audio plays
- User navigates to different book while audio plays

---

## Events

### User-Initiated Events

| Event | Description | Payload |
|-------|-------------|---------|
| `StartListeningPressed` | User clicks main action button on Book Details | bookId, chapterIndex, segmentIndex |
| `ChapterSelected` | User taps a chapter in chapter list | bookId, chapterIndex |
| `SegmentTapped` | User taps a segment in text view | segmentIndex |
| `MiniPlayerTapped` | User taps the mini player | (none) |
| `BackPressed` | User navigates back | (none) |
| `PlayPauseToggled` | User toggles play/pause | (none) |
| `StopPressed` | User explicitly stops playback | (none) |
| `UserScrolled` | User manually scrolls the text view | (none) |
| `JumpToAudioPressed` | User requests to jump to current audio position | (none) |

### System Events

| Event | Description | Payload |
|-------|-------------|---------|
| `LoadingComplete` | Chapter finished loading | segments |
| `LoadingFailed` | Chapter failed to load | error |
| `ChapterEnded` | Current chapter playback completed | (none) |
| `AudioError` | Audio playback error occurred | error |

---

## Transition Table

### From Idle

| Event | Guard | Next State | Actions |
|-------|-------|------------|---------|
| `StartListeningPressed` | - | Loading | Load chapter |
| `ChapterSelected` | - | Loading | Load chapter |

### From Loading

| Event | Guard | Next State | Actions |
|-------|-------|------------|---------|
| `LoadingComplete` | - | Active | Start playback, enable auto-scroll |
| `LoadingFailed` | - | Idle | Show error, clean up |
| `BackPressed` | - | Previous state | Cancel loading |

### From Active

| Event | Guard | Next State | Actions |
|-------|-------|------------|---------|
| `ChapterSelected` | Same book, different chapter | Preview | Load preview segments |
| `ChapterSelected` | Same book, same chapter | Active | Seek to start (or no-op) |
| `StartListeningPressed` | Different book | Loading | Pause current, load new book |
| `StartListeningPressed` | Same book | Active | No-op (already playing) |
| `SegmentTapped` | - | Active | Seek to segment |
| `UserScrolled` | - | Active | Disable auto-scroll |
| `JumpToAudioPressed` | - | Active | Re-enable auto-scroll, scroll to current |
| `PlayPauseToggled` | - | Active | Toggle isPlaying |
| `ChapterEnded` | Has next chapter | Loading | Load next chapter |
| `ChapterEnded` | No next chapter | Idle | Mark book complete |
| `StopPressed` | - | Idle | Stop playback, save position |
| `BackPressed` | - | Exit screen | Save position |

### From Preview

| Event | Guard | Next State | Actions |
|-------|-------|------------|---------|
| `SegmentTapped` | - | Loading → Active | Stop old audio, load+play tapped position |
| `StartListeningPressed` | Same book as viewing | Loading → Active | Load from viewing position |
| `StartListeningPressed` | Different book | Loading → Active | Stop old audio, load new book |
| `MiniPlayerTapped` | - | Active | Navigate to playing book/chapter |
| `ChapterSelected` | Same as viewing book | Preview | Update viewing chapter |
| `ChapterSelected` | Different book | Preview | Update viewing book+chapter |
| `BackPressed` | - | Depends on nav stack | Keep audio playing |
| `PlayPauseToggled` | via mini player | Preview | Toggle playing audio |

---

## State Diagrams

### High-Level Flow

```
                    ┌─────────────────────────────────────────────────────┐
                    │                                                     │
                    ▼                                                     │
              ┌──────────┐                                               │
              │          │                                               │
     ┌───────►│   Idle   │◄──────────────────────────────────────────┐   │
     │        │          │                                            │   │
     │        └────┬─────┘                                            │   │
     │             │                                                  │   │
     │             │ StartListeningPressed                            │   │
     │             │ ChapterSelected                                  │   │
     │             ▼                                                  │   │
     │        ┌──────────┐                                            │   │
     │        │          │  LoadingFailed                             │   │
     │        │ Loading  │────────────────────────────────────────────┘   │
     │        │          │                                                │
     │        └────┬─────┘                                                │
     │             │                                                      │
     │             │ LoadingComplete                                      │
     │             ▼                                                      │
     │        ┌──────────┐                                                │
     │        │          │  ChapterEnded (no more chapters)              │
     │        │  Active  │────────────────────────────────────────────────┘
     │        │          │
     │        └────┬─────┘
     │             │
     │             │ ChapterSelected (different chapter)
     │             │ Navigate to different book
     │             ▼
     │        ┌──────────┐
     │        │          │
     │        │ Preview  │
     │        │          │
     │        └────┬─────┘
     │             │
     │             │ SegmentTapped
     │             │ StartListeningPressed
     │             │ MiniPlayerTapped
     │             │
     └─────────────┘ (back to Active or Loading)
```

### Preview Mode Detail

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            PREVIEW MODE                                      │
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────┐     │
│   │                        VIEWING CONTEXT                             │     │
│   │  Book: "War and Peace"  Chapter: 15                               │     │
│   │  [Text segments displayed - tappable]                             │     │
│   │                                                                    │     │
│   │  Tap any paragraph → exits preview, plays that paragraph          │     │
│   └───────────────────────────────────────────────────────────────────┘     │
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────┐     │
│   │                        MINI PLAYER                                 │     │
│   │  🎵 Currently Playing: "1984" - Chapter 3                         │     │
│   │  [Tap to return to 1984]                    [▶️ Play/Pause]        │     │
│   └───────────────────────────────────────────────────────────────────┘     │
│                                                                              │
│   Actions:                                                                   │
│   • Tap text → commit to War and Peace, stop 1984                           │
│   • Tap mini player → return to 1984 playback (exit preview)                │
│   • Tap "Start Listening" → commit to War and Peace from saved position     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## UI Derivation Rules

All UI decisions are derived from the current state. No additional boolean flags needed.

| UI Element | Idle | Loading | Active | Preview |
|------------|------|---------|--------|---------|
| Show mini player (on other screens) | ❌ | ✅ | ✅ | ✅ |
| Show full playback controls | - | ❌ | ✅ | ❌ |
| Show mini player (on playback screen) | - | - | ❌ | ✅ |
| Show loading indicator | - | ✅ | ❌ | ❌ |
| Auto-scroll text | - | - | Derived from `autoScrollEnabled` | ❌ |
| Show "Jump to Audio" button | - | - | When `!autoScrollEnabled` | ❌ |
| Auto-save position | - | - | ✅ | ❌ |
| Segment tap action | - | - | Seek | Commit & Play |

---

## Implementation Types (Dart)

```dart
/// The complete view state for playback screen
sealed class PlaybackViewState {
  const PlaybackViewState();
}

/// No active playback
class IdleState extends PlaybackViewState {
  const IdleState();
}

/// Transitioning to new content
class LoadingState extends PlaybackViewState {
  final String bookId;
  final int chapterIndex;
  final int? segmentIndex;
  
  const LoadingState({
    required this.bookId,
    required this.chapterIndex,
    this.segmentIndex,
  });
}

/// Actively controlling playback
class ActiveState extends PlaybackViewState {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  final bool isPlaying;
  final bool autoScrollEnabled;
  final List<Segment> segments;
  
  const ActiveState({
    required this.bookId,
    required this.chapterIndex,
    required this.segmentIndex,
    required this.isPlaying,
    required this.autoScrollEnabled,
    required this.segments,
  });
  
  ActiveState copyWith({
    int? segmentIndex,
    bool? isPlaying,
    bool? autoScrollEnabled,
  }) => ActiveState(
    bookId: bookId,
    chapterIndex: chapterIndex,
    segmentIndex: segmentIndex ?? this.segmentIndex,
    isPlaying: isPlaying ?? this.isPlaying,
    autoScrollEnabled: autoScrollEnabled ?? this.autoScrollEnabled,
    segments: segments,
  );
}

/// Browsing content while audio plays elsewhere
class PreviewState extends PlaybackViewState {
  // What user is viewing
  final String viewingBookId;
  final int viewingChapterIndex;
  final List<Segment> viewingSegments;
  
  // What is actually playing
  final String playingBookId;
  final int playingChapterIndex;
  final int playingSegmentIndex;
  final bool isPlaying;
  
  const PreviewState({
    required this.viewingBookId,
    required this.viewingChapterIndex,
    required this.viewingSegments,
    required this.playingBookId,
    required this.playingChapterIndex,
    required this.playingSegmentIndex,
    required this.isPlaying,
  });
  
  /// Same book but different chapter?
  bool get isSameBookPreview => viewingBookId == playingBookId;
  
  /// Cross-book preview?
  bool get isCrossBookPreview => viewingBookId != playingBookId;
}
```

```dart
/// All possible user and system events
sealed class PlaybackEvent {
  const PlaybackEvent();
}

// User events
class StartListeningPressed extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  const StartListeningPressed({
    required this.bookId,
    required this.chapterIndex,
    required this.segmentIndex,
  });
}

class ChapterSelected extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;
  const ChapterSelected({required this.bookId, required this.chapterIndex});
}

class SegmentTapped extends PlaybackEvent {
  final int segmentIndex;
  const SegmentTapped(this.segmentIndex);
}

class MiniPlayerTapped extends PlaybackEvent {
  const MiniPlayerTapped();
}

class PlayPauseToggled extends PlaybackEvent {
  const PlayPauseToggled();
}

class UserScrolled extends PlaybackEvent {
  const UserScrolled();
}

class JumpToAudioPressed extends PlaybackEvent {
  const JumpToAudioPressed();
}

class StopPressed extends PlaybackEvent {
  const StopPressed();
}

class BackPressed extends PlaybackEvent {
  const BackPressed();
}

// System events
class LoadingComplete extends PlaybackEvent {
  final List<Segment> segments;
  const LoadingComplete(this.segments);
}

class LoadingFailed extends PlaybackEvent {
  final String error;
  const LoadingFailed(this.error);
}

class ChapterEnded extends PlaybackEvent {
  const ChapterEnded();
}
```

---

## Transition Function (Pure)

```dart
/// Pure function: given current state and event, compute next state
/// Side effects (loading, playing) are handled separately by listeners
(PlaybackViewState, List<SideEffect>) transition(
  PlaybackViewState state,
  PlaybackEvent event,
) {
  return switch ((state, event)) {
    // From Idle
    (IdleState(), StartListeningPressed e) => (
      LoadingState(bookId: e.bookId, chapterIndex: e.chapterIndex, segmentIndex: e.segmentIndex),
      [LoadChapter(e.bookId, e.chapterIndex)],
    ),
    
    // From Loading
    (LoadingState s, LoadingComplete e) => (
      ActiveState(
        bookId: s.bookId,
        chapterIndex: s.chapterIndex,
        segmentIndex: s.segmentIndex ?? 0,
        isPlaying: true,
        autoScrollEnabled: true,
        segments: e.segments,
      ),
      [StartPlayback(s.bookId, s.chapterIndex, s.segmentIndex ?? 0)],
    ),
    (LoadingState(), LoadingFailed e) => (
      IdleState(),
      [ShowError(e.error)],
    ),
    
    // From Active - chapter selection
    (ActiveState s, ChapterSelected e) when e.bookId == s.bookId && e.chapterIndex != s.chapterIndex => (
      // Enter preview mode for different chapter of same book
      PreviewState(
        viewingBookId: e.bookId,
        viewingChapterIndex: e.chapterIndex,
        viewingSegments: [], // Will be loaded
        playingBookId: s.bookId,
        playingChapterIndex: s.chapterIndex,
        playingSegmentIndex: s.segmentIndex,
        isPlaying: s.isPlaying,
      ),
      [LoadPreviewSegments(e.bookId, e.chapterIndex)],
    ),
    
    // From Active - user interactions
    (ActiveState s, SegmentTapped e) => (
      s.copyWith(segmentIndex: e.segmentIndex, autoScrollEnabled: true),
      [SeekTo(e.segmentIndex)],
    ),
    (ActiveState s, UserScrolled()) => (
      s.copyWith(autoScrollEnabled: false),
      [],
    ),
    (ActiveState s, JumpToAudioPressed()) => (
      s.copyWith(autoScrollEnabled: true),
      [ScrollToSegment(s.segmentIndex)],
    ),
    (ActiveState s, PlayPauseToggled()) => (
      s.copyWith(isPlaying: !s.isPlaying),
      [s.isPlaying ? PauseAudio() : PlayAudio()],
    ),
    
    // From Preview - commit to preview content
    (PreviewState s, SegmentTapped e) => (
      LoadingState(bookId: s.viewingBookId, chapterIndex: s.viewingChapterIndex, segmentIndex: e.segmentIndex),
      [PauseAudio(), LoadChapter(s.viewingBookId, s.viewingChapterIndex)],
    ),
    (PreviewState s, StartListeningPressed e) => (
      LoadingState(bookId: e.bookId, chapterIndex: e.chapterIndex, segmentIndex: e.segmentIndex),
      [PauseAudio(), LoadChapter(e.bookId, e.chapterIndex)],
    ),
    
    // From Preview - return to playing content
    (PreviewState s, MiniPlayerTapped()) => (
      ActiveState(
        bookId: s.playingBookId,
        chapterIndex: s.playingChapterIndex,
        segmentIndex: s.playingSegmentIndex,
        isPlaying: s.isPlaying,
        autoScrollEnabled: true,
        segments: [], // Needs to be loaded/cached
      ),
      [NavigateToChapter(s.playingBookId, s.playingChapterIndex)],
    ),
    
    // Default: no change
    _ => (state, []),
  };
}
```

---

## Side Effects

Side effects are actions that need to happen as a result of a transition. They're returned alongside the new state and executed by a listener.

```dart
sealed class SideEffect {}

class LoadChapter extends SideEffect {
  final String bookId;
  final int chapterIndex;
  LoadChapter(this.bookId, this.chapterIndex);
}

class LoadPreviewSegments extends SideEffect {
  final String bookId;
  final int chapterIndex;
  LoadPreviewSegments(this.bookId, this.chapterIndex);
}

class StartPlayback extends SideEffect {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  StartPlayback(this.bookId, this.chapterIndex, this.segmentIndex);
}

class SeekTo extends SideEffect {
  final int segmentIndex;
  SeekTo(this.segmentIndex);
}

class PlayAudio extends SideEffect {}
class PauseAudio extends SideEffect {}

class ScrollToSegment extends SideEffect {
  final int segmentIndex;
  ScrollToSegment(this.segmentIndex);
}

class ShowError extends SideEffect {
  final String message;
  ShowError(this.message);
}

class NavigateToChapter extends SideEffect {
  final String bookId;
  final int chapterIndex;
  NavigateToChapter(this.bookId, this.chapterIndex);
}

class SavePosition extends SideEffect {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  SavePosition(this.bookId, this.chapterIndex, this.segmentIndex);
}
```

---

## Testing Strategy

### Unit Tests for Transition Function

```dart
void main() {
  group('PlaybackStateMachine', () {
    test('Idle + StartListeningPressed → Loading', () {
      final (newState, effects) = transition(
        IdleState(),
        StartListeningPressed(bookId: 'book1', chapterIndex: 0, segmentIndex: 0),
      );
      
      expect(newState, isA<LoadingState>());
      expect((newState as LoadingState).bookId, 'book1');
      expect(effects, contains(isA<LoadChapter>()));
    });
    
    test('Active + ChapterSelected (different chapter) → Preview', () {
      final (newState, effects) = transition(
        ActiveState(bookId: 'book1', chapterIndex: 0, ...),
        ChapterSelected(bookId: 'book1', chapterIndex: 5),
      );
      
      expect(newState, isA<PreviewState>());
      expect((newState as PreviewState).viewingChapterIndex, 5);
      expect((newState).playingChapterIndex, 0);
    });
    
    test('Preview + SegmentTapped → Loading (commits to preview)', () {
      final (newState, effects) = transition(
        PreviewState(viewingBookId: 'bookB', playingBookId: 'bookA', ...),
        SegmentTapped(10),
      );
      
      expect(newState, isA<LoadingState>());
      expect((newState as LoadingState).bookId, 'bookB'); // Commits to previewed book
      expect(effects, contains(isA<PauseAudio>())); // Stops old audio
    });
    
    test('Active + UserScrolled → Active with autoScrollEnabled=false', () {
      final (newState, effects) = transition(
        ActiveState(autoScrollEnabled: true, ...),
        UserScrolled(),
      );
      
      expect(newState, isA<ActiveState>());
      expect((newState as ActiveState).autoScrollEnabled, false);
    });
    
    test('Preview does not show JumpToAudio (derived from state type)', () {
      final state = PreviewState(...);
      
      // UI derivation: Preview never shows JumpToAudio
      expect(state is PreviewState, true);
      // The UI code would check: state is! PreviewState && !state.autoScrollEnabled
    });
  });
}
```

---

## Migration Notes

### Mapping Current Implementation to New Design

| Current Code | New Design |
|--------------|------------|
| `_isPreviewMode` boolean | `state is PreviewState` |
| `_autoScrollEnabled` boolean | `ActiveState.autoScrollEnabled` |
| `widget.startPlayback` param | `StartListeningPressed` event |
| `isPreviewMode` prop drilling | Derived from state type at UI level |
| `_initializePlayback()` if/else | `transition()` function pattern match |
| `_enterPreviewMode()` method | Transition to `PreviewState` |
| `_exitPreviewModeAndPlay()` method | `SegmentTapped` event in Preview |

### What Changes

1. **PlaybackScreen** becomes stateless for navigation logic
2. State lives in a **Riverpod StateNotifier** (or Cubit)
3. Events dispatched instead of methods called
4. UI widgets read state and derive what to show
5. Side effects executed by separate listeners

### What Stays the Same

1. Actual audio playback code (`PlaybackController`)
2. Segment loading/synthesis logic
3. Position persistence logic
4. Visual appearance of UI components

---

## Open Questions for Review

1. **Should Loading preserve previous playback?** Currently proposed that audio continues until load completes. Alternative: pause immediately on load start.

2. **Preview of different book vs same book**: Should these be handled identically, or is there value in distinguishing them?

3. **Auto-scroll disable persistence**: Should `autoScrollEnabled=false` persist across chapter changes, or reset to true on each chapter?

4. **Error handling in Preview**: If in Preview mode and playing audio errors, what state should we enter?

5. **Book completion flow**: When last chapter ends, should we enter Idle or show a "book complete" variant?

---

## Appendix: Glossary

| Term | Definition |
|------|------------|
| **State** | A distinct mode the system can be in (Idle, Loading, Active, Preview) |
| **Event** | Something that happened (user action or system occurrence) |
| **Transition** | Movement from one state to another in response to an event |
| **Guard** | A condition that must be true for a transition to occur |
| **Side Effect** | An action performed as a result of a transition (loading, playing, navigating) |
| **Derived** | UI properties computed from state, not stored separately |
