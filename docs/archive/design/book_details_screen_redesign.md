# Book Details Screen - Design Audit & Recommendations

**Date:** June 2026  
**Author:** AI Design Audit  
**File:** `lib/ui/screens/book_details_screen.dart`

---

## Executive Summary

The current Book Details screen provides essential functionality but has several UX/UI gaps that hinder discoverability of listening progress. This document audits the current implementation and proposes improvements based on Material Design guidelines, iOS Human Interface Guidelines, and patterns from leading audiobook apps (Audible, Libby, Apple Books).

### Key Issues Identified

1. **No visible indication of chapter read/unread status at a glance** - Users must interpret progress percentages
2. **Progress information scattered** - Overall progress, chapter progress, and segment progress use different visual languages
3. **Missing listening stats** - No "time listened" or "time remaining" metrics visible
4. **Chapter list density** - Long books (50+ chapters) are cumbersome to navigate
5. **No chapter search/jump** - Users cannot quickly navigate to specific chapters

---

## Current Implementation Analysis

### What Exists (✅ Working Well)

| Feature | Location | Notes |
|---------|----------|-------|
| Cover image with progress badge | Top section | Shows overall % complete |
| Title & Author | Header area | Clear typography hierarchy |
| Chapter count | Stats row | Icon + text format |
| Estimated reading time | Stats row | Calculated from content length |
| Overall progress bar | Below cover | Gradient fill with chapter indicator |
| Chapter list with progress | Main content | Per-segment progress bars |
| Synthesis status indicators | Chapter row | Shows "Preparing", "Ready", percentage |
| Long-press context menu | Chapter row | Mark listened/unlistened, prepare chapter |
| Favorite toggle | Header | Heart icon |

### What's Missing (❌ Gaps)

| Gap | Impact | Priority |
|-----|--------|----------|
| **Time listened / remaining** | Users can't estimate how much is left | 🔴 High |
| **Chapter status icons** (read/in-progress/unread) | Visual scanning is difficult | 🔴 High |
| **"Continue from here" indicator** | Current position not immediately obvious | 🔴 High |
| **Chapter grouping/sections** | No structure for long chapter lists | 🟡 Medium |
| **Search/filter chapters** | No quick navigation for long books | 🟡 Medium |
| **Last listened timestamp** | No "Last played 2 days ago" | 🟡 Medium |
| **Playback speed indicator** | Not shown in book details | 🟢 Low |
| **Chapter duration estimates** | Only book total, not per-chapter | 🟢 Low |

---

## Proposed Layout

### Visual Hierarchy (Top to Bottom)

