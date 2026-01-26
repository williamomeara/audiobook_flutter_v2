# Éist Data Model Architecture

## The Elegant Core

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ÉIST DATA MODEL                                 │
│                         "Everything Flows from Books"                        │
└─────────────────────────────────────────────────────────────────────────────┘


                              ┌─────────────┐
                              │    User     │
                              │  Settings   │
                              └──────┬──────┘
                                     │
                                     │ configures voice
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                            ╔═══════════════╗                                 │
│                            ║     BOOK      ║ ◄─── The Central Entity         │
│                            ╚═══════════════╝                                 │
│                                   │                                          │
│                    ┌──────────────┼──────────────┐                           │
│                    │              │              │                           │
│                    ▼              ▼              ▼                           │
│            ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                   │
│            │  Chapters   │ │  Progress   │ │   Cache     │                   │
│            └──────┬──────┘ └──────┬──────┘ └──────┬──────┘                   │
│                   │               │               │                          │
│                   ▼               ▼               ▼                          │
│            ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                   │
│            │  Segments   │═│  Position   │═│   Audio     │                   │
│            │   (text)    │ │ (ch, seg)   │ │   Files     │                   │
│            └─────────────┘ └─────────────┘ └─────────────┘                   │
│                                                                              │
│                         ════ Same coordinate space ════                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘


## The Unified Model

Everything shares the same coordinate system: (book, chapter, segment)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        COORDINATE SPACE: (book, chapter, segment)           │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Book "mobydick_123"                                                        │
│  │                                                                          │
│  ├── Chapter 0: "Loomings"                                                  │
│  │   ├── Segment 0: "Call me Ishmael..."        Cache: ✓ (compressed)      │
│  │   ├── Segment 1: "Some years ago..."         Cache: ✓ (compressed)      │
│  │   └── Segment 2: "There now is..."           Cache: ○ (none)            │
│  │                                                                          │
│  ├── Chapter 1: "The Carpet-Bag"                                            │
│  │   ├── Segment 0: "I stuffed a shirt..."      Cache: ● (wav)             │
│  │   └── Segment 1: "..."                       Cache: ○ (none)            │
│  │                                              ▲                           │
│  │                                              │                           │
│  │   Progress: ───────────────────────►  (ch: 1, seg: 0)                   │
│  │                                                                          │
│  └── Chapter 2: "The Spouter-Inn"                                           │
│      └── ...                                                                │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

## Entity Relationships

```
┌──────────────┐
│     Book     │
├──────────────┤
│ id           │──────┬─────────────────────────────────────────┐
│ title        │      │                                         │
│ author       │      │                                         │
│ file_path    │      │ has many                                │
│ voice_id     │      │                                         │
│ is_favorite  │      │                                         │
└──────────────┘      │                                         │
                      │                                         │
                      ▼                                         ▼
              ┌──────────────┐                         ┌──────────────┐
              │   Chapter    │                         │   Progress   │
              ├──────────────┤                         ├──────────────┤
              │ book_id (FK) │                         │ book_id (FK) │
              │ index        │◄────────────────────────│ chapter_idx  │
              │ title        │                         │ segment_idx  │
              │ content*     │                         │ listen_time  │
              └──────┬───────┘                         └──────────────┘
                     │ 
                     │ contains
                     ▼
              ┌──────────────┐                         ┌──────────────┐
              │   Segment    │═════════════════════════│ Cache Entry  │
              ├──────────────┤   same coordinates      ├──────────────┤
              │ chapter_idx  │◄────────────────────────│ book_id (FK) │
              │ segment_idx  │◄────────────────────────│ chapter_idx  │
              │ text         │                         │ segment_idx  │
              │ duration_est │                         │ voice_id     │
              └──────────────┘                         │ file_path    │
                                                       │ size_bytes   │
                      * stored in EPUB file            │ compressed?  │
                        not in database                └──────────────┘
```

## Cache: Book-Centric Design

The cache is keyed by book coordinates, not content hash:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CACHE STRUCTURE                                 │
│                     Key: (book_id, chapter, segment, voice)                  │
└─────────────────────────────────────────────────────────────────────────────┘

  cache/
  ├── mobydick_123/
  │   ├── ch0_seg0_kokoro_af.m4a     ◄── Compressed
  │   ├── ch0_seg1_kokoro_af.m4a     ◄── Compressed
  │   ├── ch1_seg0_kokoro_af.wav     ◄── Not yet compressed
  │   └── ...
  │
  ├── pride_456/
  │   ├── ch0_seg0_piper_en.m4a
  │   └── ...
  │
  └── metadata.json                   ◄── Index for fast lookups

