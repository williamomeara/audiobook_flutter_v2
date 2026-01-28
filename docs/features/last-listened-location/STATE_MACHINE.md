# Last Listened Location - State Machine Design

## Overview

This document defines the state machine for tracking and restoring "last listened to" locations in the audiobook app. The feature addresses two user needs:

1. **Book-level resume**: Return to exactly where the user stopped listening in a book
2. **Chapter-level resume**: Return to where the user stopped in each individual chapter (for browsing between chapters)

## Problem Statement

### Current Behavior
- `reading_progress` table stores a single `(chapter_index, segment_index)` per book
- When user navigates away and returns, the playback resumes from this stored position
- If user jumps between chapters (e.g., browsing table of contents), each jump overwrites the global progress

### Desired Behavior
1. **Primary resume point**: The main "Continue Listening" position where the user was last actively listening
2. **Per-chapter positions**: When user jumps to a different chapter to browse, remember their position in the previous chapter
3. **"Snap back" feature**: Easy way to return to the primary listening position after browsing

---

## Data Model

### Current Schema: `reading_progress`
```sql
CREATE TABLE reading_progress (
  book_id TEXT PRIMARY KEY,
  chapter_index INTEGER NOT NULL DEFAULT 0,
  segment_index INTEGER NOT NULL DEFAULT 0,
  last_played_at INTEGER,
  total_listen_time_ms INTEGER DEFAULT 0,
  updated_at INTEGER NOT NULL
);
```

### Proposed Addition: `chapter_positions`
```sql
CREATE TABLE chapter_positions (
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  is_primary BOOLEAN NOT NULL DEFAULT 0,  -- The main listening position
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(book_id, chapter_index)
);

-- Index for quick primary position lookup
CREATE INDEX idx_chapter_positions_primary 
  ON chapter_positions(book_id, is_primary) 
  WHERE is_primary = 1;
```

### Alternative: Extend `reading_progress` (Simpler)
```sql
ALTER TABLE reading_progress ADD COLUMN primary_chapter_index INTEGER;
ALTER TABLE reading_progress ADD COLUMN primary_segment_index INTEGER;
```
- Stores the "snap back" position alongside current browsing position
- Simpler but less flexible

---

## State Definitions

### BookListeningState
```dart
enum BookListeningState {
  /// Book has never been played
  notStarted,
  
  /// User is actively listening (in playback screen)
  activelyListening,
  
  /// User has paused but remains in playback screen
  paused,
  
  /// User navigated away from playback screen
  suspended,
  
  /// User is browsing chapters (jumped to different chapter)
  browsing,
  
  /// Book completed (all chapters listened)
  completed,
}
```

### ChapterPosition (Per-Chapter State)
```dart
class ChapterPosition {
  final int chapterIndex;
  final int segmentIndex;
  final DateTime lastVisited;
  final bool isPrimary;  // Is this the main listening position?
  
  const ChapterPosition({
    required this.chapterIndex,
    required this.segmentIndex,
    required this.lastVisited,
    this.isPrimary = false,
  });
}
```

### ListeningContext (Active State)
```dart
class ListeningContext {
  /// Current playback position
  final int currentChapter;
  final int currentSegment;
  
  /// Primary listening position (snap-back target)
  final int? primaryChapter;
  final int? primarySegment;
  
  /// Whether user is browsing (jumped from primary)
  final bool isBrowsing;
  
  /// Per-chapter positions for all visited chapters
  final Map<int, ChapterPosition> chapterPositions;
}
```

---

## State Transitions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        BOOK LISTENING STATE MACHINE                          │
└──────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │  notStarted │
                    └──────┬──────┘
                           │
                           │ [USER: Start Listening]
                           ▼
                    ┌─────────────────┐
          ┌────────│ activelyListening│◄────────────┐
          │        └────────┬────────┘              │
          │                 │                        │
          │ [USER: Pause]   │ [USER: Jump Chapter]  │ [USER: Resume]
          │                 │                        │
          ▼                 ▼                        │
    ┌──────────┐     ┌───────────┐                  │
    │  paused  │     │  browsing │──────────────────┘
    └────┬─────┘     └─────┬─────┘
         │                 │
         │ [USER: Exit]    │ [USER: Exit / Snap Back]
         │                 │
         ▼                 ▼
    ┌──────────────────────────┐
    │       suspended          │
    └──────────────────────────┘
         │
         │ [ALL CHAPTERS COMPLETE]
         ▼
    ┌──────────────────────────┐
    │       completed          │
    └──────────────────────────┘
```

---

## Trigger Events & Actions

### Event: Start Listening (from Book Details)
```dart
// Trigger: User taps "Start Listening" or "Continue Listening"
// Context: bookId, targetChapter (optional)