```
┌─────────────────────────────────────────────────────────────────┐
│  ←  Back                 Book Details               ♡  Favorite │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────┐   Title: The Great Adventure                      │
│  │         │   Author: John Smith                              │
│  │  COVER  │                                                   │
│  │  IMAGE  │   ⏱️ 8h 32m total  •  📖 24 chapters              │
│  │         │   🎧 3h 15m listened  •  5h 17m remaining         │
│  │   42%   │                                                   │
│  └─────────┘   Last played: Yesterday at 9:45 PM               │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    OVERALL PROGRESS                             │
│  ═══════════════════════●══════════════════════════════════    │
│  Chapter 8 of 24 • Segment 15 of 42                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [▶️ Continue Listening]  ← Primary action button               │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Chapters        📊 8/24 listened       🔍 Search               │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ✓  1. Chapter One - The Beginning                      │   │
│  │     ████████████████████████████████ 100% • 12m        │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ✓  2. A New Dawn                                        │   │
│  │     ████████████████████████████████ 100% • 8m         │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ▶️  3. The Journey Begins ← CURRENT                     │   │
│  │     █████████████░░░░░░░░░░░░░░░░░░ 42% • 5m left      │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ○  4. Crossing the River                                │   │
│  │     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0% • ~15m         │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ⟳  5. Night Falls (Preparing 62%)                       │   │
│  │     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0% • ~18m         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────── Show all 24 chapters ───────────                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Recommendations

### 1. Enhanced Stats Row (🔴 HIGH PRIORITY)

**Current:**
```dart
Row(children: [
  Icon(Icons.menu_book), Text('24 Chapters'),
  Icon(Icons.access_time), Text('8h 32m'),
])
```

**Proposed:**
```dart
// Two-row stats layout with listening time
Column(
  children: [
    Row(children: [
      Icon(Icons.menu_book), Text('24 chapters'),
      Text('•'),
      Icon(Icons.access_time), Text('8h 32m total'),
    ]),
    SizedBox(height: 4),
    Row(children: [
      Icon(Icons.headphones), Text('3h 15m listened'),
      Text('•'),
      Text('5h 17m remaining'),
    ]),
  ],
)
```

**Implementation Notes:**
- Calculate `timeListened` from segment progress database
- `timeRemaining = totalEstimate - timeListened`
- Show "remaining" in different color (e.g., `colors.textTertiary`)

---

### 2. Chapter Status Icons (🔴 HIGH PRIORITY)

Replace ambiguous progress percentages with clear status indicators:

| Status | Icon | Color | Meaning |
|--------|------|-------|---------|
| Unread | `○` (empty circle) | `colors.textTertiary` | Not started |
| In Progress | `▶️` or half-filled circle | `colors.primary` | Currently listening |
| Completed | `✓` (checkmark) | `colors.primary` filled | 100% listened |
| Preparing | `⟳` (sync icon) | `colors.accent` | Synthesis in progress |

**Code Change:**
```dart
Widget _buildChapterStatusIcon(ChapterProgress? progress, bool isCurrent, bool isSynthesizing) {
  if (isSynthesizing) {
    return Icon(Icons.sync, color: colors.accent, size: 20);
  }
  if (progress?.isComplete ?? false) {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check, color: colors.primaryForeground, size: 14),
    );
  }
  if (isCurrent) {
    return Icon(Icons.play_circle_filled, color: colors.primary, size: 24);
  }
  if (progress?.hasStarted ?? false) {
    return CircularProgressIndicator(
      value: progress!.percentComplete,
      strokeWidth: 2,
      color: colors.primary,
      backgroundColor: colors.background,
    );
  }
  return Container(
    width: 24, height: 24,
    decoration: BoxDecoration(
      border: Border.all(color: colors.textTertiary),
      shape: BoxShape.circle,
    ),
  );
}
```

---

### 3. "Continue From Here" Indicator (🔴 HIGH PRIORITY)

Highlight the current chapter distinctly:

```dart
// In chapter list item
Container(
  decoration: BoxDecoration(
    color: isCurrentChapter 
        ? colors.primary.withAlpha(25)  // Subtle highlight
        : colors.card,
    border: isCurrentChapter 
        ? Border(left: BorderSide(color: colors.primary, width: 4))
        : null,
    borderRadius: BorderRadius.circular(12),
  ),
  child: ...
)
```

Add badge text:
```dart
if (isCurrentChapter)
  Chip(
    label: Text('CONTINUE HERE'),
    backgroundColor: colors.primary,
    labelStyle: TextStyle(
      color: colors.primaryForeground,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    ),
  ),
