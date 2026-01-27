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
┌──────────────────┐
│      Book        │
├──────────────────┤
│ id               │──────┬─────────────────────────────────────────┐
│ title            │      │                                         │
│ author           │      │                                         │
│ file_path        │      │ has many                                │
│ voice_id?        │      │ (nullable until first play)             │
│ is_favorite      │      │                                         │
└──────────────────┘      │                                         │
        │                 │                                         │
        │ voice used      │                                         │
        │ for synthesis   ▼                                         ▼
        │         ┌──────────────┐                         ┌──────────────┐
        │         │   Chapter    │                         │   Progress   │
        │         ├──────────────┤                         ├──────────────┤
        │         │ index        │◄────────────────────────│ chapter_idx  │
        │         │ title        │                         │ segment_idx  │
        │         │ segments[]   │─────────────────────────│ listen_time  │
        │         └──────┬───────┘                         └──────────────┘
        │                │ 
        │                │ has many (pre-segmented at import)
        │                ▼
        │         ┌──────────────┐                         ┌──────────────┐
        │         │   Segment    │═════════════════════════│ Cache Entry  │
        │         ├──────────────┤   same coordinates      ├──────────────┤
        │         │ index        │◄────────────────────────│ book_id (FK) │
        │         │ text         │                         │ chapter_idx  │
        │         │ char_count   │◄────────────────────────│ segment_idx  │
        │         │ duration_ms  │                         │ file_path    │
        └─────────┤              │                         │ size_bytes   │
 voice from Book  └──────────────┘                         │ compressed?  │
                                                           └──────────────┘

              ╔══════════════════════════════════════════════════════════════╗
              ║  KEY INSIGHT: One Voice Per Book                              ║
              ║  - Voice stored in Book, not CacheEntry                       ║
              ║  - Cache key: (book_id, chapter_idx, segment_idx)             ║
              ║  - Voice change clears cache and requires re-synthesis        ║
              ║  - Segment index = Progress position = Cache key              ║
              ╚══════════════════════════════════════════════════════════════╝
```

## One Voice Per Book Design

**Key Principle:** Each book has exactly one voice. Voice is locked at first play.
This eliminates cache invalidation on global voice changes and simplifies the data model.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ONE VOICE PER BOOK                                 │
│                                                                              │
│   • Voice assigned at first play (from global default)                       │
│   • Voice change requires explicit "Clear & Change Voice" action             │
│   • Cache key: (book_id, chapter, segment) — NO voice in key                 │
│   • All cache entries for a book share the same voice                        │
└─────────────────────────────────────────────────────────────────────────────┘

  Book: "Moby Dick"
  Voice: "Kokoro AF" (locked at first play)
  
  cache/
  ├── mobydick_123/
  │   ├── ch0_seg0.m4a     ◄── All same voice (Kokoro AF)
  │   ├── ch0_seg1.m4a
  │   ├── ch1_seg0.wav     ◄── Not yet compressed
  │   └── ...
  │
  ├── pride_456/             ◄── Different book can have different voice
  │   ├── ch0_seg0.m4a       ◄── All same voice (e.g., Piper EN)
  │   └── ...
  │
  └── metadata.json          ◄── Index for fast lookups

```

### Voice Lifecycle

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           VOICE LIFECYCLE                                     │
└──────────────────────────────────────────────────────────────────────────────┘

  IMPORT BOOK ────────────────────────► book.voiceId = null (no voice yet)
       │
       │ User plays book for first time
       ▼
  FIRST PLAY ─────────────────────────► book.voiceId = globalSettings.defaultVoice
       │                                (voice is now LOCKED for this book)
       │
       │ Cache entries created without voice in key
       ▼
  PLAYBACK ───────────────────────────► cacheKey = (book_id, chapter, segment)
       │
       │ User wants different voice?
       ▼
  CHANGE VOICE ───────────────────────► Confirm dialog → Clear all cache
       │                                → Set book.voiceId = newVoice
       │                                → Re-synthesize on next play
       ▼
  NEW VOICE ──────────────────────────► Same cache structure, different audio