```

### Why Book-Centric (not Content-Addressable)?

| Aspect | Content-Addressable | Book-Centric (chosen) |
|--------|--------------------|-----------------------|
| Key | `hash(text)_voice.wav` | `book_ch_seg_voice.wav` |
| Deduplication | ✓ Same text shares cache | ✗ Each book has own cache |
| Query: "What's cached for book X?" | Slow (scan all) | Fast (direct lookup) |
| Query: "What's cached for chapter Y?" | Very slow | Fast |
| Complexity | High | Low |
| Storage waste | ~0% | ~1-2% (rare duplicates) |

**Decision**: The 1-2% storage overhead is worth the massive simplification.

```dart
// Simple, fast queries
class CacheIndex {
  // book_id -> chapter_idx -> segment_idx -> CacheEntry
  final Map<String, Map<int, Map<int, CacheEntry>>> _index = {};
  
  // O(1) - instant
  int countForBook(String bookId) => 
    _index[bookId]?.values.expand((ch) => ch.values).length ?? 0;
  
  // O(1) - instant
  int countForChapter(String bookId, int chapterIdx) =>
    _index[bookId]?[chapterIdx]?.length ?? 0;
    
  // O(1) - instant
  bool isSegmentCached(String bookId, int chapter, int segment) =>
    _index[bookId]?[chapter]?[segment] != null;
    
  // O(1) - instant  
  CacheLevel chapterCacheLevel(String bookId, int chapterIdx, int totalSegments) {
    final cached = countForChapter(bookId, chapterIdx);
    if (cached == 0) return CacheLevel.none;
    if (cached < totalSegments) return CacheLevel.partial;
    if (allCompressed(bookId, chapterIdx)) return CacheLevel.fullCompressed;
    return CacheLevel.full;
  }
}
```

## State Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            STATE LIFECYCLE                                    │
└──────────────────────────────────────────────────────────────────────────────┘

  USER ACTION                    SYSTEM STATE                     PERSISTENCE
  ───────────                    ────────────                     ───────────

  Import Book ─────────────────► Book Created ──────────────────► library.json
       │                              │
       │                              │ parse chapters
       ▼                              ▼
  Open Book ───────────────────► Chapters Loaded ──────────────► (from EPUB)
       │                              │
       │                              │ segment text
       ▼                              ▼
  Play ────────────────────────► Synthesis Request ─────────────► cache_meta.json
       │                              │
       │                              │ TTS generates
       ▼                              ▼
  Listen ──────────────────────► Audio Playing ─────────────────► audio files
       │                              │
       │                              │ position updates
       ▼                              ▼
  Progress ────────────────────► Position Saved ────────────────► library.json
       │                              │
       │                              │ chapter complete
       ▼                              ▼
  Complete ────────────────────► Stats Updated ─────────────────► library.json
```

## The Unified View (Book Details Page)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         BOOK DETAILS: Data Sources                            │
└──────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  BOOK HEADER                                                                 │
│  ├── title, author, cover ─────────────────────────────── from: Book        │
│  ├── progress % ───────────────────────────────────────── from: Progress    │
│  └── favorite ♥ ───────────────────────────────────────── from: Book        │
├─────────────────────────────────────────────────────────────────────────────┤
│  STORAGE CARD                                                                │
│  ├── X segments cached ────────────────────────────────── from: CacheIndex  │
│  ├── Y compressed (Z MB) ──────────────────────────────── from: CacheIndex  │
│  └── [Compress] [Clear] buttons                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  CHAPTERS LIST                                                               │
│  │                                                                           │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  │ ● Chapter 1: The Beginning           ✓ Read   8/8 cached   5m    │  │
│  │  │   ████████████████████████████████████ 100%                       │  │
│  │  └───────────────────────────────────────────────────────────────────┘  │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  │ ◐ Chapter 2: The Journey             ⏸ 60%    6/10 cached  7m    │  │
│  │  │   ████████████████████░░░░░░░░░░░░░░░ 60%                        │  │
│  │  └───────────────────────────────────────────────────────────────────┘  │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  │ ○ Chapter 3: The Discovery                    0/12 cached  8m    │  │
│  │  │   ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0%                        │  │
│  │  └───────────────────────────────────────────────────────────────────┘  │
│  │                                                                           │
│  └── Badges: ○ none  ◐ partial  ● full  ✓ compressed                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Minimal Implementation (No SQLite)

