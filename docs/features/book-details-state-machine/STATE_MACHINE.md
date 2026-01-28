# Book Details Page - State Machine Architecture

> **Last Audit:** January 2026  
> **Status:** ⚠️ Partial - Core state machine implemented, provider caching issue identified

## Implementation Status: ✅ PARTIALLY IMPLEMENTED (commit 57e0910)

**Completed:**
- `BookProgressState` enum: `notStarted`, `inProgress`, `complete`
- `deriveBookProgressState()` function
- Segmented progress bar showing per-chapter completion
- Unified completion source (uses `chapterProgressMap` only)
- "Listen Again" button for completed books

**Remaining:**
- Full unified state model (BookDetailsState)
- Combined CACHED+COMPLETE indicator
- Current chapter badge priority fix
- **Provider cache invalidation on return from playback** (see Gap 7 in GAP_ANALYSIS.md)

---

## Known Issue: "Start Listening" vs "Continue Listening" (Jan 2026)

**Symptom**: Button shows "Start Listening" even when user has listening progress (e.g., skipped first chapter).

**Cause**: `bookChapterProgressProvider` is not invalidated when returning from playback screen. The provider returns cached data showing no progress, causing `deriveBookProgressState()` to return `notStarted`.

**Impact**: Users see incorrect button text until the cache naturally refreshes or they force-reload.

**Workaround**: Navigate away and back, or restart the app.

**Fix**: Add provider invalidation on screen focus/GoRouter navigation. See GAP_ANALYSIS.md Gap 7.

---

## Overview

This document defines an ideal state machine architecture for the Book Details page, ensuring consistent UI states, clear transitions, and proper data flow.

---

## Book State Machine

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BOOK STATES                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────┐      ┌───────────┐      ┌────────────┐      ┌─────────┐ │
│   │  EMPTY   │──────│  IMPORTED │──────│  STARTED   │──────│ COMPLETE│ │
│   └──────────┘      └───────────┘      └────────────┘      └─────────┘ │
│        │                  │                   │                  │      │
│        │                  │                   │                  │      │
│  No book loaded     Book parsed        First segment       All chapters │
│                     Chapters ready     listened            listened     │
│                     0% progress        1-99% progress      100%         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### State Definitions

| State | Condition | UI Behavior |
|-------|-----------|-------------|
| **EMPTY** | Book not found or loading failed | Show error message |
| **IMPORTED** | Book loaded, 0 chapters listened | "Start Listening" button, no progress bar |
| **STARTED** | At least 1 segment listened | "Continue Listening" button, show progress bar |
| **COMPLETE** | All chapters 100% listened | "Listen Again" button, full progress bar |

---

## Chapter State Machine (Per Chapter)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CHAPTER STATES                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────┐      ┌────────────┐      ┌──────────┐      ┌──────────┐ │
│   │ UNPLAYED │──────│  PARTIAL   │──────│ COMPLETE │──────│  CACHED  │ │
│   └──────────┘      └────────────┘      └──────────┘      └──────────┘ │
│        │                  │                   │                  │      │
│   No segments        Some segments       All segments      Chapter audio│
│   listened           listened            listened          pre-synth'd  │
│                                                                          │
│   Badge: number      Badge: partial      Badge: ✓         Badge: ✓+☁️   │
│                      progress ring                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Chapter State Transitions

```dart
enum ChapterState {
  unplayed,   // percentComplete == 0
  partial,    // 0 < percentComplete < 1.0
  complete,   // percentComplete >= 1.0 OR manuallyMarked
  cached,     // complete AND synthStatus == complete
}

ChapterState deriveChapterState(ChapterProgress? progress, ChapterSynthesisState? synth) {
  final isComplete = progress?.isComplete ?? false;
  final isCached = synth?.status == ChapterSynthesisStatus.complete;
  
  if (isCached && isComplete) return ChapterState.cached;
  if (isComplete) return ChapterState.complete;
  if (progress?.hasStarted ?? false) return ChapterState.partial;
  return ChapterState.unplayed;
}
```

---

## UI Component State Matrix

### Progress Section States

