# SQLite Migration & State Consolidation Plan

## Best Practices Audit (Updated after research)

### Key Research Findings

**From Flutter/Mobile Best Practices:**

1. **WAL Mode is Essential**
   - Enable `PRAGMA journal_mode=WAL` for concurrent read/write
   - Can reduce latency by up to 40%
   - Works well with `PRAGMA synchronous=NORMAL` for mobile
   - ⚠️ Pitfall: WAL doesn't work over network FS, generates extra files (-wal, -shm)

2. **Batch Writes in Transactions**
   - Group inserts in single transaction (100-1000 rows optimal)
   - Avoid extremely large transactions (memory issues, long locks)
   - Can improve performance by 50%+ vs individual inserts

3. **Index Strategically**
   - Only index columns in WHERE, ORDER BY, JOIN clauses
   - Too many indexes slow down writes
   - Use `EXPLAIN QUERY PLAN` to profile

4. **sqflite vs Drift Recommendation**
   - **sqflite**: Better for simple schemas, SQL-savvy teams, full control
   - **Drift**: Better for complex schemas, type safety, reactive streams
   - Our app: Complex relational data + need reactivity → **Consider Drift**
   - But: sqflite is simpler to start, can migrate to Drift later

5. **Background Operations**
   - Never access DB on main thread
   - Use isolates for heavy operations
   - sqflite handles this automatically for most operations

### Plan Revisions Based on Research

| Original Plan | Audit Finding | Revision |
|---------------|---------------|----------|
| Store chapter content in DB | Large TEXT columns slow down queries | **Keep chapters in files, store only metadata** |
| Singleton DB instance | Good practice | ✅ Keep |
| No PRAGMA config mentioned | WAL mode critical | **Add WAL + synchronous=NORMAL** |
| No migration versioning | Need for future changes | **Add schema version table** |
| Batch insert not mentioned | Critical for import | **Add batch import for library.json** |
| No maintenance strategy | VACUUM needed periodically | **Add VACUUM on app idle** |

---

## Current Persistence Landscape

### 1. SharedPreferences (Key-Value)

| Key | Data Type | Location |
|-----|-----------|----------|
| `darkMode` | bool | settings_controller.dart |
| `selectedVoice` | string | settings_controller.dart |
| `autoAdvanceChapters` | bool | settings_controller.dart |
| `smartSynthesisEnabled` | bool | settings_controller.dart |
| `showBookCoverBackground` | bool | settings_controller.dart |
| `hapticFeedbackEnabled` | bool | settings_controller.dart |
| `synthesisMode` | enum | settings_controller.dart |
| `showBufferIndicator` | bool | settings_controller.dart |
| `compressOnSynthesize` | bool | settings_controller.dart |
| `cacheQuotaGB` | double | settings_controller.dart |
| `runtime_playback_config_v1` | JSON blob | runtime_playback_config.dart |
| `engine_config_*` | JSON blobs | engine_config_manager.dart |

### 2. JSON Files

| File | Content | Location |
|------|---------|----------|
| `library.json` | Full library state (books, progress, favorites) | Documents dir |
| `.cache_metadata.json` | Cache entry metadata | Cache dir |
| `voices_manifest.json` | Available TTS voices | Assets (read-only) |

### 3. In-Memory State (Not Persisted)

| State | Type | Should Persist? |
|-------|------|-----------------|
| `SegmentReadinessTracker` | Map<bookId, Map<segmentId, status>> | Maybe (recovery) |
| `ChapterSynthesisState` | Per-chapter synthesis progress | No (ephemeral) |
| `PlaybackState` | Current playback position | Partially (via Book.progress) |
| Concurrency counters | Per-model synthesis limits | Yes (learned values) |
| Download progress | Per-asset download state | No (recovery on restart) |

---

## Proposed SQLite Schema

### Core Tables

```sql
-- User settings (replaces SharedPreferences)
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,  -- JSON encoded
  updated_at INTEGER NOT NULL
);

-- Books library
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  file_path TEXT NOT NULL,
  cover_image_path TEXT,
  gutenberg_id INTEGER,
  voice_id TEXT,
  is_favorite INTEGER DEFAULT 0,
  added_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Chapters (normalized from books) - METADATA ONLY, content stays in files
CREATE TABLE chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  title TEXT NOT NULL,
  word_count INTEGER,
  char_count INTEGER,
  estimated_duration_ms INTEGER,
  -- Content stored in original EPUB/PDF file, not duplicated here
  UNIQUE(book_id, chapter_index)
);

-- Reading progress
CREATE TABLE reading_progress (
  book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL DEFAULT 0,
  segment_index INTEGER NOT NULL DEFAULT 0,
  last_played_at INTEGER,
  total_listen_time_ms INTEGER DEFAULT 0,
  updated_at INTEGER NOT NULL
);

-- Completed chapters
CREATE TABLE completed_chapters (
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  PRIMARY KEY(book_id, chapter_index)
);
```

