# State Machine vs Actual Code - Gap Analysis

> **Last Audit:** January 2026  
> **Status:** ⚠️ Active Issues - See Gap 7 (Provider Cache)

## Overview

This document compares the ideal state machine architecture against the current implementation of `book_details_screen.dart` and identifies gaps and issues.

---

## Book States Comparison

### Ideal State Machine
| State | Condition | UI Behavior |
|-------|-----------|-------------|
| EMPTY | Book not found | Error message |
| IMPORTED | Book loaded, 0% progress | "Start Listening", no progress bar |
| STARTED | 1-99% progress | "Continue Listening", show progress bar |
| COMPLETE | 100% complete | "Listen Again", full progress bar |

### Actual Implementation (lines 50-72)
```dart
final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
if (book == null) {
  return Center(child: Text('Book not found', ...));
}

final progress = book.progressPercent;
final hasProgress = progress > 0;
```

### ❌ Gap 1: Missing COMPLETE State
**Issue:** The code doesn't distinguish between STARTED (in-progress) and COMPLETE (100%). 
- `hasProgress = progress > 0` treats both 50% and 100% the same
- Button always says "Continue Listening" even when book is 100% complete

**Ideal Fix:**
```dart
final bookState = progress == 0 
    ? BookState.imported 
    : progress >= 100 
        ? BookState.complete 
        : BookState.started;

// Then use bookState to determine:
// - Button text: "Start" / "Continue" / "Listen Again"
// - Progress bar visibility
```

### ✅ Correct: EMPTY and IMPORTED States
- Book not found → shows "Book not found" message ✓
- Book with 0% progress → hides progress bar, shows "Start Listening" ✓

---

## Chapter States Comparison

### Ideal State Machine
| State | Badge | Status Icon | Background |
|-------|-------|-------------|------------|
| UNPLAYED | Number | Circle outline | Card color |
| PARTIAL | Number | Progress ring | Card color |
| COMPLETE | ✓ | Check circle | Card color |
| CURRENT | ▶ | Depends on listening | Primary tint |
| CACHED | ✓ | Cloud done + "Ready" | Card color |

### Actual Implementation (lines 504-700)
```dart
final isCurrentChapter = index == book.progress.chapterIndex;
final isRead = book.completedChapters.contains(index);  // Legacy!
final hasListeningProgress = segmentProgress?.hasStarted ?? false;
final isListeningComplete = segmentProgress?.isComplete ?? false;
final isSynthesizing = synthState?.status == ChapterSynthesisStatus.synthesizing;
final isSynthComplete = synthState?.status == ChapterSynthesisStatus.complete;
```

### ❌ Gap 2: Dual Completion Sources
**Issue:** Two ways to determine if chapter is complete:
1. `isRead` - from `book.completedChapters` (legacy JSON set)
2. `isListeningComplete` - from `chapterProgressMap` (SQLite DAO)

These are OR'd together: `(isRead || isListeningComplete)`

**Problem:** They can drift. If `isRead` is true but `isListeningComplete` is false, the UI shows completed but the progress bar markers might not reflect it properly.

**Recommendation:** Deprecate `book.completedChapters` and use only `chapterProgressMap` as the single source of truth.

### ✅ Correct: Current Chapter Highlighting
- `isCurrentChapter` → Primary background tint ✓
- `isCurrentChapter` → Play icon in badge ✓
- "CONTINUE HERE" chip shown ✓

### ✅ Correct: Synthesis States
- `isSynthesizing` → Progress spinner with percentage ✓
- `isSynthComplete` → Cloud icon + "Ready" text ✓

### ⚠️ Partial: Badge Logic
**Actual Code (lines 583-608):**
```dart
child: (isRead || isListeningComplete)
    ? Icon(Icons.check, ...)
    : isCurrentChapter
        ? Icon(Icons.play_arrow, ...)
        : Text('${index + 1}', ...),
```

**Issue:** Current chapter with listening complete shows checkmark, not play icon.
- If `isCurrentChapter && isListeningComplete`, shows ✓ instead of ▶