| Book State | Progress Badge | Progress Bar | Progress Label |
|------------|----------------|--------------|----------------|
| IMPORTED | Hidden | Hidden | Hidden |
| STARTED | Show % | Show with markers | "Chapter X of Y" |
| COMPLETE | Show 100% | Full bar, all markers filled | "Complete" |

### Chapter Card States

| Chapter State | Badge | Border | Background | Status Icon |
|---------------|-------|--------|------------|-------------|
| **Current + Unplayed** | ▶ (play) | Primary border | Primary tint | Circle outline |
| **Current + Partial** | ▶ (play) | Primary border | Primary tint | Progress ring |
| **Unplayed** | Number | Gray border | Card color | Circle outline |
| **Partial** | Number | None | Card color | Progress ring X% |
| **Complete** | ✓ | None | Card color | Check circle |
| **Cached** | ✓ | None | Card color | Cloud check + "Ready" |

### Action Button States

| Book State | Button Text | Icon | Action |
|------------|-------------|------|--------|
| IMPORTED (notStarted) | "Start Listening" | play_circle_outline | Navigate to `/playback/{bookId}` |
| STARTED (inProgress) | "Continue Listening" | play_circle_fill | Navigate to `/playback/{bookId}` |
| COMPLETE | "Listen Again" | replay | Navigate to `/playback/{bookId}` |

> **Note**: All states navigate to the same route. The playback screen handles
> resuming from the correct position based on saved progress in the database.

---

## Synthesis State Machine (Per Chapter)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SYNTHESIS STATES                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────┐      ┌────────────┐      ┌──────────┐      ┌──────────┐ │
│   │   IDLE   │──────│ PREPARING  │──────│ COMPLETE │      │  FAILED  │ │
│   └──────────┘      └────────────┘      └──────────┘      └──────────┘ │
│        │                  │                   │                  │      │
│   Not cached         Synthesizing        Audio ready       Error state  │
│                      Show progress                                       │
│                                                                          │
│   Menu: "Prepare"    Menu: "Cancel"     Menu: "Clear"    Menu: "Retry" │
│                                          + cached badge                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Unified State Model (Proposed)

```dart
/// Unified state for the Book Details page
class BookDetailsState {
  final BookLoadState loadState;
  final Book? book;
  final BookProgressState progressState;
  final Map<int, ChapterDisplayState> chapters;
  final String? error;
}

enum BookLoadState {
  loading,
  loaded,
  error,
  notFound,
}

enum BookProgressState {
  notStarted,  // 0% progress
  inProgress,  // 1-99% progress
  complete,    // 100% progress
}

/// Everything needed to display a chapter card
class ChapterDisplayState {
  final int index;
  final String title;
  final ChapterState listeningState;
  final SynthesisState synthesisState;
  final bool isCurrent;
  final double percentListened;
  final Duration? duration;
  final double synthProgress;
  
  /// Derived display properties
  bool get showProgressRing => listeningState == ChapterState.partial;
  bool get showCheckmark => listeningState == ChapterState.complete || listeningState == ChapterState.cached;
  bool get showCacheIndicator => synthesisState == SynthesisState.complete;
  bool get showSynthProgress => synthesisState == SynthesisState.preparing;
}

enum ChapterState { unplayed, partial, complete, cached }
enum SynthesisState { idle, preparing, complete, failed }
```

---

## State Derivation Logic

```dart
/// Derive book progress state from chapter progress data.
/// 
/// NOTE: The actual implementation in book_details_screen.dart uses
/// Map<int, ChapterProgress?> (nullable values) and handles nulls properly.
BookProgressState deriveBookProgressState(
  Map<int, ChapterProgress?> chapterProgress,
  int totalChapters,
) {
  if (totalChapters == 0) return BookProgressState.notStarted;
  
  // Check if any chapter has been started
  final anyStarted = chapterProgress.values.any((p) => p?.hasStarted ?? false);
  if (!anyStarted) return BookProgressState.notStarted;
  
  // Check if all chapters are complete
  // Must iterate by index to ensure ALL chapters are checked, not just those in map
  int completeCount = 0;
  for (int i = 0; i < totalChapters; i++) {
    if (chapterProgress[i]?.isComplete ?? false) {
      completeCount++;
    }
  }
  
  if (completeCount == totalChapters) return BookProgressState.complete;
  
  return BookProgressState.inProgress;
}

/// Should progress bar be shown?
bool shouldShowProgressBar(BookProgressState state) {
  return state != BookProgressState.notStarted;
}

/// Progress bar value (0.0 - 1.0)
double calculateProgressBarValue(int currentChapterIndex, int totalChapters) {
  return (currentChapterIndex + 1) / totalChapters.clamp(1, double.infinity);
}
```

