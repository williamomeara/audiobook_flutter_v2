# Last Listened Location - Gap Analysis

## Current Implementation Analysis

### How Progress is Currently Tracked

#### 1. Global Book Progress (`reading_progress` table)
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

**Current Behavior:**
- Single position per book (chapter + segment)
- Updated every 30 seconds during playback (`_autoSaveProgress()`)
- Updated when exiting playback screen (`_saveProgressAndPop()`)
- Updated when navigating chapters (`_nextChapter()`, `_previousChapter()`)

#### 2. Segment-Level Progress (`segment_progress` table)
```sql
CREATE TABLE segment_progress (
  book_id TEXT,
  chapter_index INTEGER,
  segment_index INTEGER,
  listened_at INTEGER,
  PRIMARY KEY(book_id, chapter_index, segment_index)
);
```

**Current Behavior:**
- Marks individual segments as listened
- Used for chapter completion percentage
- NOT used for resume position

### Current Chapter Navigation

#### In `playback_screen.dart`:

1. **Next Chapter (`_nextChapter()`, lines 460-494)**
   - Marks current chapter complete
   - Sets `_currentChapterIndex = newChapterIndex`
   - Calls `loadChapter()` at segment 0
   - ❌ Does NOT save current segment position before switching

2. **Previous Chapter (`_previousChapter()`, lines 496-524)**
   - Sets `_currentChapterIndex = newChapterIndex`
   - Calls `loadChapter()` at segment 0
   - ❌ Does NOT save current segment position before switching

3. **Auto-Advance (`_autoAdvanceToNextChapter()`, lines 320-329)**
   - Only called when chapter ends naturally
   - ✅ Current chapter is marked complete before advance

4. **Initial Load (`_initializePlayback()`, lines 380-435)**
   - Loads book's saved progress (chapter + segment)
   - Resumes from saved position

### What's Missing

| Feature | Status | Notes |
|---------|--------|-------|
| Single resume position per book | ✅ Exists | `reading_progress` table |
| Resume at exact segment | ✅ Exists | `segment_index` column |
| Per-chapter positions | ❌ Missing | Need `chapter_positions` table |
| Browsing mode detection | ❌ Missing | Need state tracking |
| Snap-back to primary | ❌ Missing | Need UI + logic |
| Save position before chapter jump | ❌ Missing | Position lost on chapter switch |

---

## Gap Details

### Gap 1: Position Lost on Manual Chapter Switch

**Problem:**
When user taps Next/Previous chapter, the current segment position is lost.

**Example:**
1. User at Chapter 3, Segment 45
2. User taps "Previous Chapter" to check something in Chapter 2
3. System loads Chapter 2 at Segment 0
4. User's position (Chapter 3:45) is overwritten by auto-save

**Current Code (line 513):**
```dart
setState(() => _currentChapterIndex = newChapterIndex);
await ref.read(playbackControllerProvider.notifier).loadChapter(
  book: book,
  chapterIndex: newChapterIndex,
  startSegmentIndex: 0,  // ← Always starts at 0!
  autoPlay: ref.read(playbackStateProvider).isPlaying,
);
```

**Fix Required:**
- Save current position before chapter switch
- Store in `chapter_positions` table
- Check for existing position when loading chapter

---

### Gap 2: No "Snap Back" Mechanism

**Problem:**
After browsing to a different chapter, no easy way to return to previous position.

**User Story:**
> "I was at Chapter 5, but wanted to check a character name in Chapter 2. Now I have to remember I was at Chapter 5 and manually navigate back."

**Fix Required:**
- Track "primary" listening position (where user was actively listening)
- Show "Back to Chapter X" button when browsing
- Implement `snapBackToPrimary()` action

---

### Gap 3: No Per-Chapter Resume Points

**Problem:**
When revisiting a chapter, always starts from beginning (segment 0).

**Example:**
1. User listens to Chapter 3 up to segment 45, then advances to Chapter 4
2. User later returns to Chapter 3
3. Chapter 3 starts from segment 0, not segment 45

**Current Code (line 325):**
```dart
await ref.read(playbackControllerProvider.notifier).loadChapter(
  book: book,
  chapterIndex: newChapterIndex,
  startSegmentIndex: 0,  // ← Always 0
  autoPlay: true,
);
```

**Fix Required:**
- Store last segment position for each visited chapter
- Retrieve position when loading a chapter
- Default to segment 0 only if no position exists

---

### Gap 4: No Browsing vs Listening Distinction

**Problem:**
System can't tell if user is:
- Actively listening (should update primary position)
- Just browsing (should keep primary position, allow snap-back)

**Fix Required:**
- Add `browsingModeProvider` state
- Enter browsing mode on manual chapter jump
- Exit browsing mode after ~30 seconds of listening OR on explicit snap-back

---

## Integration Points

### Files That Need Changes

1. **`lib/app/database/migrations/migration_v4.dart`** (NEW)
   - Create `chapter_positions` table

2. **`lib/app/database/daos/chapter_position_dao.dart`** (NEW)
   - CRUD operations for positions

3. **`lib/app/playback_providers.dart`**
   - Add `browsingModeProvider`
   - Add `primaryPositionProvider`
   - Add `chapterPositionsProvider`

4. **`lib/app/listening_actions_notifier.dart`** (NEW)
   - `jumpToChapter()` with position saving
   - `snapBackToPrimary()`
   - `commitCurrentPosition()`

5. **`lib/ui/screens/playback_screen.dart`**
   - Update `_nextChapter()` to save position first
   - Update `_previousChapter()` to save position first
   - Add snap-back button when browsing
   - Add auto-promotion timer

6. **`lib/ui/screens/book_details_screen.dart`**
   - Update chapter list to show primary position indicator
   - Update "Continue Listening" to use primary position

---

## Summary

| Priority | Gap | Complexity | Impact |
|----------|-----|------------|--------|
| High | Save position before chapter switch | Low | High - prevents data loss |
| High | Per-chapter positions | Medium | High - enables resume in chapters |
| Medium | Browsing mode detection | Low | Medium - better UX |
| Medium | Snap-back button | Medium | High - key user request |
| Low | Auto-promotion | Low | Nice-to-have |
| Low | Primary position badge | Low | Visual polish |