Action startListening(String bookId, {int? targetChapter}) {
  final existingProgress = await progressDao.getProgress(bookId);
  
  if (existingProgress == null) {
    // Fresh start - chapter 0, segment 0
    return NavigateToPlayback(
      bookId: bookId,
      chapterIndex: 0,
      segmentIndex: 0,
      setPrimary: true,
    );
  }
  
  // Resume from last position
  return NavigateToPlayback(
    bookId: bookId,
    chapterIndex: existingProgress.chapterIndex,
    segmentIndex: existingProgress.segmentIndex,
    setPrimary: true,
  );
}
```

### Event: Jump to Chapter (from Chapter List)
```dart
// Trigger: User taps a chapter in the list while playback is active
// Context: bookId, currentChapter, targetChapter

Action jumpToChapter(
  String bookId, 
  int currentChapter, 
  int currentSegment,
  int targetChapter,
) {
  // Save current position as chapter position
  await positionDao.saveChapterPosition(
    bookId: bookId,
    chapterIndex: currentChapter,
    segmentIndex: currentSegment,
    isPrimary: true,  // Mark as primary listening position
  );
  
  // Check if target chapter has a previous position
  final existingPosition = await positionDao.getChapterPosition(
    bookId, 
    targetChapter,
  );
  
  if (existingPosition != null) {
    // Resume from where they left off in this chapter
    return JumpToPosition(
      chapterIndex: targetChapter,
      segmentIndex: existingPosition.segmentIndex,
      enterBrowsingMode: true,
    );
  }
  
  // Start from beginning of chapter
  return JumpToPosition(
    chapterIndex: targetChapter,
    segmentIndex: 0,
    enterBrowsingMode: true,
  );
}
```

### Event: Snap Back to Primary Position
```dart
// Trigger: User taps "Back to where I was" button (while browsing)
// Context: bookId

Action snapBackToPrimary(String bookId) {
  final primaryPosition = await positionDao.getPrimaryPosition(bookId);
  
  if (primaryPosition == null) {
    // No primary position - stay where you are
    return NoOp();
  }
  
  return JumpToPosition(
    chapterIndex: primaryPosition.chapterIndex,
    segmentIndex: primaryPosition.segmentIndex,
    enterBrowsingMode: false,  // Exit browsing mode
  );
}
```

### Event: Continue Listening in Browsed Chapter
```dart
// Trigger: User continues listening in browsed chapter for > 30 seconds
// Context: bookId, browsedChapter, currentSegment

Action promoteBrowsingToPrimary(
  String bookId, 
  int browsedChapter, 
  int currentSegment,
) {
  // Clear old primary flag
  await positionDao.clearPrimaryFlag(bookId);
  
  // Set new primary to current position
  await positionDao.saveChapterPosition(
    bookId: bookId,
    chapterIndex: browsedChapter,
    segmentIndex: currentSegment,
    isPrimary: true,
  );
  
  return ExitBrowsingMode();
}
```

### Event: Exit Playback Screen
```dart
// Trigger: User navigates back from playback screen
// Context: bookId, currentChapter, currentSegment, isBrowsing

