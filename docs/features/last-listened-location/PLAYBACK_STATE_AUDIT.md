# Playback State Machine Audit

**Date**: 2026-01-30
**Audit by**: Claude Opus 4.5

## Executive Summary

The current implementation has evolved organically with patches applied for specific bugs. This audit identifies the core issues and proposes a more robust state machine architecture that would prevent these recurring issues.

## Current Architecture Analysis

### What Exists Today

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CURRENT STATE SOURCES (FRAGMENTED)                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   PlaybackState (global provider)                                   │
│   ├── bookId: String?           - Which book is playing             │
│   ├── queue: List<AudioTrack>   - Loaded segments for chapter       │
│   ├── currentIndex: int         - Current playing segment           │
│   ├── isPlaying: bool           - Audio playing status              │
│   └── isBuffering: bool         - Waiting for audio                 │
│                                                                      │
│   PlaybackScreen (local state)                                       │
│   ├── _isPreviewMode: bool      - UI mode flag                      │
│   ├── _previewSegments: List?   - Preview text data                 │
│   ├── _currentChapterIndex: int - Chapter being viewed              │
│   ├── _autoScrollEnabled: bool  - Auto-scroll flag                  │
│   └── widget.startPlayback: bool - Navigation intent flag (NEW)     │
│                                                                      │
│   Widget parameters passed through hierarchy                         │
│   └── isPreviewMode (layouts) ─► isPreviewMode (TextDisplayView)    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Problem: Two Interleaved State Machines

**State Machine A: Audio Playback**
- Lives in `PlaybackState` (global Riverpod provider)
- Knows: which book/chapter/segment is playing, play/pause state
- Doesn't know: what the user is currently viewing

**State Machine B: Navigation/View**
- Lives scattered across PlaybackScreen local state
- Knows: what chapter/book the user is viewing, preview vs active mode
- Determines: which UI controls to show

**The Core Problem**: These two state machines need to coordinate, but they don't share a unified model. When we need to answer "should I show Jump to Audio?" we have to check:
1. Is auto-scroll disabled? (view state)
2. Is preview mode active? (view state)

This fragmentation leads to:
- Props drilling (`isPreviewMode` through 4 levels of widgets)
- Patch-on-patch fixes (add more booleans for each edge case)
- Bugs when state combinations aren't considered

## Identified Issues

### Issue 1: Navigation Intent Not Captured
**Symptom**: User clicks "Start Listening" on Book B while Book A plays → enters preview mode instead of starting playback.
**Root Cause**: The route `/playback/:bookId` doesn't encode user's intent. We patched this with `startPlayback=true` query param.
**Better Solution**: Encode intent in navigation state, not query params.

### Issue 2: Jump to Audio Button in Preview Mode
**Symptom**: Scrolling in preview mode shows "Jump to Audio" button that makes no sense.
**Root Cause**: `autoScrollEnabled` was the only condition. Preview mode wasn't considered.
**Better Solution**: A unified view state that knows what actions are valid.

### Issue 3: Mode Determination is Spread Out
**Code Location**: `_initializePlayback()` method in PlaybackScreen (~80 lines of if/else)
**Problem**: Logic checks multiple conditions to determine mode, but this happens after navigation. The determination should happen BEFORE navigation or AT navigation time.

## Proposed Architecture: Unified Navigation State

### New Model: `PlaybackViewState`

```dart
/// Describes what the PlaybackScreen should show
enum PlaybackViewMode {
  /// User is actively listening to this book/chapter
  /// - Full controls shown
  /// - Auto-scroll active
  /// - Position auto-saved
  active,
  
  /// User is previewing content while audio plays elsewhere
  /// - Mini player shows what's playing
  /// - Text is browsable but tapping commits to this position
  /// - No auto-save
  preview,
  
  /// User is starting playback of this book (explicit intent)
  /// - Load chapter and start playing
  /// - If different book was playing, stop it
  starting,
}

class PlaybackViewState {
  final PlaybackViewMode mode;
  final String bookId;
  final int chapterIndex;
  final int? segmentIndex;
  
  // Derived from mode - no need for separate booleans
  bool get showMiniPlayer => mode == PlaybackViewMode.preview;
  bool get showFullControls => mode == PlaybackViewMode.active;
  bool get autoScrollEnabled => mode == PlaybackViewMode.active;
  bool get showJumpToAudio => false; // Never in preview, handled by mini player
  bool get shouldAutoSave => mode == PlaybackViewMode.active;
}
```