**Recommendation:** Current chapter should ALWAYS show play icon regardless of completion:
```dart
child: isCurrentChapter
    ? Icon(Icons.play_arrow, ...)
    : (isRead || isListeningComplete)
        ? Icon(Icons.check, ...)
        : Text('${index + 1}', ...),
```

---

## Status Icon Logic Comparison

### Ideal Priority Order
1. SYNTHESIZING → Spinner with progress
2. CACHED → Cloud done icon
3. COMPLETE → Check circle
4. PARTIAL → Progress ring
5. UNPLAYED → Circle outline

### Actual Code (lines 637-698)
```dart
if (isSynthesizing) { ... }
else if (isSynthComplete) { ... }
else if (isRead || isListeningComplete) { ... }
else if (hasListeningProgress) { ... }
else { Icon(Icons.circle_outlined) }
```

### ✅ Correct: Priority Order
The actual implementation follows the ideal priority order correctly.

### ❌ Gap 3: CACHED + COMPLETE Combination
**Issue:** If a chapter is both CACHED (`isSynthComplete`) AND COMPLETE (`isListeningComplete`), only the cache indicator shows.

**Ideal:** Should show both - cloud icon AND checkmark, or a combined indicator.

**Current Behavior:** Shows "Ready" cloud icon, hides completion checkmark.

---

## Progress Bar Comparison

### Ideal State Machine
| Book State | Progress Bar Visibility |
|------------|------------------------|
| IMPORTED | Hidden |
| STARTED | Visible with markers |
| COMPLETE | Visible, fully filled |

### Actual Implementation (lines 300-329)
```dart
if (hasProgress) ...[
  Row(...'Reading Progress'...),
  _buildProgressBarWithChapterMarkers(
    progress: (book.progress.chapterIndex + 1) / book.chapters.length,
    ...
  ),
]
```

### ✅ Correct: Hidden for IMPORTED State
Progress bar is hidden when `hasProgress = false` (0% progress).

### ❌ Gap 4: Progress Calculation Method
**Issue:** Progress bar uses chapter-based progress:
```dart
progress: (book.progress.chapterIndex + 1) / book.chapters.length
```

But the badge uses `book.progressPercent` which is content-weighted.

**Problem:** They can show different values. Badge might say "5%" while progress bar shows ~15% (chapter 3 of 20).

**Recommendation:** Use consistent calculation for both.

---

## CONTINUE HERE Chip Comparison

### Ideal Behavior
- Show on current chapter if NOT fully listened

### Actual Code (lines 562-578)
```dart
if (isCurrentChapter && !isListeningComplete) ...[
  Container(...'CONTINUE HERE'...)
]
```

### ✅ Correct
Chip is shown correctly for current chapter that hasn't been fully listened to.

---

## Action Button Comparison

### Ideal State Machine
| State | Button Text | Icon |
|-------|-------------|------|
| IMPORTED | "Start Listening" | play_circle_outline |
| STARTED | "Continue Listening" | play_circle_fill |
| COMPLETE | "Listen Again" | replay |

### Actual Code (lines 381-384)
```dart
icon: Icon(hasProgress ? Icons.play_circle_fill : Icons.play_circle_outline),
label: Text(hasProgress ? 'Continue Listening' : 'Start Listening'),
```

### ❌ Gap 5: Missing COMPLETE State Button
**Issue:** No "Listen Again" option for 100% completed books.

**Recommendation:**
```dart
final buttonText = switch (bookState) {
  BookState.imported => 'Start Listening',
  BookState.started => 'Continue Listening',
  BookState.complete => 'Listen Again',
};
final buttonIcon = switch (bookState) {
  BookState.imported => Icons.play_circle_outline,
  BookState.started => Icons.play_circle_fill,
  BookState.complete => Icons.replay,
};
```

---

## Summary of Gaps