### Audio Cache Tables

```sql
-- Cache entries (replaces .cache_metadata.json)
CREATE TABLE cache_entries (
  key TEXT PRIMARY KEY,  -- voiceId_hash.wav or .m4a
  book_id TEXT NOT NULL,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  voice_id TEXT NOT NULL,
  engine_type TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  duration_ms INTEGER,
  is_compressed INTEGER DEFAULT 0,
  is_pinned INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_accessed_at INTEGER NOT NULL,
  access_count INTEGER DEFAULT 1,
  FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
);

CREATE INDEX idx_cache_book ON cache_entries(book_id);
CREATE INDEX idx_cache_chapter ON cache_entries(book_id, chapter_index);
CREATE INDEX idx_cache_voice ON cache_entries(voice_id);
CREATE INDEX idx_cache_accessed ON cache_entries(last_accessed_at);
```

### TTS Engine Tables

```sql
-- Engine configuration and calibration
CREATE TABLE engine_configs (
  engine_id TEXT PRIMARY KEY,
  max_concurrency INTEGER DEFAULT 1,
  avg_synthesis_time_ms INTEGER,
  avg_chars_per_second REAL,
  last_calibrated_at INTEGER,
  config_json TEXT  -- Additional engine-specific settings
);

-- Per-model performance metrics
CREATE TABLE model_metrics (
  model_id TEXT PRIMARY KEY,
  engine_id TEXT NOT NULL REFERENCES engine_configs(engine_id),
  avg_latency_ms INTEGER,
  avg_chars_per_second REAL,
  total_syntheses INTEGER DEFAULT 0,
  total_chars_synthesized INTEGER DEFAULT 0,
  last_used_at INTEGER,
  FOREIGN KEY(engine_id) REFERENCES engine_configs(engine_id)
);
```

### Voice Download Tables

```sql
-- Downloaded voice models
CREATE TABLE downloaded_voices (
  voice_id TEXT PRIMARY KEY,
  engine_type TEXT NOT NULL,
  display_name TEXT NOT NULL,
  language TEXT NOT NULL,
  quality TEXT,
  size_bytes INTEGER NOT NULL,
  download_url TEXT NOT NULL,
  downloaded_at INTEGER NOT NULL,
  install_path TEXT NOT NULL,
  checksum TEXT
);

-- Download history/queue
CREATE TABLE download_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  voice_id TEXT NOT NULL,
  status TEXT NOT NULL,  -- 'pending', 'downloading', 'complete', 'failed'
  progress_percent INTEGER DEFAULT 0,
  bytes_downloaded INTEGER DEFAULT 0,
  total_bytes INTEGER,
  error_message TEXT,
  started_at INTEGER,
  completed_at INTEGER,
  retry_count INTEGER DEFAULT 0
);
```

### Database Initialization (New Section)

```sql
-- Schema version tracking for migrations
CREATE TABLE schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL,
  description TEXT
);

-- Initial pragmas for optimal mobile performance
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA cache_size = -2000;  -- 2MB cache
```

```dart
/// Database initialization with best practices
class AppDatabase {
  static Database? _db;
  static const _dbName = 'eist_audiobook.db';
  static const _dbVersion = 1;
  
  static Future<Database> get instance async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
    return _db!;
  }
  
  static Future<void> _onCreate(Database db, int version) async {
    // Apply pragmas first
    await db.execute('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA synchronous = NORMAL');
    await db.execute('PRAGMA foreign_keys = ON');
    
    // Create tables in order (respecting FK dependencies)
    await db.execute(createBooksTable);
    await db.execute(createChaptersTable);
    // ... etc
    
    // Record schema version
    await db.insert('schema_version', {
      'version': version,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
      'description': 'Initial schema',
    });
  }
  
  static Future<void> _onOpen(Database db) async {
    // Re-apply WAL mode (some devices reset it)
    await db.execute('PRAGMA journal_mode = WAL');
  }
  
  /// Batch insert with transaction (optimal for migration)
  static Future<void> batchInsert<T>(
    Database db,
    String table,
    List<Map<String, dynamic>> rows, {
    int batchSize = 500,
  }) async {
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.skip(i).take(batchSize).toList();
      await db.transaction((txn) async {
        for (final row in batch) {
          await txn.insert(table, row);
        }
      });
    }
  }
}
```

---

## Migration Strategy

### Phase 1: Add SQLite Infrastructure
1. Add `sqflite` package to pubspec.yaml
2. Create database helper class with schema versioning
3. Add migration system for future schema changes

### Phase 2: Migrate Library (Highest Priority)
1. Create books/chapters/progress tables
2. Add migration code to import existing library.json
3. Update LibraryController to use SQLite
4. Keep library.json as backup/export format

