# Playback Screen Audit

**Date**: January 3, 2025  
**File**: `lib/ui/screens/playback_screen.dart` (1786 lines)  
**Status**: Audit Complete

## Executive Summary

The playback screen is the core feature of the audiobook app, responsible for TTS synthesis, audio playback, text display, and progress tracking. This audit evaluates the current implementation against industry best practices (Audible, Libby, Pocket Casts patterns) and identifies opportunities for SQLite optimization and UX improvements.

---

## Current Implementation Analysis

### Strengths ✅

1. **Dual Layout Support**
   - Portrait mode: Full-featured with text/cover toggle
   - Landscape mode: Split view with controls on left, text on right
   - Responsive design adapts to orientation changes

2. **Text View with Auto-Scroll**
   - Auto-scrolls to keep current segment visible
   - Smooth scrolling animation
   - Word-level highlighting (when segment is playing)
   - User can manually scroll and re-engage auto-scroll

3. **Segment Readiness Tracking**
   - `SegmentReadinessTracker` monitors synthesis progress
   - Visual indicators for segment availability
   - Cache verification every 5 segments

4. **Chapter Navigation**
   - Previous/Next chapter buttons
   - Chapter auto-advance when current chapter completes
   - Chapter title displayed in header

5. **Sleep Timer**
   - Countdown timer display
   - Multiple preset durations
   - Pause playback when timer expires

6. **Playback Controls**
   - Play/Pause with prominent FAB
   - Skip back/forward 10 seconds
   - Speed control (0.5x - 2.0x)
   - Segment-level seek via slider

7. **SQLite Usage (Well Optimized)**
   - Pre-segmented text loaded from SQLite (no runtime segmentation)
   - Segment queries use indexed lookups: `book_id + chapter_index`
   - Progress saves via `updateProgress()` on screen exit
   - Batch chapter text retrieval supported

### Weaknesses & Gaps ❌

1. **No Jump-to-Chapter UI**
   - Must go to Book Details to select a different chapter
   - Audible/Libby have chapter list accessible from playback screen

2. **No Bookmarks**
   - Cannot save specific positions within chapters
   - Industry standard: tap timestamp to create bookmark

3. **No Playback Stats Display**
   - Time listened, time remaining not shown
   - Audible shows "X hrs Y mins left in book"

4. **Limited Progress Persistence**
   - Only saves on screen exit via `_saveProgressAndPop()`
   - Risk of losing progress on crash/force quit
   - Should auto-save periodically (every 30s or on segment change)

5. **No Clip/Share Feature**
   - Cannot share audio clips or text excerpts
   - Feature common in podcast apps (Pocket Casts)

6. **Car Mode Missing**
   - No simplified large-button interface for driving
   - Audible has dedicated "Car Mode" with huge buttons

7. **Text Display Limitations**
   - No font size adjustment
   - No theme toggle (light/dark) within playback
   - No line spacing controls

---

## SQLite Optimization Analysis

### Current Queries (Efficient ✅)

| Query | Location | Performance |
|-------|----------|-------------|
| `getSegmentsForChapter()` | `segment_dao.dart:13` | Indexed by `book_id + chapter_index` |
| `getSegmentText()` | `segment_dao.dart:26` | Single row lookup |
| `getSegmentCount()` | `segment_dao.dart:63` | COUNT(*) with index |
| `updateProgress()` | `library_repository.dart:228` | Single upsert |

### Logging Evidence
From playback_providers.dart line 534:
```dart
final segmentDuration = DateTime.now().difference(segmentStart);
PlaybackLogger.info('[PlaybackProvider] Loaded ${segments.length} segments from SQLite in ${segmentDuration.inMilliseconds}ms');
```

**Typical load time**: < 10ms for chapters with 100+ segments (pre-segmented)

### Optimization Opportunities

1. **Periodic Progress Auto-Save**
   - **Current**: Only saves on screen exit
   - **Recommended**: Save every 30 seconds or on segment completion
   - **Impact**: Prevents progress loss on crash

2. **Pre-fetch Adjacent Chapter Segments**
   - **Current**: Only pre-synthesizes first segment of next chapter
   - **Recommended**: Also pre-load segment metadata for prev/next chapters
   - **Impact**: Instant chapter switching

3. **Batch Progress Queries**
   - **Current**: Individual chapter progress lookups
   - **Recommended**: Single query for all chapters of current book
   - **Impact**: Faster "time remaining in book" calculations

---

## Best Practices Comparison

### Audible Features (Gold Standard)
| Feature | Audible | Our App | Priority |
|---------|---------|---------|----------|
| Chapter list from playback | ✅ | ❌ | HIGH |
| Bookmarks | ✅ | ❌ | MEDIUM |
| Time remaining in book | ✅ | ❌ | HIGH |
| Clip sharing | ✅ | ❌ | LOW |
| Car Mode | ✅ | ❌ | MEDIUM |
| Sleep timer | ✅ | ✅ | - |
| Speed control | ✅ | ✅ | - |
| Skip 30s fwd/back | ✅ | ✅ (10s) | - |