```

### Why One Voice Per Book?

| Aspect | Multi-Voice Cache | One Voice Per Book (chosen) |
|--------|-------------------|----------------------------|
| Cache key | `(book, ch, seg, voice)` | `(book, ch, seg)` |
| Voice switch cost | Only synthesize missing | Delete all, re-synthesize |
| Storage predictability | N voices = N × storage | One voice = predictable |
| User mental model | "Which voice is playing?" | "This book = this voice" |
| Implementation | Complex | Simple |
| Global voice change | Invalidates nothing, confusing | N/A (no global voice in cache) |

**Decision**: The simpler "one voice per book" model trades A/B voice testing convenience 
for a clearer mental model and simpler implementation. Voice changes are rare after 
a user starts listening to a book.

## Cache: Book-Centric Design

The cache is keyed by book coordinates only (voice is per-book, not per-entry):

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CACHE STRUCTURE                                 │
│                         Key: (book_id, chapter, segment)                     │
└─────────────────────────────────────────────────────────────────────────────┘

  cache/
  ├── mobydick_123/
  │   ├── ch0_seg0.m4a     ◄── Compressed (voice from book.voiceId)
  │   ├── ch0_seg1.m4a     ◄── Compressed
  │   ├── ch1_seg0.wav     ◄── Not yet compressed
  │   └── ...
  │
  ├── pride_456/
  │   ├── ch0_seg0.m4a     ◄── Different book, possibly different voice
  │   └── ...
  │
  └── metadata.json        ◄── Index for fast lookups

```

### Why Book-Centric (not Content-Addressable)?