Action exitPlayback(
  String bookId,
  int currentChapter,
  int currentSegment,
  bool isBrowsing,
) {
  // Always save current chapter position
  await positionDao.saveChapterPosition(
    bookId: bookId,
    chapterIndex: currentChapter,
    segmentIndex: currentSegment,
    isPrimary: !isBrowsing,  // Only primary if not browsing
  );
  
  // Update main reading progress
  await progressDao.updatePosition(bookId, currentChapter, currentSegment);
  
  return NavigateToBookDetails(bookId);
}
```

---

## UI Integration: Leveraging Existing "Resume Auto-Scroll" Button

### Current Implementation

The playback screen already has a "Jump to Audio" button (in `text_display.dart`) that:
- Appears when user scrolls away from current segment
- Re-enables auto-scroll and jumps to current segment
- Uses `Icons.my_location` icon

### Extended Behavior for Cross-Chapter Navigation

We can leverage this same button for the "snap back" feature:

1. **Same Chapter** (current behavior):
   - Button appears when auto-scroll is disabled
   - Tapping scrolls to current segment within chapter

2. **Different Chapter** (new behavior):
   - Button appears when viewing a chapter different from primary listening position
   - Label changes to "Back to Chapter X"
   - Tapping loads the primary chapter and scrolls to position

### Implementation Approach

```dart
// In _JumpToCurrentButton, check if we're in a different chapter
Widget build(BuildContext context) {
  final isBrowsingDifferentChapter = ref.watch(browsingModeProvider(bookId));
  final primaryPosition = ref.watch(primaryPositionProvider(bookId));
  
  // Determine button text and action
  final String label;
  final VoidCallback onTap;
  
  if (isBrowsingDifferentChapter && primaryPosition.valueOrNull != null) {
    // Cross-chapter snap-back
    final primary = primaryPosition.value!;
    label = 'Back to Ch.${primary.chapterIndex + 1}';
    onTap = () => ref.read(listeningActionsProvider.notifier)
        .snapBackToPrimary(bookId);
  } else {
    // Same-chapter scroll (existing behavior)
    label = 'Jump to Audio';
    onTap = widget.onJumpToCurrent;
  }
  
  // ... rest of button UI
}
```

### Unified Button Behavior

| State | Button Label | Action |
|-------|-------------|--------|
| Same chapter, scrolled away | "Jump to Audio" | Scroll to current segment |
| Different chapter (browsing) | "Back to Ch.X" | Load primary chapter, scroll to position |
| Primary chapter, auto-scroll on | (hidden) | N/A |

---

## UI State Mapping

### Book Details Screen

| Listening State | Action Button | Chapter List Badge |
|----------------|---------------|-------------------|
| `notStarted` | "Start Listening" | (none) |
| `suspended` (has progress) | "Continue Listening" | Primary chapter has ▶ badge |
| `suspended` (browsing) | "Continue at [Primary]" | Primary chapter has 🎯, current has ▶ |
| `completed` | "Listen Again" | All chapters have ✓ |

### Playback Screen (when browsing different chapter)

```
┌─────────────────────────────────────────────────┐
│  ◄  Chapter 5: The Discovery                    │
│                                                  │
│  "The forest opened up before them..."          │
│                                                  │
│  ▶ │ 0:45 ━━━━━━━━━━○─────────── 4:20          │
│                                                  │
│        [Previous] [Play/Pause] [Next]           │
│                                                  │
│         ┌────────────────────────────┐          │
│         │ 🎯 Back to Ch.3            │          │  ← Extended "Resume" button
│         └────────────────────────────┘          │
└─────────────────────────────────────────────────┘
```

### Chapter List (within Playback)

```
┌─────────────────────────────────────────────────┐
│  Chapters                                        │
├─────────────────────────────────────────────────┤
│  1. Introduction                    ✓           │
│  2. The Beginning                   ✓           │
│  3. The Journey                     🎯 ← Primary│  ← Shows timestamp "2:34"
│  4. The Challenge                   ○           │
│  5. The Discovery                   ▶ ← Current │  ← Currently browsing
│  6. The Return                      ○           │
└─────────────────────────────────────────────────┘
```

---

## Provider Architecture

### State Providers
```dart
/// Tracks whether user is currently in "browsing mode"
final browsingModeProvider = StateProvider.family<bool, String>(
  (ref, bookId) => false,
);

/// Primary listening position (snap-back target)
final primaryPositionProvider = FutureProvider.family<ChapterPosition?, String>(
  (ref, bookId) async {
    final dao = ref.read(chapterPositionDaoProvider);
    return dao.getPrimaryPosition(bookId);
  },
);

/// All chapter positions for a book
final chapterPositionsProvider = FutureProvider.family<Map<int, ChapterPosition>, String>(
  (ref, bookId) async {
    final dao = ref.read(chapterPositionDaoProvider);
    return dao.getAllPositions(bookId);
  },
);

/// Combined listening context for playback screen
final listeningContextProvider = Provider.family<ListeningContext, String>(
  (ref, bookId) {
    final playbackState = ref.watch(playbackStateProvider);
    final isBrowsing = ref.watch(browsingModeProvider(bookId));
    final primaryPosition = ref.watch(primaryPositionProvider(bookId));
    final chapterPositions = ref.watch(chapterPositionsProvider(bookId));
    
    return ListeningContext(
      currentChapter: playbackState.currentChapter,
      currentSegment: playbackState.currentIndex,
      primaryChapter: primaryPosition.valueOrNull?.chapterIndex,
      primarySegment: primaryPosition.valueOrNull?.segmentIndex,
      isBrowsing: isBrowsing,
      chapterPositions: chapterPositions.valueOrNull ?? {},
    );
  },
);
```

### Actions Notifier
```dart
class ListeningActionsNotifier extends Notifier<void> {
  @override
  void build() {}
  