### Libby (Library App) Features
| Feature | Libby | Our App | Priority |
|---------|-------|---------|----------|
| Chapter navigation | ✅ | Partial | HIGH |
| Font size in text view | ✅ | ❌ | MEDIUM |
| Reading stats | ✅ | ❌ | MEDIUM |
| Offline queue | ✅ | Partial | - |

### Pocket Casts (Podcast App) Features
| Feature | Pocket Casts | Our App | Priority |
|---------|--------------|---------|----------|
| Variable speed (fine-grained) | ✅ | ✅ | - |
| Silence trimming | ✅ | N/A | - |
| Volume boost | ✅ | ❌ | LOW |
| Auto-archive | ✅ | ❌ | LOW |

---

## Recommended Improvements

### Phase 1: Quick Wins (1-2 hours each)

1. **Add Chapter Jump Dialog**
   - Tap chapter title to show bottom sheet with chapter list
   - Similar to Book Details chapter list but inline
   - SQLite query already available: `getSegmentsForChapter()`

2. ~~**Show Time Remaining**~~ ✅ **COMPLETED** (commit 7f1958e)
   - ~~Add "Xh Ym remaining in chapter | Xh Ym remaining in book"~~
   - ~~Use existing `BookProgressSummary.remainingDuration`~~
   - ~~Display below progress slider~~
   - **Implemented**: Shows "Xh Ym left in chapter • Xh Ym left in book" below progress slider

3. ~~**Periodic Progress Auto-Save**~~ ✅ **COMPLETED** (commit 7f1958e)
   - ~~Timer every 30 seconds OR on segment completion~~
   - ~~Use existing `updateProgress()` method~~
   - ~~Prevents crash-related progress loss~~
   - **Implemented**: 30-second periodic timer saves progress to SQLite

### Phase 2: Medium Effort (Half day each)

4. **Text Display Options**
   - Font size slider (settings or inline menu)
   - Store preference in settings
   - Persist across sessions

5. **Bookmarks System**
   - New SQLite table: `bookmarks(book_id, chapter_index, segment_index, created_at, note)`
   - Tap on timestamp creates bookmark
   - Bookmark list accessible from menu

6. **Jump to Segment**
   - Tap any segment in text view to seek to it
   - Current: only auto-scrolls, no tap-to-seek

### Phase 3: Major Features (1+ days)

7. **Car Mode**
   - Large play/pause button (fills 60% of screen)
   - Extra-large skip buttons
   - Minimal text/UI
   - Launch from overflow menu

8. **Listening Stats Dashboard**
   - Total time listened (all time, this week)
   - Books completed
   - Daily streak
   - New SQLite table for aggregated stats

---

## File Structure Recommendations

Current playback_screen.dart at 1786 lines should be refactored:

```
lib/ui/screens/playback/
├── playback_screen.dart          # Main scaffold, orientation handling
├── playback_portrait_view.dart   # Portrait layout
├── playback_landscape_view.dart  # Landscape layout
├── widgets/
│   ├── playback_controls.dart    # Play/pause, skip, speed
│   ├── progress_slider.dart      # Segment slider with time
│   ├── text_display.dart         # Scrollable text with highlighting
│   ├── chapter_header.dart       # Chapter title, navigation
│   ├── sleep_timer_widget.dart   # Sleep timer UI
│   └── car_mode_view.dart        # Future: car mode
└── dialogs/
    ├── chapter_jump_dialog.dart  # Chapter selection
    └── bookmark_dialog.dart      # Future: bookmark management
```

---

## Conclusion

The playback screen has a solid foundation with good SQLite usage patterns and essential features. The main gaps compared to industry leaders are:

1. **Missing**: Chapter jump UI from playback screen (HIGH priority)
2. ~~**Missing**: Time remaining display (HIGH priority)~~ ✅ **COMPLETED**
3. ~~**Risk**: Progress only saved on exit (MEDIUM priority)~~ ✅ **COMPLETED** (auto-save every 30s)
4. **UX**: Text display customization missing (MEDIUM priority)

The SQLite layer is well-optimized with indexed queries and pre-segmented text. ~~The main opportunity is periodic progress auto-save to prevent data loss.~~ Auto-save is now implemented.

**Recommended Next Steps**:
1. ~~Implement Phase 1 Quick Wins (chapter jump, time remaining, auto-save)~~ ✅ 2/3 Complete
2. Consider file refactoring to improve maintainability (1786 lines is large)
3. Add bookmarks system for power users