| Aspect | Content-Addressable | Book-Centric (chosen) |
|--------|--------------------|-----------------------|
| Key | `hash(text).wav` | `book_ch_seg.wav` |
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
  
  // Clear all cache for a book (used when changing voice)
  void clearForBook(String bookId) {
    _index.remove(bookId);
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

## Data Model Classes (Dart)

```dart
/// The core data model - elegant and simple
class Book {
  final String id;
  final String title;
  final String author;
  final String filePath;        // Original EPUB for reference
  final List<Chapter> chapters; // Pre-segmented at import
  final BookProgress progress;
  final bool isFavorite;
  final String? voiceId;        // Null until first play, then locked
  
  /// Get effective voice (book's voice or global default)
  String getVoice(UserSettings settings) => voiceId ?? settings.defaultVoiceId;
  
  /// Assign voice at first play (immutable after)
  Book withVoice(String voice) => Book(
    id: id, title: title, author: author, filePath: filePath,
    chapters: chapters, progress: progress, isFavorite: isFavorite,
    voiceId: voice,
  );
}

class Chapter {
  final int index;
  final String title;
  final List<Segment> segments; // Pre-computed at import time!
  
  int get segmentCount => segments.length;
  
  // Reconstruct full content for search (if needed)
  String get content => segments.map((s) => s.text).join('\n\n');
}

class Segment {
  final int index;
  final String text;
  final int charCount;
  final int estimatedDurationMs;
  
  /// Cache key uses book coordinates only (no voice - voice is per-book)
  String cacheKey(String bookId, int chapterIndex) => 
    '${bookId}_ch${chapterIndex}_seg$index';
}

/// Cache entry with book coordinates (no voice_id - voice is per-book)
class CacheEntry {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  // NO voiceId here - voice is stored on the Book, not the CacheEntry
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
  
  /// Clear all cache for a book (used when changing voice)
  void clearForBook(String bookId) {
    _index.remove(bookId);
    // Also delete the physical files in cache directory
  }
}

/// Voice change service - handles the "Clear & Change Voice" flow
class VoiceChangeService {
  final CacheIndex cacheIndex;
  final LibraryService libraryService;
  
  /// Change a book's voice (requires clearing cache)
  Future<void> changeVoice(String bookId, String newVoiceId) async {
    // 1. Clear all cached audio for this book
    cacheIndex.clearForBook(bookId);
    
    // 2. Delete physical cache files
    await _deleteCacheDirectory(bookId);
    
    // 3. Update book's voice
    await libraryService.updateBookVoice(bookId, newVoiceId);
    
    // 4. Next play will re-synthesize with new voice
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

## Data Storage (SQLite)

**Note:** Data is stored in SQLite (`eist_audiobook.db`), not JSON files.
See [SQLite Storage Architecture](#sqlite-storage-architecture) for full schema.

### Example Data Representation

```sql
-- Book record
INSERT INTO books VALUES (
  'moby_dick_abc123',           -- id
  'Moby Dick',                  -- title
  'Herman Melville',            -- author
  '/data/books/moby_dick.epub', -- file_path
  '/data/books/.../cover.jpg',  -- cover_image_path
  2701,                         -- gutenberg_id
  'kokoro_af',                  -- voice_id (NULL at import, set at first play)
  1,                            -- is_favorite
  1704067200000,                -- added_at
  1704070800000                 -- updated_at
);

-- Reading progress
INSERT INTO reading_progress VALUES (
  'moby_dick_abc123',           -- book_id
  1,                            -- chapter_index
  3,                            -- segment_index
  1704070800000,                -- last_played_at
  3600000,                      -- total_listen_time_ms
  1704070800000                 -- updated_at
);

-- Cache entry (NO voice_id - voice is per-book)
INSERT INTO cache_entries VALUES (
  1,                            -- id (auto)
  'moby_dick_abc123',           -- book_id
  0,                            -- chapter_index
  0,                            -- segment_index
  'cache/moby_ch0_seg0.m4a',    -- file_path
  45000,                        -- size_bytes
  12500,                        -- duration_ms
  1,                            -- is_compressed
  0,                            -- is_pinned
  1704067200000,                -- created_at
  1704070800000                 -- last_accessed_at
);

-- Chapter METADATA (no content - segments have the text)
INSERT INTO chapters VALUES (
  1,                            -- id (auto)
  'moby_dick_abc123',           -- book_id
  0,                            -- chapter_index
  'Chapter 1: Loomings',        -- title
  42,                           -- segment_count (pre-computed)
  5420,                         -- word_count
  28500,                        -- char_count
  1800000                       -- estimated_duration_ms
);

-- Segments (text lives here - pre-segmented at import)
INSERT INTO segments VALUES (
  1,                            -- id (auto)
  'moby_dick_abc123',           -- book_id
  0,                            -- chapter_index
  0,                            -- segment_index
  'Call me Ishmael.',           -- text (actual content)
  16,                           -- char_count
  1200                          -- estimated_duration_ms
);

INSERT INTO segments VALUES (
  2,                            -- id (auto)
  'moby_dick_abc123',           -- book_id
  0,                            -- chapter_index
  1,                            -- segment_index
  'Some years ago—never mind how long precisely—having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.',
  205,                          -- char_count
  15400                         -- estimated_duration_ms
);
```

## Import Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            IMPORT FLOW (ONCE)                                 │
└──────────────────────────────────────────────────────────────────────────────┘

  EPUB File                      Processing                        SQLite
  ─────────                      ──────────                        ──────

  moby_dick.epub ──────────────► Parse XHTML ─────────────────────► INSERT book
       │                              │
       │                              │ Clean HTML, extract text
       ▼                              ▼
  Raw HTML ────────────────────► segmentText() ───────────────────► segments[]
       │                              │                              (in memory)
       │                              │ Split by sentences/paragraphs
       ▼                              ▼
  Chapter content ─────────────► Estimate durations ──────────────► INSERT chapters
       │                              │                              (metadata only)
       │                              │
       ▼                              ▼
  Segments[] ──────────────────► Batch insert ────────────────────► INSERT segments
       │                              │                              (text lives here!)
       │                              │ chars/second calculation
       ▼                              ▼
                               Transaction commit


  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  DONE ONCE at import. Never re-segmented during playback.                 ║
  ║  TEXT is stored in segments table, NOT in EPUB file references.           ║
  ║  book.voice_id = NULL (assigned at first play)                            ║
  ╚══════════════════════════════════════════════════════════════════════════╝
```

## Playback Flow (Fast)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           PLAYBACK FLOW (FAST)                               │
└──────────────────────────────────────────────────────────────────────────────┘

  User Action                    Data Flow                          Source
  ───────────                    ─────────                          ──────

  Open Book ───────────────────► book = BookDao.getBook(id) ───────► SQLite
       │                              │
       │                              │ Already segmented!
       ▼                              ▼
  Play Chapter 2, Seg 3 ───────► segment = book.chapters[2].segments[3]
       │                              │
       │                              │ Check cache (indexed query)
       ▼                              ▼
  Need Audio? ─────────────────► cacheKey = (book_id, ch, seg) ← NO voice!
       │                              │
       │                              ├── Cache hit → play immediately
       ▼                              │
  Cache miss ──────────────────► TTS.synthesize(segment.text, book.voiceId) ─► audio
       │                              │
       │                              │ Save to cache (INSERT)
       ▼                              ▼
  Play ────────────────────────► audioPlayer.play(audioFile)


  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  No segmentation at playback. Data loaded from SQLite (indexed).          ║
  ║  Voice comes from book.voiceId (set at first play).                        ║
  ║  Cache lookup: SELECT * FROM cache_entries WHERE book_id=? AND ch=? ...   ║
  ╚══════════════════════════════════════════════════════════════════════════╝
```

## Summary: The Elegant Design

1. **Book is the center** - everything relates back to a book
2. **Unified coordinate space** - (book, chapter, segment) used everywhere
3. **Pre-segmented at import** - no re-segmentation during playback
4. **One voice per book** - voice stored on Book, not in cache key
5. **Cache is book-centric** - keyed by (book, chapter, segment), not content hash
6. **Progress is a pointer** - (book, chapter, segment) tuple
7. **O(1) lookups** - SQLite indexed queries, no full scans needed
8. **SQLite as single source of truth** - no JSON files or SharedPreferences

### Design Principles

| Principle | Application |
|-----------|-------------|
| Segment once, use everywhere | Import segments chapters, playback uses them directly |
| Single source of truth | All data in SQLite (eist_audiobook.db) |
| Same coordinate system | Book details, playback, and cache all use (book, chapter, segment) |
| One voice per book | Voice is on Book, cache key has no voice - simpler mental model |
| Fast by default | SQLite indexes, no full scans needed |
| Simplicity over deduplication | 1-2% storage waste is worth massive simplification |


---

## SQLite Storage Architecture

The data model is persisted in SQLite for fast queries and atomic operations.

### Database Schema

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SQLite DATABASE                                   │
│                          eist_audiobook.db                                   │
└─────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════╗
║  CORE TABLES                                                                   ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ books                                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ id TEXT PRIMARY KEY            │ "moby_dick_abc123"                         │
│ title TEXT NOT NULL            │ "Moby Dick"                                │
│ author TEXT NOT NULL           │ "Herman Melville"                          │
│ file_path TEXT NOT NULL        │ "/data/books/moby_dick.epub"               │
│ cover_image_path TEXT          │ "/data/books/moby_dick/cover.jpg"          │
│ gutenberg_id INTEGER           │ 2701                                       │
│ voice_id TEXT                  │ NULL → "kokoro_af" (set at first play)     │
│ is_favorite INTEGER            │ 0 or 1                                     │
│ added_at INTEGER               │ Unix timestamp                              │
│ updated_at INTEGER             │ Unix timestamp                              │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ 1:N
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ chapters (metadata only - no content)                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ id INTEGER PRIMARY KEY         │ Auto-increment                              │
│ book_id TEXT NOT NULL (FK)     │ → books.id                                  │
│ chapter_index INTEGER          │ 0, 1, 2, ...                                │
│ title TEXT NOT NULL            │ "Chapter 1: Loomings"                       │
│ segment_count INTEGER          │ Pre-computed: number of segments            │
│ word_count INTEGER             │ 5420                                        │
│ char_count INTEGER             │ 28500                                       │
│ estimated_duration_ms INTEGER  │ 1800000                                     │
│ UNIQUE(book_id, chapter_index) │                                             │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ 1:N (text lives in segments)
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ segments (pre-segmented at import - text lives here)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ id INTEGER PRIMARY KEY         │ Auto-increment                              │
│ book_id TEXT NOT NULL (FK)     │ → books.id                                  │
│ chapter_index INTEGER          │ 0, 1, 2, ...                                │
│ segment_index INTEGER          │ 0, 1, 2, ...                                │
│ text TEXT NOT NULL             │ "Call me Ishmael."                          │
│ char_count INTEGER             │ 16                                          │
│ estimated_duration_ms INTEGER  │ 1200                                        │
│ UNIQUE(book_id, chapter_index, segment_index)                                │
└─────────────────────────────────────────────────────────────────────────────┘

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  KEY: Text is stored in segments, not in chapters.                       ║
  ║       Segmentation happens ONCE at import time.                          ║
  ║       Playback just queries segments - no runtime segmentation.          ║
  ╚══════════════════════════════════════════════════════════════════════════╝

         │
         │ 1:1 (per book)
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ reading_progress                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ book_id TEXT PRIMARY KEY (FK)  │ → books.id                                  │
│ chapter_index INTEGER          │ Current chapter (0-based)                   │
│ segment_index INTEGER          │ Current segment (0-based)                   │
│ last_played_at INTEGER         │ Unix timestamp                              │
│ total_listen_time_ms INTEGER   │ Cumulative listening time                   │
│ updated_at INTEGER             │ Unix timestamp                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ completed_chapters                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│ book_id TEXT NOT NULL (FK)     │ → books.id                                  │
│ chapter_index INTEGER          │ Completed chapter index                     │
│ completed_at INTEGER           │ Unix timestamp                              │
│ PRIMARY KEY(book_id, chapter_index)                                          │
└─────────────────────────────────────────────────────────────────────────────┘


╔═══════════════════════════════════════════════════════════════════════════════╗
║  CACHE TABLES                                                                  ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ cache_entries                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ id INTEGER PRIMARY KEY         │ Auto-increment                              │
│ book_id TEXT NOT NULL (FK)     │ → books.id (CASCADE DELETE)                 │
│ chapter_index INTEGER          │ 0, 1, 2, ...                                │
│ segment_index INTEGER          │ 0, 1, 2, ...                                │
│ file_path TEXT NOT NULL        │ "cache/moby_ch0_seg0.m4a"                   │
│ size_bytes INTEGER             │ 45000                                       │
│ duration_ms INTEGER            │ 12500                                       │
│ is_compressed INTEGER          │ 1 (m4a) or 0 (wav)                          │
│ is_pinned INTEGER              │ 0 (evictable) or 1 (pinned)                 │
│ created_at INTEGER             │ Unix timestamp                              │
│ last_accessed_at INTEGER       │ Unix timestamp                              │
│ UNIQUE(book_id, chapter_index, segment_index)  ← NO voice_id in key!         │
└─────────────────────────────────────────────────────────────────────────────┘

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  KEY: Cache key is (book_id, chapter_index, segment_index)               ║
  ║       Voice is NOT in cache key - stored on Book, one voice per book     ║
  ║       Changing voice clears all cache entries for that book              ║
  ╚══════════════════════════════════════════════════════════════════════════╝


╔═══════════════════════════════════════════════════════════════════════════════╗
║  SETTINGS & CONFIG TABLES                                                      ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ settings                                                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ key TEXT PRIMARY KEY           │ "dark_mode", "selected_voice", etc.         │
│ value TEXT NOT NULL            │ JSON-encoded value                          │
│ updated_at INTEGER             │ Unix timestamp                              │
└─────────────────────────────────────────────────────────────────────────────┘

  Settings Keys (in SQLite):
  ├── selected_voice (string)         ← NOT needed at startup
  ├── auto_advance_chapters (bool)
  ├── default_playback_rate (double)
  ├── smart_synthesis_enabled (bool)
  ├── cache_quota_gb (double)
  ├── haptic_feedback_enabled (bool)
  ├── synthesis_mode (string enum)
  ├── compress_on_synthesize (bool)
  ├── show_buffer_indicator (bool)
  ├── show_book_cover_background (bool)
  └── runtime_playback_config (JSON blob)

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  HYBRID APPROACH: dark_mode stays in SharedPreferences (startup-critical) ║
  ║  All other settings in SQLite settings table above.                       ║
  ╚══════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ engine_configs                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│ engine_id TEXT PRIMARY KEY     │ "kokoro", "piper", "supertonic"             │
│ device_tier TEXT               │ "high", "medium", "low"                     │
│ max_concurrency INTEGER        │ 1-4 (learned via profiling)                 │
│ buffer_ahead_count INTEGER     │ 3-10 (learned)                              │
│ prefer_compression INTEGER     │ 0 or 1                                      │
│ avg_synthesis_time_ms INTEGER  │ Rolling average                             │
│ last_calibrated_at INTEGER     │ Unix timestamp                              │
│ config_json TEXT               │ Additional engine-specific settings         │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ model_metrics                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ model_id TEXT PRIMARY KEY      │ "kokoro_af", "piper_en_us_ryan"             │
│ engine_id TEXT NOT NULL (FK)   │ → engine_configs.engine_id                  │
│ avg_latency_ms INTEGER         │ Rolling average synthesis latency           │
│ avg_chars_per_second REAL      │ Performance metric                          │
│ total_syntheses INTEGER        │ Usage counter                               │
│ total_chars_synthesized INTEGER│ Cumulative                                  │
│ last_used_at INTEGER           │ Unix timestamp                              │
└─────────────────────────────────────────────────────────────────────────────┘


╔═══════════════════════════════════════════════════════════════════════════════╗
║  VOICE DOWNLOADS                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ downloaded_voices                                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│ voice_id TEXT PRIMARY KEY      │ "kokoro_af", "piper_en_us_ryan"             │
│ engine_type TEXT NOT NULL      │ "kokoro", "piper", "supertonic"             │
│ display_name TEXT              │ "Kokoro - American Female"                  │
│ language TEXT                  │ "en-US"                                     │
│ quality TEXT                   │ "high", "medium"                            │
│ size_bytes INTEGER             │ Download size                               │
│ install_path TEXT              │ Path to installed model                     │
│ downloaded_at INTEGER          │ Unix timestamp                              │
│ checksum TEXT                  │ SHA256 for verification                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Startup Sequence (Hybrid Settings)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         APP STARTUP SEQUENCE                                  │
└──────────────────────────────────────────────────────────────────────────────┘

  main() {
       │
       │ ① SharedPreferences (fast: ~5-10ms)
       ├────────────────────────────────────────────────────────► dark_mode
       │                                                           │
       │                                                           ▼
       │                                               ┌─────────────────────┐
       │                                               │ runApp(MaterialApp( │
       │                                               │   theme: dark/light │
       │                                               │ ))                  │
       │                                               └─────────────────────┘
       │
       │ ② SQLite init (async: ~20-50ms)
       ├────────────────────────────────────────────────────────► all other settings
       │                                                           │
       │                                                           ▼
       │                                               ┌─────────────────────┐
       │                                               │ SettingsController  │
       │                                               │ ready               │
       │                                               └─────────────────────┘
  }

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  Why hybrid? Theme must be set BEFORE first frame renders.               ║
  ║  SharedPreferences for dark_mode ensures no flash/flicker.               ║
  ║  All other settings can wait for SQLite (no visible delay).              ║
  ╚══════════════════════════════════════════════════════════════════════════╝
```

### Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ENTITY RELATIONSHIPS                                 │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────┐
                              │  settings   │
                              └─────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
              ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴─────┐
              │  engine   │   │  model    │   │downloaded │
              │  configs  │   │  metrics  │   │  voices   │
              └───────────┘   └───────────┘   └───────────┘


                              ┌─────────────┐
                              │    books    │ ◄─── voice_id (nullable)
                              └──────┬──────┘
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           │                         │                         │
           ▼                         ▼                         ▼
    ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
    │  chapters   │          │  reading    │          │   cache     │
    │ (metadata)  │          │  progress   │          │  entries    │
    └──────┬──────┘          └─────────────┘          └─────────────┘
           │
           │ 1:N
           ▼
    ┌─────────────┐          ┌─────────────┐
    │  segments   │──────────│  completed  │
    │  (text)     │          │  chapters   │
    └─────────────┘          └─────────────┘


  Cascade Deletes:
  ─────────────────
  DELETE book → DELETE chapters, segments, reading_progress, completed_chapters, cache_entries
```

### Query Examples

```sql
-- Get all books with progress
SELECT b.*, rp.chapter_index, rp.segment_index, rp.total_listen_time_ms
FROM books b
LEFT JOIN reading_progress rp ON b.id = rp.book_id
ORDER BY b.updated_at DESC;

-- Get segments for playback (no runtime segmentation!)
SELECT segment_index, text, char_count, estimated_duration_ms
FROM segments
WHERE book_id = ? AND chapter_index = ?
ORDER BY segment_index;

-- Get cache stats per book (O(1) with index)
SELECT book_id, 
       COUNT(*) as segment_count,
       SUM(size_bytes) as total_bytes,
       SUM(CASE WHEN is_compressed = 1 THEN 1 ELSE 0 END) as compressed_count
FROM cache_entries
GROUP BY book_id;

-- Get cache stats for a specific chapter
SELECT COUNT(*) as cached_segments, SUM(size_bytes) as chapter_bytes
FROM cache_entries
WHERE book_id = ? AND chapter_index = ?;

-- Clear cache when changing voice (used by VoiceChangeService)
DELETE FROM cache_entries WHERE book_id = ?;

-- Get LRU eviction candidates
SELECT * FROM cache_entries
WHERE is_pinned = 0
ORDER BY last_accessed_at ASC
LIMIT ?;
```

### Indexes

```sql
-- Primary indexes (auto-created)
-- books.id, settings.key, engine_configs.engine_id, etc.

-- Secondary indexes for common queries
CREATE INDEX idx_chapters_book ON chapters(book_id);
CREATE INDEX idx_cache_book ON cache_entries(book_id);
CREATE INDEX idx_cache_book_chapter ON cache_entries(book_id, chapter_index);
CREATE INDEX idx_cache_last_accessed ON cache_entries(last_accessed_at);
CREATE INDEX idx_model_engine ON model_metrics(engine_id);
```

### Database Initialization

```sql
-- Applied at database creation
PRAGMA journal_mode = WAL;      -- Write-ahead logging for concurrency
PRAGMA synchronous = NORMAL;    -- Balance safety/performance
PRAGMA foreign_keys = ON;       -- Enforce referential integrity
PRAGMA cache_size = -2000;      -- 2MB query cache
```