```dart
/// The core data model - elegant and simple
class Book {
  final String id;
  final String title;
  final String author;
  final String filePath;      // Source of truth for content
  final List<Chapter> chapters;
  final BookProgress progress;
  final bool isFavorite;
}

class Chapter {
  final int index;
  final String title;
  final String content;       // Loaded from EPUB on demand
  
  List<Segment> get segments => segmentText(content);
  int get segmentCount => segments.length;
}

class Segment {
  final int chapterIndex;
  final int segmentIndex;
  final String text;
  final Duration estimatedDuration;
  
  /// Cache key uses book coordinates, not content hash
  String cacheKey(String bookId, String voiceId) => 
    '${bookId}_ch${chapterIndex}_seg${segmentIndex}_$voiceId';
}

/// Cache entry with book coordinates
class CacheEntry {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  final String voiceId;
  final String filePath;
  final int sizeBytes;
  final bool isCompressed;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
}

/// Cache index - O(1) lookups, book-centric
class CacheIndex {
  // book_id -> chapter_idx -> segment_idx -> CacheEntry
  final Map<String, Map<int, Map<int, CacheEntry>>> _index = {};
  
  void add(CacheEntry entry) {
    _index
      .putIfAbsent(entry.bookId, () => {})
      .putIfAbsent(entry.chapterIndex, () => {})
      [entry.segmentIndex] = entry;
  }
  
  int countForBook(String bookId) => 
    _index[bookId]?.values.expand((ch) => ch.values).length ?? 0;
  
  int countForChapter(String bookId, int chapterIdx) =>
    _index[bookId]?[chapterIdx]?.length ?? 0;
    
  CacheEntry? get(String bookId, int chapter, int segment) =>
    _index[bookId]?[chapter]?[segment];
    
  bool isSegmentCached(String bookId, int chapter, int segment) =>
    get(bookId, chapter, segment) != null;
    
  CacheLevel chapterCacheLevel(String bookId, int chapterIdx, int totalSegments) {
    final cached = countForChapter(bookId, chapterIdx);
    if (cached == 0) return CacheLevel.none;
    if (cached < totalSegments) return CacheLevel.partial;
    final allCompressed = _index[bookId]![chapterIdx]!.values
        .every((e) => e.isCompressed);
    return allCompressed ? CacheLevel.fullCompressed : CacheLevel.full;
  }
}

enum CacheLevel { none, partial, full, fullCompressed }
```

## When to Add Complexity

```
                Simple                              Complex
                  │                                    │
   Current ───────┼────────────────────────────────────┼───────► Future
                  │                                    │
              library.json                         SQLite
              cache_meta.json                      FTS5 Search
              SharedPreferences                    Analytics DB
                  │                                    │
                  │     Add complexity only when:      │
                  │     - Search is slow (>500ms)     │
                  │     - Need phrase search          │
                  │     - Want sync across devices    │
                  │     - Need complex queries        │
                  │                                    │
```

## Summary: The Elegant Design

1. **Book is the center** - everything relates back to a book
2. **Unified coordinate space** - (book, chapter, segment) used everywhere
3. **Content lives in files** - EPUB/PDF, not duplicated in database
4. **Cache is book-centric** - keyed by (book, chapter, segment, voice), not content hash
5. **Progress is a pointer** - (book, chapter, segment) tuple
6. **O(1) lookups** - in-memory index, no database needed
7. **Add complexity incrementally** - start simple, grow when needed

### Design Principles

| Principle | Application |
|-----------|-------------|
| Single source of truth | Content → EPUB file, Progress → library.json, Cache → cache_meta.json |
| Same coordinate system | Book details, playback, and cache all use (book, chapter, segment) |
| Fast by default | In-memory indexes, no full scans needed |
| Simplicity over deduplication | 1-2% storage waste is worth massive simplification |