| # | Gap | Severity | Fix Complexity | Status |
|---|-----|----------|----------------|--------|
| 1 | Missing COMPLETE book state | Medium | Low | ✅ FIXED (commit 57e0910) |
| 2 | Dual completion data sources | High | Medium | ✅ FIXED (commit 57e0910) |
| 3 | CACHED hides COMPLETE indicator | Low | Low | Open |
| 4 | Inconsistent progress calculation | Medium | Low | ✅ FIXED (commit 57e0910) |
| 5 | Missing "Listen Again" button | Low | Low | ✅ FIXED (commit 57e0910) |
| 6 | Current chapter badge priority | Low | Low | Open |
| 7 | Provider cache not invalidated on return from playback | Medium | Low | ✅ FIXED (Jan 2026) |

---

## Gap 7: Provider Cache Issue ✅ FIXED

### Issue
When returning from the playback screen to book details, the `bookChapterProgressProvider` is not invalidated, causing stale progress data to display.

**Symptom**: User starts listening from chapter 1 (skipping chapter 0), returns to book details, and button still shows "Start Listening" instead of "Continue Listening".

### Root Cause
The provider is only invalidated when:
- User manually marks chapters listened/unlistened via context menu

But NOT invalidated when:
- Returning from playback screen (most common case)
- Progress updates during playback

### Solution Implemented
Added `WidgetsBindingObserver` mixin to `_BookDetailsScreenState` that invalidates the provider on `AppLifecycleState.resumed`:

```dart
class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen>
    with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(bookChapterProgressProvider(widget.bookId));
    }
  }
}
```

Or use GoRouter's `onEnter` callback to refresh data when navigating back.

---

## Recommended Fixes (Priority Order)

### High Priority
1. ~~**Unify completion sources**: Remove usage of `book.completedChapters`, use only `chapterProgressMap`~~ ✅ **COMPLETED**
   - Now uses `chapterProgressMap` for all chapter completion checks
   - Progress bar counts COMPLETED chapters from this map

2. ~~**Fix provider cache invalidation (Gap 7)**: Refresh chapter progress when returning from playback~~ ✅ **COMPLETED**
   - Added `WidgetsBindingObserver` mixin to `_BookDetailsScreenState`
   - Invalidates `bookChapterProgressProvider` on `AppLifecycleState.resumed`
   - "Start Listening" vs "Continue Listening" bug is now fixed

### Medium Priority  
3. ~~**Add COMPLETE book state**: Track when all chapters are 100% listened~~ ✅ **COMPLETED**
   - Implemented `BookProgressState` enum: `notStarted`, `inProgress`, `complete`
   - Added `deriveBookProgressState()` function
4. ~~**Consistent progress**: Use same calculation for badge and progress bar~~ ✅ **COMPLETED**
   - Progress bar now counts completed chapters from `chapterProgressMap`
   - Implemented segmented progress bar showing per-chapter fill

### Low Priority
5. **Combined CACHED+COMPLETE indicator**: Show both states visually
6. ~~**"Listen Again" button**: Add for completed books~~ ✅ **COMPLETED**
7. **Badge priority fix**: Current chapter always shows play icon

---

## Code Snippets for Fixes

### Fix 1: Remove Dual Completion Sources
```dart
// Remove this line (507):
final isRead = book.completedChapters.contains(index);

// Change all (isRead || isListeningComplete) to just:
final isCompleted = chapterProgressMap[index]?.isComplete ?? false;
```

### Fix 2: Add Book State Enum
```dart
enum BookProgressState { notStarted, inProgress, complete }

BookProgressState deriveBookState(Map<int, ChapterProgress> progress, int chapterCount) {
  if (progress.isEmpty || progress.values.every((p) => !p.hasStarted)) {
    return BookProgressState.notStarted;
  }
  if (progress.length == chapterCount && progress.values.every((p) => p.isComplete)) {
    return BookProgressState.complete;
  }
  return BookProgressState.inProgress;
}
```

### Fix 3: Badge Priority
```dart
child: isCurrentChapter
    ? Icon(Icons.play_arrow, size: 16, color: colors.primaryForeground)
    : isCompleted
        ? Icon(Icons.check, size: 16, color: colors.primaryForeground)
        : Text('${index + 1}', ...),
```