### Navigation Would Set Intent

```dart
// From BookDetailsScreen "Start Listening" button:
context.push(
  '/playback/${bookId}',
  extra: PlaybackViewState(
    mode: PlaybackViewMode.starting,
    bookId: bookId,
    chapterIndex: chapter,
    segmentIndex: segment,
  ),
);

// From chapter list tap (when audio is playing):
context.push(
  '/playback/${bookId}',
  extra: PlaybackViewState(
    mode: PlaybackViewMode.preview,
    bookId: bookId,
    chapterIndex: index,
  ),
);
```

### Router Would Handle State

```dart
GoRoute(
  path: '/playback/:bookId',
  builder: (context, state) {
    final bookId = state.pathParameters['bookId']!;
    final viewState = state.extra as PlaybackViewState? ??
        _inferViewState(bookId, ref); // Fallback for deep links
    
    return PlaybackScreen(
      bookId: bookId,
      viewState: viewState,
    );
  },
),
```

### Benefits of This Approach

1. **Single Source of Truth**: `PlaybackViewState.mode` determines all UI behavior
2. **No Props Drilling**: Layouts just ask `viewState.showJumpToAudio`
3. **Intent Preserved**: Navigation carries explicit intent, not implicit detection
4. **Testable**: State machine has clear inputs (navigation) and outputs (UI)
5. **Extensible**: Add new modes without touching widget hierarchy

## Migration Path

### Phase 1: Introduce PlaybackViewState (Low Risk)
- Create the model
- Use it alongside existing state
- Verify parity with current behavior

### Phase 2: Migrate UI Decisions (Medium Risk)  
- Replace `_isPreviewMode` checks with `viewState.mode` checks
- Remove `isPreviewMode` props drilling through layouts

### Phase 3: Clean Up Navigation (Higher Risk)
- Remove query param hacks (`startPlayback=true`)
- Pass `PlaybackViewState` via `extra` in navigation
- Handle backward compatibility for deep links

## Recommendation

For today: The current patch-based approach works. The `startPlayback` param and `isPreviewMode` prop fix the immediate bugs.

For refactor sprint: Implement the unified `PlaybackViewState` model. This would prevent future state-related bugs and make the codebase more maintainable.

## Current State of the Code (Post-Patches)

The following flags/params now exist:
- `widget.startPlayback` - Navigation intent for explicit playback start
- `_isPreviewMode` - UI mode flag (local state)
- `isPreviewMode` param in PortraitLayout, LandscapeLayout, TextDisplayView
- `_autoScrollEnabled` - User scroll state

This is functional but fragmented. A future refactor should unify these into a proper state machine as described above.

---

## Industry Best Practices Research

### 1. Finite State Machines (FSM) for UI

The XState/Stately documentation describes finite state machines as having five parts:
- A **finite number of states**
- A **finite number of events**
- An **initial state**
- A **transition function** that determines next state given current state and event
- A (possibly empty) set of **final states**

**Key insight**: A system can only be in ONE state at a time. This prevents "impossible states" - the exact problem we have when `_isPreviewMode` and `_autoScrollEnabled` can have conflicting combinations.

### 2. BLoC Pattern (flutter_bloc)

The BLoC library emphasizes:
- **Separation of UI and business logic**: UI just sends events, doesn't know implementation
- **Event-driven state changes**: Instead of calling functions that might or might not update state, you dispatch events that always result in predictable state transitions
- **Traceability**: Every state change comes from a known event

**Key insight**: Using events makes it clear WHY state changed. In our case, we could have events like `NavigateToChapter`, `StartPlaybackFromDetails`, `TapMiniPlayer` instead of inferring intent from parameters.

### 3. Statecharts (Extended State Machines)

David Harel's statecharts add:
- **Hierarchical (nested) states**: e.g., `PlaybackScreen.Active` vs `PlaybackScreen.Preview`
- **Guards/conditions**: Transitions can have conditions (like "only if different book is playing")
- **Actions**: Entry/exit actions when entering/leaving states

**Key insight**: Our `_initializePlayback()` method is essentially implementing guards manually with if/else chains. A proper statechart would make these transitions explicit.

### 4. The Dart `state_machine` Package

Demonstrates idiomatic Dart FSM patterns:
```dart
StateMachine playback = StateMachine('playback');
State isActive = playback.newState('active');
State isPreview = playback.newState('preview');
State isLoading = playback.newState('loading');

StateTransition startPlayback = playback.newStateTransition(
  'startPlayback', 
  [isPreview, isLoading], 
  isActive
);
StateTransition enterPreview = playback.newStateTransition(
  'enterPreview',
  [isActive, isLoading],
  isPreview
);
```