---

## Recommended Implementation Changes

### 1. Create BookDetailsNotifier

Replace the current inline logic with a dedicated notifier:

```dart
@riverpod
class BookDetailsNotifier extends _$BookDetailsNotifier {
  @override
  Future<BookDetailsState> build(String bookId) async {
    final library = await ref.watch(libraryProvider.future);
    final book = library.books.where((b) => b.id == bookId).firstOrNull;
    
    if (book == null) {
      return BookDetailsState(
        loadState: BookLoadState.notFound,
        book: null,
        progressState: BookProgressState.notStarted,
        chapters: {},
      );
    }
    
    final chapterProgress = await ref.watch(bookChapterProgressProvider(bookId).future);
    final synthStates = ref.watch(chapterSynthesisProvider);
    
    return BookDetailsState(
      loadState: BookLoadState.loaded,
      book: book,
      progressState: deriveBookProgressState(chapterProgress, book.chapters.length),
      chapters: _buildChapterStates(book, chapterProgress, synthStates),
    );
  }
}
```

### 2. Simplify UI with State-Driven Rendering

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(bookDetailsNotifierProvider(bookId));
  
  return state.when(
    loading: () => LoadingScreen(),
    error: (e, _) => ErrorScreen(error: e),
    data: (details) => switch (details.loadState) {
      BookLoadState.notFound => NotFoundScreen(),
      BookLoadState.error => ErrorScreen(error: details.error),
      _ => _buildBookDetails(details),
    },
  );
}

Widget _buildBookDetails(BookDetailsState state) {
  return Column(
    children: [
      _buildHeader(state.book!),
      if (state.progressState != BookProgressState.notStarted)
        _buildProgressSection(state),
      _buildActionButton(state.progressState),
      _buildChapterList(state.chapters),
    ],
  );
}
```

---

## State Transition Events

| Event | From State | To State | Side Effects |
|-------|------------|----------|--------------|
| `bookLoaded` | EMPTY → IMPORTED | None | Load chapter progress |
| `segmentPlayed` | IMPORTED → STARTED | Update segment_progress DB |
| `chapterCompleted` | STARTED (any) | Update progress, check if all complete |
| `allChaptersComplete` | STARTED → COMPLETE | None |
| `markedAsListened` | Any → COMPLETE | Bulk update segment_progress |
| `markedAsUnlistened` | Any → UNPLAYED | Clear segment_progress |
| `synthesisStarted` | IDLE → PREPARING | Start background synthesis |
| `synthesisCancelled` | PREPARING → IDLE | Stop synthesis |
| `synthesisComplete` | PREPARING → COMPLETE | Show notification |

---

## Benefits of This Architecture

1. **Single Source of Truth**: All UI state derived from one place
2. **Testable**: State transitions can be unit tested
3. **Predictable**: Clear state machine prevents impossible states
4. **Debuggable**: Can log state transitions for debugging
5. **Maintainable**: Adding new states/features is straightforward

---

## Migration Path

> **Note**: Steps 1-3 partially completed in commit 57e0910

1. ~~Create `BookDetailsState` and `ChapterDisplayState` models~~ ✅ Created `BookProgressState` enum
2. ~~Create `BookDetailsNotifier` with state derivation logic~~ ✅ Created `deriveBookProgressState()`
3. ~~Gradually migrate UI components to use derived state~~ ✅ Progress bar and button use state
4. Remove inline state calculation from build method (ongoing)
5. Add state transition logging for debugging
