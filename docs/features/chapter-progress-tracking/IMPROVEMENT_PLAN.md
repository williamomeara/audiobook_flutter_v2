# Chapter Progress Tracking - Improvement Plan

## Status: ✅ IMPLEMENTED

**Implemented:** 2026-01-24

## Problem (Solved)

The old system determined if a chapter was "read" based solely on whether its index was less than the current chapter index:

```dart
final isRead = index < book.progress.chapterIndex;
```

**Issues (now fixed):**
1. ~~Jumping to chapter 10 marks chapters 1-9 as "read" even if they weren't listened to~~
2. ~~Jumping back to chapter 2 "un-reads" chapters 3-9~~
3. ~~No actual tracking of what was actually listened to~~

## Solution Implemented

We implemented a simplified version of **Option 2 (Completed Chapters Set)** with the following approach:

### Data Model

```dart
class Book {
  // ... existing fields
  final Set<int> completedChapters; // Chapters user completed
}
```

### Completion Triggers

A chapter is marked as complete when:
- User advances to the next chapter (manual or auto-advance)
- User long-presses a chapter to manually toggle read/unread

### Files Changed

1. **`packages/core_domain/lib/src/models/book.dart`**
   - Added `completedChapters: Set<int>` field
   - Updated `copyWith`, `toJson`, `fromJson`
   - Migration: old books get chapters before current position auto-marked as complete

2. **`lib/app/library_controller.dart`**
   - Added `markChapterComplete(bookId, chapterIndex)`
   - Added `toggleChapterComplete(bookId, chapterIndex)`

3. **`lib/ui/screens/book_details_screen.dart`**
   - `isRead` now checks `completedChapters.contains(index)`
   - Added `isInProgress` state with lighter badge color
   - Added "In Progress" label for current chapter
   - Added long-press to toggle read/unread
   - Updated `_countReadChapters` to use `completedChapters.length`

4. **`lib/ui/screens/playback_screen.dart`**
   - `_nextChapter()` marks current chapter complete before advancing
   - `_autoAdvanceToNextChapter()` marks previous chapter complete

### UI States

Three visual states for chapters:
- **Not Started**: Grey badge, no label
- **In Progress**: Semi-transparent primary badge, "In Progress" label
- **Completed**: Primary badge, "✓ Read" label

### User Interactions

- **Tap chapter**: Navigate to playback
- **Long-press chapter**: Toggle read/unread status

---

## Design Decisions

1. **When to mark a chapter as "complete":**
   - ✅ **On advancing to next chapter** (simpler and clearer to users)

2. **Manual chapter marking:**
   - ✅ **Yes** - Long-press to toggle read/unread

3. **Re-listening to completed chapters:**
   - ✅ **Keeps marked as complete** (no change on re-listen)

4. **Progress states UI:**
   - ✅ **Three states**: Not Started, In Progress, Completed

---

## Future Enhancements (Not Implemented)

- Track percentage listened per chapter
- Track times listened for analytics
- Show last listened date
- Snackbar feedback when toggling read status
