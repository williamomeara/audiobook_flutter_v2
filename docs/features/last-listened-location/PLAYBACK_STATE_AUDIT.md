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