  /// Jump to a different chapter, saving current position
  Future<void> jumpToChapter(String bookId, int targetChapter) async {
    final playbackState = ref.read(playbackStateProvider);
    final currentChapter = playbackState.currentChapter;
    final currentSegment = playbackState.currentIndex;
    
    // Save current position as primary (first jump) or position (subsequent)
    final isBrowsing = ref.read(browsingModeProvider(bookId));
    final dao = ref.read(chapterPositionDaoProvider);
    
    if (!isBrowsing) {
      // First jump - save as primary
      await dao.saveChapterPosition(
        bookId: bookId,
        chapterIndex: currentChapter,
        segmentIndex: currentSegment,
        isPrimary: true,
      );
      ref.read(browsingModeProvider(bookId).notifier).state = true;
    } else {
      // Already browsing - just save position
      await dao.saveChapterPosition(
        bookId: bookId,
        chapterIndex: currentChapter,
        segmentIndex: currentSegment,
        isPrimary: false,
      );
    }
    
    // Check for existing position in target chapter
    final targetPosition = await dao.getChapterPosition(bookId, targetChapter);
    final targetSegment = targetPosition?.segmentIndex ?? 0;
    
    // Navigate to target chapter
    ref.read(playbackControllerProvider.notifier).jumpToChapter(
      targetChapter,
      segmentIndex: targetSegment,
    );
  }
  
  /// Snap back to primary listening position
  Future<void> snapBackToPrimary(String bookId) async {
    final dao = ref.read(chapterPositionDaoProvider);
    final primary = await dao.getPrimaryPosition(bookId);
    
    if (primary == null) return;
    
    // Navigate to primary position
    ref.read(playbackControllerProvider.notifier).jumpToChapter(
      primary.chapterIndex,
      segmentIndex: primary.segmentIndex,
    );
    
    // Exit browsing mode
    ref.read(browsingModeProvider(bookId).notifier).state = false;
  }
  
  /// Promote current browsing position to primary (user committed to new location)
  Future<void> commitCurrentPosition(String bookId) async {
    final playbackState = ref.read(playbackStateProvider);
    final dao = ref.read(chapterPositionDaoProvider);
    
    // Clear old primary
    await dao.clearPrimaryFlag(bookId);
    
    // Set current as primary
    await dao.saveChapterPosition(
      bookId: bookId,
      chapterIndex: playbackState.currentChapter,
      segmentIndex: playbackState.currentIndex,
      isPrimary: true,
    );
    
    // Exit browsing mode
    ref.read(browsingModeProvider(bookId).notifier).state = false;
  }
}
```

---

## Migration Plan

### Phase 1: Database Schema
1. Create `chapter_positions` table in migration_v4.dart
2. Create `ChapterPositionDao` with CRUD operations
3. Add provider for accessing positions

### Phase 2: Playback Screen Integration
1. Track browsing mode state
2. Show "snap back" button when browsing
3. Auto-promote after 30 seconds of continuous listening

### Phase 3: Book Details Integration
1. Show primary position indicator on chapter list
2. Update "Continue Listening" to respect primary position
3. Invalidate providers on resume (already done in Gap 7 fix)

### Phase 4: UI Polish
1. Add animations for snap-back
2. Show timestamp on snap-back button
3. Add settings for auto-promote duration

---

## Testing Scenarios

### Scenario 1: Simple Resume
1. User opens book, starts listening at Chapter 1, Segment 5
2. User pauses, exits playback
3. User returns later → "Continue Listening" takes them to Chapter 1, Segment 5

### Scenario 2: Chapter Browse with Snap Back
1. User is listening at Chapter 3, Segment 20
2. User opens chapter list, taps Chapter 7
3. System saves Chapter 3:20 as primary, enters browsing mode
4. User listens to Chapter 7:0 for a few seconds
5. User taps "Back to Chapter 3 (timestamp)" → jumps back to Chapter 3:20

### Scenario 3: Commit to New Position
1. User is listening at Chapter 3, Segment 20
2. User jumps to Chapter 5 (browsing mode)
3. User listens to Chapter 5 for 30+ seconds
4. System auto-promotes Chapter 5 to primary, exits browsing mode
5. User exits playback → "Continue Listening" shows Chapter 5 position

### Scenario 4: Multiple Chapter Browse
1. User at Chapter 3:20 (primary)
2. User jumps to Chapter 5 → saves position for Ch5
3. User jumps to Chapter 8 → saves position for Ch5, Ch8
4. User snaps back → returns to Chapter 3:20
5. User later browses to Chapter 5 → resumes at previous position within Ch5

---

## Implementation Priority

1. **High**: Database schema + DAO (foundation)
2. **High**: Primary position tracking (core feature)
3. **Medium**: Browsing mode detection + snap-back UI
4. **Medium**: Per-chapter position persistence
5. **Low**: Auto-promotion after listening duration
6. **Low**: UI polish and animations
