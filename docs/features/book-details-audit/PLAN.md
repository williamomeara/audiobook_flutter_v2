# Book Details Page Audit & State Visualization Plan

## Current State Analysis

### What the Book Details Screen Currently Tracks

1. **Reading Progress**
   - `BookProgress`: chapterIndex + segmentIndex (persisted in Library)
   - `progressPercent`: derived from segments completed vs total
   - `completedChapters`: set of fully listened chapter indices

2. **Synthesis State**
   - `ChapterSynthesisState`: per-chapter synthesis status
     - `synthesizing`, `complete`, `error`, `idle`
     - Progress: 0.0-1.0 (percentage through synthesis)
   - Managed via `chapterSynthesisProvider`

3. **General Book Info**
   - Title, author, cover image
   - Chapter list (title, content length)
   - Favorite status

### What's Missing / Implicit

1. **Cache State** (per chapter/segment)
   - Which segments are actually cached vs need synthesis
   - Compressed vs uncompressed cache entries
   - Cache size per chapter

2. **Prefetch State**
   - What's queued for prefetch
   - Current prefetch progress
   - Prefetch mode (adaptive/aggressive/off)

3. **Playback History**
   - When was each chapter last played
   - Time spent per chapter
   - Listening sessions

---

## Data Sources Inventory

| Data | Source | Persistence | UI Location |
|------|--------|-------------|-------------|
| Reading position | `Book.progress` | SQLite/JSON | Progress bar |
| Completed chapters | `Book.completedChapters` | SQLite/JSON | Chapter badges |
| Synthesis progress | `ChapterSynthesisState` | In-memory | Chapter row |
| Cache entries | `IntelligentCacheManager` | Metadata JSON | ❌ Not shown |
| Compressed count | `CacheUsageStats` | Computed | Settings only |
| Prefetch queue | `SynthesisStrategy` | In-memory | ❌ Not shown |
| Prefetch mode | `RuntimePlaybackConfig` | SharedPrefs | Settings only |

---

## Proposed Information Architecture

### Option A: Chapter-Level Detail View

Show detailed state per chapter when expanded:

```
┌──────────────────────────────────────────────────┐
│ Chapter 5: The Journey Begins                    │
│ ○ 15 of 32 segments cached                       │
│ ○ 12 compressed (2.3 MB), 3 uncompressed (8.1 MB)│
│ ○ Progress: 40% listened                         │
│ ○ Last played: 2 days ago                        │
└──────────────────────────────────────────────────┘
```

**Pros:**
- All info at chapter level where it matters
- Easy to understand per-chapter state

**Cons:**
- Requires cache lookup per chapter (performance)
- UI becomes dense/complex

### Option B: Book-Level Summary Card

Add a "Storage & Progress" card above chapter list:

```
┌──────────────────────────────────────────────────┐
│ ⊕ Storage & Progress                             │
├──────────────────────────────────────────────────┤
│ 📖 Progress: Chapter 5 of 12 (42%)               │
│ 💾 Cached: 156 segments (45 MB)                  │
│    ├ 140 compressed (12 MB)                      │
│    └ 16 uncompressed (33 MB)                     │
│ ⏳ Prefetching: 3 segments queued                │
│ 🕐 Total listening time: 4h 23m                  │
└──────────────────────────────────────────────────┘
```

**Pros:**
- Clean summary view
- Single cache query
- Non-intrusive

**Cons:**
- Doesn't show per-chapter cache state
- Less actionable

### Option C: Hybrid - Summary + Chapter Icons

Summary card (Option B) + simple icons on chapters:

```
Chapter badges:
○ = No cache
◐ = Partially cached  
● = Fully cached
✓ = Cached + compressed
```

Example chapter row:
```
┌──────────────────────────────────────────────────┐
│ [●] 5. The Journey Begins           ▶ 40%      │
│     Tap to play • Long-press for options         │
└──────────────────────────────────────────────────┘
```

**Pros:**
- Best of both: summary + per-chapter indicators
- Visual at-a-glance status
- Minimal UI changes

**Cons:**
- Requires computing cache state per chapter

### Option D: Progressive Disclosure

Collapsible sections that load on demand:

```
▼ Reading Progress
  Chapter 5 of 12 (42%)
  15 chapters read • 4h 23m total

▶ Cache Status (tap to load)

▶ Synthesis Queue (tap to load)
```

**Pros:**
- Clean default view
- On-demand loading = better performance
- Power users can dig deeper

**Cons:**
- Extra taps for power users
- Hidden information

---

## Recommended Approach: Option C (Hybrid)