### Phase 3: Migrate Cache Metadata
1. Create cache_entries table
2. Migrate from .cache_metadata.json
3. Update IntelligentCacheManager
4. Add new query methods (by book, by chapter)

### Phase 4: Migrate Settings
1. Create settings table
2. Migrate from SharedPreferences
3. Update SettingsController
4. Keep SharedPreferences as fallback for quick reads

### Phase 5: Add New Features
1. Engine metrics/calibration tables
2. Listening history tracking
3. Per-model concurrency learning

---

## Benefits

### Current Pain Points Solved

| Problem | Solution |
|---------|----------|
| Cache stats require full scan | `SELECT SUM(size_bytes) FROM cache_entries WHERE book_id = ?` |
| No per-chapter cache info | `SELECT COUNT(*) FROM cache_entries WHERE book_id = ? AND chapter_index = ?` |
| Library.json grows large | Normalized tables, lazy chapter loading |
| No listening analytics | `reading_progress.total_listen_time_ms` + history table |
| Can't query settings efficiently | Single indexed table |
| Concurrency not learned | `model_metrics` tracks real performance |

### New Capabilities

1. **Fast queries**: Get book cache stats in O(1) not O(n)
2. **Partial loading**: Load book metadata without all chapter content
3. **Analytics**: Time spent per book, listening patterns
4. **Smart concurrency**: Learn optimal concurrency per model/device
5. **Offline-first**: SQLite works offline, syncs when needed
6. **Data integrity**: Foreign keys, transactions, ACID

---

## Database Package Choice

### Option A: sqflite (Recommended)
- ✅ Most mature Flutter SQLite package
- ✅ Cross-platform (iOS, Android, macOS, Linux, Windows)
- ✅ Well documented
- ❌ Requires manual SQL

### Option B: drift (formerly moor)
- ✅ Type-safe queries, code generation
- ✅ Migrations, reactive streams
- ❌ More complex setup
- ❌ Build runner dependency

### Option C: isar
- ✅ Very fast, modern API
- ✅ Reactive, type-safe
- ❌ Different paradigm (document-based)
- ❌ Less mature than sqflite

**Recommendation**: Start with **sqflite** for simplicity and control, consider drift later if we need more complex queries.

**Updated Recommendation after research**: Given our need for:
- Complex relational queries (book → chapters → cache entries)
- Reactive updates (UI should update when cache changes)
- Type safety to prevent runtime errors

**Consider starting with Drift** if willing to accept the build_runner complexity. Otherwise, sqflite with manual stream/change notification is fine.

---

## Performance Considerations

### Expected Database Size
| Data | Rows (100 books) | Estimated Size |
|------|------------------|----------------|
| books | 100 | ~50 KB |
| chapters | ~1,500 | ~200 KB |
| cache_entries | ~15,000 | ~2 MB |
| reading_progress | 100 | ~10 KB |
| model_metrics | ~50 | ~5 KB |
| **Total** | ~16,750 | **~2.3 MB** |

### Query Performance Targets
| Query | Target Latency | Current (JSON scan) |
|-------|----------------|---------------------|
| Get book cache size | <5ms | ~50-100ms |
| Get chapter cache count | <2ms | ~20-50ms |
| List all books | <10ms | ~5ms (already fast) |
| Update progress | <5ms | ~10ms |

### Indexing Strategy
```sql
-- Primary indexes (auto-created on PRIMARY KEY)
-- Secondary indexes for common queries:
CREATE INDEX idx_cache_book_chapter ON cache_entries(book_id, chapter_index);
CREATE INDEX idx_cache_voice ON cache_entries(voice_id);
CREATE INDEX idx_cache_last_accessed ON cache_entries(last_accessed_at);
CREATE INDEX idx_chapters_book ON chapters(book_id);
```

---

## Estimated Effort

| Phase | Effort | Priority |
|-------|--------|----------|
| Infrastructure | 2-3 hours | High |
| Library migration | 4-6 hours | High |
| Cache migration | 3-4 hours | High |
| Settings migration | 2 hours | Medium |
| New features | 4-6 hours | Low |

**Total: ~15-20 hours** for full migration

---

## Questions to Resolve

1. **Schema versioning**: How to handle schema upgrades gracefully?
2. **Encryption**: Do we need to encrypt the database? (probably not for audiobooks)
3. **Backup/export**: Keep JSON export capability?
4. **Chapter content**: Store in DB or keep as file references?
5. **Sync**: Any future cloud sync requirements?

---

## Next Steps

- [ ] Decide: Go with sqflite or drift?
- [ ] Decide: Full migration or incremental?
- [ ] Create database helper class
- [ ] Write migration for library.json → SQLite
- [ ] Update LibraryController
- [ ] Write migration for cache metadata
- [ ] Update IntelligentCacheManager