```

---

### 4. Chapter Duration Estimates (🟡 MEDIUM)

Show estimated duration per chapter:

```dart
// Calculate from segment count and average TTS duration
String _estimateChapterDuration(int segmentCount) {
  // Average segment ~= 30 seconds of audio
  final totalSeconds = segmentCount * 30;
  final minutes = totalSeconds ~/ 60;
  if (minutes < 60) return '~${minutes}m';
  final hours = minutes ~/ 60;
  final remainingMins = minutes % 60;
  return '~${hours}h ${remainingMins}m';
}
```

Display in chapter row:
```dart
Row(
  children: [
    Text('42%', style: TextStyle(color: colors.textTertiary)),
    SizedBox(width: 8),
    Text('• ~12m', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
  ],
)
```

---

### 5. Chapter Search/Filter (🟡 MEDIUM)

For books with many chapters, add search:

```dart
// State
String _chapterSearchQuery = '';

// UI
TextField(
  decoration: InputDecoration(
    hintText: 'Search chapters...',
    prefixIcon: Icon(Icons.search),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    filled: true,
    fillColor: colors.background,
  ),
  onChanged: (value) => setState(() => _chapterSearchQuery = value),
)

// Filter
final filteredChapters = chapters.where((ch) =>
  ch.title.toLowerCase().contains(_chapterSearchQuery.toLowerCase())
).toList();
```

---

### 6. Chapter Stats Summary (🟡 MEDIUM)

Show listened/unread count in chapter section header:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text('Chapters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${listenedCount}/${totalCount} listened',
            style: TextStyle(fontSize: 12, color: colors.primary),
          ),
        ),
        SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.search),
          onPressed: _showChapterSearch,
        ),
      ],
    ),
  ],
)
```

---

### 7. Last Played Timestamp (🟡 MEDIUM)

Store and display last playback time:

```dart
// In BookProgress model, add:
final DateTime? lastPlayedAt;

// Display:
if (book.progress.lastPlayedAt != null)
  Text(
    'Last played: ${_formatRelativeTime(book.progress.lastPlayedAt!)}',
    style: TextStyle(fontSize: 12, color: colors.textTertiary),
  ),

String _formatRelativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return DateFormat('MMM d').format(time);
}
```

---

### 8. Progress Bar with Chapter Markers (🟢 LOW)

Enhance overall progress bar to show chapter boundaries:

```dart
Stack(
  children: [
    // Background
    Container(
      height: 8,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    // Progress fill
    FractionallySizedBox(
      widthFactor: progressPercent / 100,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.primary, colors.accent]),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    ),
    // Chapter markers (small ticks)
    ...chapterPositions.map((pos) => Positioned(
      left: MediaQuery.of(context).size.width * pos - 20,  // Adjust for padding
      child: Container(
        width: 2,
        height: 8,
        color: colors.textTertiary.withAlpha(128),
      ),
    )),
  ],
)
```

---

## Accessibility Considerations

1. **Screen readers**: Add semantic labels
   ```dart
   Semantics(
     label: 'Chapter 3, 42% complete, currently playing',
     child: chapterRow,
   )
   ```

2. **Touch targets**: Ensure chapter rows are at least 48dp tall (already met)

3. **Color contrast**: Don't rely solely on color for status - use icons + color

4. **Dynamic Type**: Support larger text sizes
   ```dart
   Text(
     chapter.title,
     style: Theme.of(context).textTheme.bodyLarge,  // Respects system text scale
   )
   ```

---

## Implementation Priority

### Phase 1: Quick Wins (1-2 hours)
- [ ] Add "time listened / time remaining" stats
- [ ] Highlight current chapter with left border
- [ ] Add "CONTINUE HERE" chip to current chapter

### Phase 2: Core Improvements (3-4 hours)
- [ ] Replace progress percentages with status icons
- [ ] Add chapter duration estimates
- [ ] Add "X/Y listened" count in header

### Phase 3: Enhanced Navigation (2-3 hours)
- [ ] Add chapter search for books with 10+ chapters
- [ ] Add last played timestamp
- [ ] Improve progress bar with chapter markers

---

## Testing Checklist

- [ ] Verify progress calculations are accurate
- [ ] Test with books having 1, 10, 50, and 100+ chapters
- [ ] Test with RTL languages
- [ ] Test with Dynamic Type sizes (small to accessibility XXL)
- [ ] Test dark/light theme transitions
- [ ] Verify screen reader announces chapter status correctly

---

## Appendix: Reference App Screenshots

### Audible Patterns
- Uses circular progress ring on cover
- Shows "X hours Y minutes left"
- Chapter list shows duration per chapter
- "Continue" button is always visible

### Libby Patterns
- Shows total time and time remaining prominently
- Uses timeline visualization for chapters
- Bookmark indicators on chapters
- "Start" vs "Resume" button text changes

### Apple Books (Audiobooks)
- Minimal chapter list (collapsed by default)
- Large cover with playback controls
- "X of Y chapters" in header
- Time remaining shown below progress bar

---

*Document generated as part of UX audit. Implementation should follow existing code patterns in the codebase.*