### Phase 1: Book-Level Summary Widget
1. Create `BookStorageSummaryCard` widget
2. Add provider: `bookCacheStatsProvider(bookId)`
3. Show: cached segments, compressed ratio, total size

### Phase 2: Chapter Cache Indicators
1. Add `ChapterCacheState` enum: `none`, `partial`, `full`, `compressed`
2. Create provider: `chapterCacheStateProvider(bookId, chapterIndex)`
3. Show icon badge on chapter rows

### Phase 3: Prefetch Visibility (Optional)
1. Show "Preparing..." indicator when prefetch is active
2. Add segment count to prefetch status

---

## Implementation Details

### New Data Model

```dart
/// Cache state for a specific chapter
class ChapterCacheInfo {
  final int cachedSegments;
  final int totalSegments;
  final int compressedSegments;
  final int cacheSizeBytes;
  
  CacheLevel get level => 
    cachedSegments == 0 ? CacheLevel.none :
    cachedSegments < totalSegments ? CacheLevel.partial :
    compressedSegments == cachedSegments ? CacheLevel.fullCompressed :
    CacheLevel.full;
}

enum CacheLevel { none, partial, full, fullCompressed }
```

### New Provider

```dart
/// Get cache info for a specific book
final bookCacheInfoProvider = FutureProvider.family<BookCacheInfo, String>((ref, bookId) async {
  final cacheManager = await ref.watch(intelligentCacheManagerProvider.future);
  return cacheManager.getBookCacheInfo(bookId);
});

/// Get cache info for a specific chapter
final chapterCacheInfoProvider = FutureProvider.family<ChapterCacheInfo, (String, int)>((ref, key) async {
  final (bookId, chapterIndex) = key;
  final cacheManager = await ref.watch(intelligentCacheManagerProvider.future);
  return cacheManager.getChapterCacheInfo(bookId, chapterIndex);
});
```

### Cache Manager Extension

```dart
extension CacheInfoExtension on IntelligentCacheManager {
  /// Get aggregated cache info for a book
  Future<BookCacheInfo> getBookCacheInfo(String bookId) async {
    final entries = _metadata.values
        .where((m) => m.bookId == bookId)
        .toList();
    
    return BookCacheInfo(
      cachedSegments: entries.length,
      compressedSegments: entries.where((m) => m.key.endsWith('.m4a')).length,
      totalSizeBytes: entries.fold(0, (sum, m) => sum + m.sizeBytes),
      chapterCount: entries.map((m) => m.chapterIndex).toSet().length,
    );
  }
  
  /// Get cache info for a specific chapter
  Future<ChapterCacheInfo> getChapterCacheInfo(String bookId, int chapterIndex) async {
    final entries = _metadata.values
        .where((m) => m.bookId == bookId && m.chapterIndex == chapterIndex)
        .toList();
    
    return ChapterCacheInfo(
      cachedSegments: entries.length,
      compressedSegments: entries.where((m) => m.key.endsWith('.m4a')).length,
      totalSizeBytes: entries.fold(0, (sum, m) => sum + m.sizeBytes),
    );
  }
}
```

---

## UI Mockups

### Summary Card (above chapter list)

```
┌─────────────────────────────────────────────────────┐
│ 💾 Storage                                          │
│                                                     │
│ ██████████░░░░░░░░░░░░ 48% cached                   │
│                                                     │
│ 156 segments • 45 MB total                          │
│ 140 compressed (12 MB) • 16 pending (33 MB)         │
│                                                     │
│ [Compress All]  [Prepare Book]                      │
└─────────────────────────────────────────────────────┘
```

### Chapter Row with Cache Badge

```
┌─────────────────────────────────────────────────────┐
│ ● 5                                                 │
│   The Journey Begins                      ▶ Play   │
│   12 min • 8/8 cached                              │
│   ████████████████████ 100%                        │
└─────────────────────────────────────────────────────┘

Badge legend:
○ = No cache (hollow)
◐ = Partial (half-filled)
● = Full cache (filled)
✓ = Compressed (checkmark)
```

---

## Open Questions

1. **Performance**: How expensive is querying cache per chapter on screen load?
   - Mitigation: Cache the computation, update on invalidation

2. **Total segments**: We don't store total segment count per chapter
   - Option: Estimate from content length (same as progressPercent)
   - Option: Store during synthesis/playback

3. **Listening history**: Not currently tracked
   - Would need new model + persistence
   - Consider: Is this actually needed?

4. **Refresh trigger**: When should cache stats refresh?
   - On screen focus
   - After synthesis complete
   - After compression

---

## Next Steps

- [ ] Review this plan with user
- [ ] Decide on option (A/B/C/D) 
- [ ] Decide which features to implement first
- [ ] Create detailed implementation tasks