**Key insight**: Legal transitions are defined up-front. Attempting illegal transitions throws exceptions. This would catch bugs like "entering preview mode from preview mode".

### 5. BlocListener for Side Effects

`flutter_bloc` recommends:
- `BlocBuilder` for UI that depends on state
- `BlocListener` for side effects (navigation, showing dialogs) that should happen ONCE per state change

**Key insight**: Our "Jump to Audio" button logic mixes concerns. Instead of checking multiple booleans in the build method, we could have a listener that shows/hides it based on state transitions.

---

## Recommended Architecture (Revised with Research)

Based on industry patterns, here's a more robust approach:

### PlaybackViewState as a Sealed Class

```dart
sealed class PlaybackViewState {}

class ActivePlayback extends PlaybackViewState {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  final bool autoScrollEnabled;
  
  // All UI decisions derived from this state
  bool get showFullControls => true;
  bool get showMiniPlayer => false;
  bool get shouldAutoSave => true;
}

class PreviewMode extends PlaybackViewState {
  final String previewBookId;
  final int previewChapterIndex;
  final String? playingBookId;  // null if nothing playing
  final int? playingChapterIndex;
  
  bool get showFullControls => false;
  bool get showMiniPlayer => playingBookId != null;
  bool get shouldAutoSave => false;
}

class LoadingPlayback extends PlaybackViewState {
  final String bookId;
  final int chapterIndex;
}
```

### Events Instead of Parameters

```dart
sealed class PlaybackEvent {}

class StartListeningPressed extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
}

class ChapterTapped extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;
}

class MiniPlayerTapped extends PlaybackEvent {}

class SegmentTapped extends PlaybackEvent {
  final int segmentIndex;
}
```

### Transition Logic (Explicit)

```dart
PlaybackViewState transition(PlaybackViewState current, PlaybackEvent event) {
  return switch ((current, event)) {
    // From anywhere, "Start Listening" starts active playback
    (_, StartListeningPressed e) => ActivePlayback(
      bookId: e.bookId,
      chapterIndex: e.chapterIndex,
      segmentIndex: e.segmentIndex,
    ),
    
    // From active, tapping different chapter enters preview
    (ActivePlayback s, ChapterTapped e) 
      when e.bookId == s.bookId && e.chapterIndex != s.chapterIndex 
      => PreviewMode(
        previewBookId: e.bookId,
        previewChapterIndex: e.chapterIndex,
        playingBookId: s.bookId,
        playingChapterIndex: s.chapterIndex,
      ),
    
    // From preview, tapping segment exits preview and starts that segment
    (PreviewMode s, SegmentTapped e) => ActivePlayback(
      bookId: s.previewBookId,
      chapterIndex: s.previewChapterIndex,
      segmentIndex: e.segmentIndex,
    ),
    
    // From preview, mini player tap returns to active
    (PreviewMode s, MiniPlayerTapped _) when s.playingBookId != null 
      => ActivePlayback(
        bookId: s.playingBookId!,
        chapterIndex: s.playingChapterIndex!,
        segmentIndex: 0, // Or restore from playback state
      ),
    
    // Invalid transitions return current state (or could throw)
    _ => current,
  };
}
```

### Benefits of This Approach

1. **Impossible states are impossible**: Can't have `autoScrollEnabled && isPreviewMode` as a bug
2. **Transitions are explicit and testable**: Unit test the transition function
3. **UI is purely derived**: No conditional logic spread across widgets
4. **Events are traceable**: Can log all events for debugging
5. **Matches Flutter/Dart ecosystem**: Uses sealed classes, pattern matching

---

## Summary

| Current State | Recommended State |
|---------------|-------------------|
| Multiple booleans (`_isPreviewMode`, `_autoScrollEnabled`, `startPlayback`) | Single sealed class hierarchy |
| Intent inferred from context (is other book playing?) | Intent explicit in events |
| Transition logic in `_initializePlayback()` if/else | Pure transition function |
| UI checks multiple conditions | UI derives from single state |
| Props drilling (`isPreviewMode` through 4 levels) | State available via provider |

The current implementation works but will continue to accumulate patches. A refactor to a proper state machine architecture would prevent future bugs and make the system easier to reason about.

