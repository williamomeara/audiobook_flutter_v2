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
| `defaultPlaybackRate` | double | settings_controller.dart |
| `smartSynthesisEnabled` | bool | settings_controller.dart |
| `showBookCoverBackground` | bool | settings_controller.dart |
| `hapticFeedbackEnabled` | bool | settings_controller.dart |
| `synthesisMode` | enum | settings_controller.dart |
| `showBufferIndicator` | bool | settings_controller.dart |
| `compressOnSynthesize` | bool | settings_controller.dart |
| `cacheQuotaGB` | double | settings_controller.dart |
| `runtime_playback_config_v1` | JSON blob | runtime_playback_config.dart |
| `engine_config_{engineId}` | JSON blobs | packages/playback/engine_config_manager.dart |
| `engine_tuned_{engineId}` | ISO8601 string | packages/playback/engine_config_manager.dart |

### 2. JSON Files

| File | Content | Location |
|------|---------|----------|
| `library.json` | Full library state (books, progress, favorites) | Documents dir |
| `.cache_metadata.json` | Cache entry metadata | Cache dir |
| `voices_manifest.json` | Available TTS voices | Assets (read-only) |
| `.manifest` | Download installation manifest (per voice asset) | voice_assets/{key}/ |

### 3. Package-Level Persistence (needs migration)

| Package | File | Persistence Type |
|---------|------|------------------|
| `playback` | `engine_config_manager.dart` | SharedPreferences (engine configs, tuning timestamps) |
| `tts_engines` | `intelligent_cache_manager.dart` | JSON file (.cache_metadata.json) |
| `downloads` | `atomic_asset_manager.dart` | JSON manifests (.manifest files) |

### 4. In-Memory State (Not Persisted)

| State | Type | Should Persist? |
|-------|------|-----------------|
| `SegmentReadinessTracker` | Map<bookId, Map<segmentId, status>> | Maybe (recovery) |
| `ChapterSynthesisState` | Per-chapter synthesis progress | No (ephemeral) |
| `PlaybackState` | Current playback position | Partially (via Book.progress) |
| Concurrency counters | Per-model synthesis limits | Yes (learned values) |
| Download progress | Per-asset download state | No (recovery on restart) |
| `_states` in AtomicAssetManager | Download state per asset | No (recovery from filesystem) |

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

-- Chapters (metadata only - no content, segments have the text)
CREATE TABLE chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  title TEXT NOT NULL,
  segment_count INTEGER NOT NULL,     -- pre-computed at import
  word_count INTEGER,
  char_count INTEGER,
  estimated_duration_ms INTEGER,
  UNIQUE(book_id, chapter_index)
);

-- Segments (pre-segmented at import - text lives here)
CREATE TABLE segments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  text TEXT NOT NULL,                  -- segment text (e.g., one sentence)
  char_count INTEGER NOT NULL,
  estimated_duration_ms INTEGER NOT NULL,
  UNIQUE(book_id, chapter_index, segment_index)
);

CREATE INDEX idx_segments_book_chapter ON segments(book_id, chapter_index);

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
-- NOTE: NO voice_id in this table - voice is stored on the Book (one voice per book)
-- Cache key is (book_id, chapter_index, segment_index) only
CREATE TABLE cache_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  file_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  duration_ms INTEGER,
  is_compressed INTEGER DEFAULT 0,
  is_pinned INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_accessed_at INTEGER NOT NULL,
  UNIQUE(book_id, chapter_index, segment_index)
);

CREATE INDEX idx_cache_book ON cache_entries(book_id);
CREATE INDEX idx_cache_chapter ON cache_entries(book_id, chapter_index);
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
-- Downloaded voice models (tracks which voices are installed)
-- NOTE: .manifest files are KEPT for atomic install verification (see Phase 6 decision)
-- This table provides fast queries for "is voice X installed?" without filesystem checks
CREATE TABLE downloaded_voices (
  voice_id TEXT PRIMARY KEY,
  engine_type TEXT NOT NULL,
  display_name TEXT NOT NULL,
  language TEXT NOT NULL,
  quality TEXT,
  size_bytes INTEGER NOT NULL,
  install_path TEXT NOT NULL,
  downloaded_at INTEGER NOT NULL,
  checksum TEXT
);

-- NOTE: download_history table REMOVED - download progress is ephemeral
-- and recovers from filesystem state on app restart. No need to persist.
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

## Full Replacement Migration Plan

**Goal**: Completely replace JSON-based persistence with SQLite. No dual-mode, no rollback, no legacy code.

### Decisions Made

| Question | Decision |
|----------|----------|
| sqflite vs drift? | **sqflite** - simpler, full control, good enough for our needs |
| Full migration or incremental? | **Full replacement** - app not released, no need for dual-mode |
| Keep backup capability? | **No** - can add JSON export feature later if needed |
| Chapter content storage? | **Keep in EPUB/PDF files** - only store metadata in DB |
| Voice in cache key? | **No** - one voice per book (from ARCHITECTURE.md) |

### Schema Alignment with ARCHITECTURE.md

Incorporating "One Voice Per Book" design:

```sql
-- Books table (voice_id nullable until first play, then locked)
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  file_path TEXT NOT NULL,
  cover_image_path TEXT,
  gutenberg_id INTEGER,
  voice_id TEXT,  -- NULL at import, set at first play
  is_favorite INTEGER DEFAULT 0,
  added_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Cache entries (NO voice_id - voice is per-book, not per-entry)
CREATE TABLE cache_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  file_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  duration_ms INTEGER,
  is_compressed INTEGER DEFAULT 0,
  is_pinned INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_accessed_at INTEGER NOT NULL,
  UNIQUE(book_id, chapter_index, segment_index)
);
```

---

## Execution Checklist

### Phase 1: Infrastructure (Foundation) - COMPLETED

- [x] **1.1** Add sqflite to pubspec.yaml
- [x] **1.2** Create `lib/app/database/app_database.dart`
  - Singleton pattern
  - WAL mode, pragmas
  - Schema version tracking
- [x] **1.3** Create `lib/app/database/migrations/` folder
  - `migration_v1.dart` - initial schema
- [x] **1.4** Create `lib/app/database/daos/` folder structure
  - `book_dao.dart`
  - `chapter_dao.dart`
  - `segment_dao.dart`
  - `progress_dao.dart`
  - `completed_chapters_dao.dart`
  - `cache_dao.dart`
  - `settings_dao.dart`
  - `engine_config_dao.dart`
  - `model_metrics_dao.dart`
  - `downloaded_voices_dao.dart`
- [x] **1.5** Create `lib/app/database/database.dart` barrel file

### Phase 2: Library Migration (Replace library.json) - COMPLETED

**Files created/modified:**
- `lib/app/database/repositories/library_repository.dart` - NEW
- `lib/app/database/migrations/json_migration_service.dart` - NEW
- `lib/app/library_controller.dart` - REWRITTEN to use SQLite
- `lib/app/playback_providers.dart` - UPDATED to use SQLite segments
- `lib/ui/screens/book_details_screen.dart` - UPDATED to use SQLite segments

**Steps:**
- [x] **2.1** Create `BookDao` with CRUD operations (completed in Phase 1)
- [x] **2.2** Create `ChapterDao` (metadata only, no content) (completed in Phase 1)
- [x] **2.3** Create `SegmentDao` (text lives here) (completed in Phase 1)
- [x] **2.4** Create `ProgressDao` (completed in Phase 1)
- [x] **2.5** Create `CompletedChaptersDao` (completed in Phase 1)
- [x] **2.6** Update import logic to pre-segment at import time
  - Parse EPUB/PDF → extract chapters
  - Call `segmentText(chapter.content)` once at import
  - Insert chapter metadata + segments into DB via `LibraryRepository.insertBook()`
- [x] **2.7** Rewrite `LibraryController` to use `LibraryRepository`
  - Uses `LibraryRepository` which coordinates all DAOs
  - `getSegmentsForChapter()` replaces runtime `segmentText()` calls
  - Auto-migration from library.json on first launch
- [x] **2.8** JSON migration service created
  - `JsonMigrationService.migrate()` runs automatically on first DB open
  - Backs up library.json to library.json.backup
  - Deletes original after successful migration
- [x] **2.9** Update playback to use SQLite segments
  - `playback_providers.dart` - `loadChapter()` uses `getSegmentsForChapter()`
  - `book_details_screen.dart` - `_loadChapterTracks()` uses SQLite

### Phase 3: Cache Migration (Replace .cache_metadata.json) - COMPLETED

**Files created/modified:**
- `lib/app/database/migrations/migration_v2.dart` - NEW (adds access_count, engine_type, voice_id columns)
- `lib/app/database/migrations/cache_migration_service.dart` - NEW
- `lib/app/database/sqlite_cache_metadata_storage.dart` - NEW (SQLite implementation of CacheMetadataStorage)
- `lib/app/database/daos/cache_dao.dart` - UPDATED (added filename-based methods for CacheMetadataStorage)
- `lib/app/database/daos/settings_dao.dart` - UPDATED (added convenience methods)
- `lib/app/playback_providers.dart` - UPDATED (uses SqliteCacheMetadataStorage)
- `packages/tts_engines/lib/src/cache/cache_metadata_storage.dart` - NEW (abstract interface)
- `packages/tts_engines/lib/src/cache/json_cache_metadata_storage.dart` - NEW (JSON fallback/migration)
- `packages/tts_engines/lib/src/cache/intelligent_cache_manager.dart` - REWRITTEN (uses storage interface)
- `packages/tts_engines/lib/tts_engines.dart` - UPDATED (exports new cache files)

**Architecture:**
- Created abstract `CacheMetadataStorage` interface in tts_engines package
- IntelligentCacheManager accepts storage interface (no file dependencies)
- App layer provides `SqliteCacheMetadataStorage` implementation
- `JsonCacheMetadataStorage` kept for migration and fallback

**Steps:**
- [x] **3.1** Extended `CacheDao` with filename-based methods
  - `getAllEntriesByFilePath()` - load all entries as Map<filename, row>
  - `upsertEntryByFilePath()` - insert/update by file_path
  - `deleteEntryByFilePath()` / `deleteEntriesByFilePaths()` - batch delete
  - `getTotalSizeFromMetadata()`, `getSizeByBook()`, `getSizeByVoice()` - aggregations
  - `getCompressedCount()` - count .m4a entries
  - Original coordinate-based methods retained for future use
- [x] **3.2** Created migration service (`cache_migration_service.dart`)
  - `CacheMigrationService.needsMigration()` checks for JSON file
  - `CacheMigrationService.migrate()` reads JSON, inserts to SQLite
  - Backs up JSON to .cache_metadata.json.migrated
  - Auto-runs on database open
- [x] **3.3** Created storage interface pattern
  - `CacheMetadataStorage` abstract interface in tts_engines package
  - `JsonCacheMetadataStorage` implements interface for JSON file
  - `SqliteCacheMetadataStorage` implements interface for SQLite (app layer)
  - IntelligentCacheManager accepts `CacheMetadataStorage` instead of `File`
- [x] **3.4** Updated `playback_providers.dart`
  - Gets database instance via `AppDatabase.instance`
  - Creates CacheDao and SettingsDao
  - Creates SqliteCacheMetadataStorage
  - Passes storage to IntelligentCacheManager
- [x] **3.5** Removed JSON file handling from IntelligentCacheManager
  - Removed `metadataFile` parameter
  - Removed `_loadMetadata()` / `_saveMetadata()` methods
  - All persistence goes through `_storage` interface

### Phase 4: Settings Migration (Hybrid: SharedPreferences + SQLite) - COMPLETED

**Key Decision:** Keep ONLY `dark_mode` in SharedPreferences (needed at app startup for theme).
All other settings go to SQLite.

**Files created/modified:**
- `lib/app/quick_settings_service.dart` - NEW (SharedPreferences dark_mode only)
- `lib/app/database/migrations/settings_migration_service.dart` - NEW (one-time migration)
- `lib/app/settings_controller.dart` - REWRITTEN (uses SQLite + QuickSettingsService)
- `lib/app/config/runtime_playback_config.dart` - REWRITTEN (uses SQLite)
- `lib/main.dart` - UPDATED (initializes QuickSettingsService at startup)
- `lib/app/database/app_database.dart` - UPDATED (runs settings migration)
- `lib/app/database/daos/settings_dao.dart` - UPDATED (added darkMode key)

**Settings Location Map:**

| Setting | Location | Reason |
|---------|----------|--------|
| `dark_mode` | SharedPreferences + SQLite | Needed IMMEDIATELY at app launch for theme |
| `selected_voice` | SQLite | Not needed until Settings or first-play |
| `auto_advance_chapters` | SQLite | Not startup-critical |
| `default_playback_rate` | SQLite | Not startup-critical |
| `smart_synthesis_enabled` | SQLite | Not startup-critical |
| `cache_quota_gb` | SQLite | Not startup-critical |
| `haptic_feedback_enabled` | SQLite | Not startup-critical |
| `synthesis_mode` | SQLite | Not startup-critical |
| `compress_on_synthesize` | SQLite | Not startup-critical |
| `show_buffer_indicator` | SQLite | Not startup-critical |
| `show_book_cover_background` | SQLite | Not startup-critical |
| `runtime_playback_config` | SQLite | Not startup-critical |

**Steps:**
- [x] **4.1** SettingsDao already existed with full CRUD operations
- [x] **4.2** Created `QuickSettingsService` for SharedPreferences (dark_mode only)
  - Static `initialize()` returns initial dark mode value
  - Synchronous `darkMode` getter after initialization
  - `setDarkMode()` for updates
- [x] **4.3** Updated `main.dart` to read dark_mode from SharedPreferences at startup
  - Calls `QuickSettingsService.initialize()` before `runApp()`
  - Passes `initialDarkMode` to `AudiobookApp`
- [x] **4.4** Rewrote `SettingsController`
  - Uses `QuickSettingsService` for dark_mode reads at startup
  - Uses `SettingsDao` for all settings persistence
  - When dark_mode changes: updates both SharedPreferences AND SQLite
- [x] **4.5** Created `SettingsMigrationService`
  - Runs automatically on database open
  - Reads all SharedPreferences keys
  - Inserts into SQLite settings table
  - Clears old SP keys (except dark_mode)
- [x] **4.6** Rewrote `RuntimePlaybackConfig`
  - Stores in settings table as JSON blob
  - Removed SharedPreferences dependency

**Note:** Keep `shared_preferences` package for `dark_mode` only. Remove it from playback package.

### Phase 5: Engine Config Migration (Package: playback) - COMPLETED (via removal)

**Decision:** The engine calibration popup feature was removed entirely because Auto Synth now handles
intelligent pre-synthesis automatically. This eliminated the need for manual engine profiling/calibration.

**Files DELETED:**
- `lib/ui/widgets/optimization_prompt_dialog.dart` - The calibration popup dialog
- `lib/app/database/daos/engine_config_dao.dart` - Unused DAO
- `packages/playback/lib/src/engine_config.dart` - Device tier config classes
- `packages/playback/lib/src/engine_config_manager.dart` - SharedPreferences-based config manager
- `packages/playback/lib/src/device_profiler.dart` - Device performance profiler
- `packages/playback/lib/src/calibration/` - Entire calibration folder
- `packages/playback/test/calibration/` - Calibration tests

**Files MODIFIED:**
- `lib/ui/screens/playback_screen.dart` - Removed prompt call and import
- `lib/app/playback_providers.dart` - Removed `engineConfigManagerProvider` and `deviceProfilerProvider`
- `lib/app/database/database.dart` - Removed engine_config_dao export
- `packages/playback/lib/playback.dart` - Removed exports for deleted files
- `packages/playback/pubspec.yaml` - Removed `shared_preferences` dependency

**Steps (completed via removal):**
- [x] **5.1** ~~Create `EngineConfigDao`~~ → REMOVED (feature deleted)
- [x] **5.2** ~~Create `ModelMetricsDao`~~ → ModelMetricsDao already exists for synthesis metrics tracking
- [x] **5.3** ~~Migrate existing engine configs~~ → No migration needed (feature removed)
- [x] **5.4** ~~Update `DeviceEngineConfigManager`~~ → DELETED
- [x] **5.5** Remove SharedPreferences dependency from playback package ✓

**Note:** The `engine_configs` table still exists in the database schema (migration_v1.dart) but is unused.
It can be dropped in a future migration if desired, but leaving it causes no harm.

### Phase 5.5: Enhanced Reading Progress (Per-Segment Tracking)

**Goal:** Track exactly which segments have been listened to, enabling:
- Accurate per-chapter progress percentages (e.g., "45% of chapter 3")
- Support for non-linear reading (users who skip around)
- Ability to mark entire chapters as read/unread
- Visual indication of listened vs unlistened segments

**Design Decision:** Create separate `segment_progress` table (not add column to `segments`)
- ✅ Clean separation of content data vs. user progress data
- ✅ Easy to clear progress without affecting content
- ✅ Can track additional metadata (listened_at timestamp)
- ✅ Supports future multi-user scenarios
- ✅ Progress queries don't bloat segment table scans

**New Table Schema:**
```sql
CREATE TABLE segment_progress (
  book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  is_listened INTEGER DEFAULT 1,  -- Presence in table means listened
  listened_at INTEGER NOT NULL,   -- Timestamp when first listened
  PRIMARY KEY(book_id, chapter_index, segment_index)
);

CREATE INDEX idx_segment_progress_chapter 
  ON segment_progress(book_id, chapter_index);
```

**Files to create/modify:**
- `lib/app/database/migrations/migration_v3.dart` - NEW (add segment_progress table)
- `lib/app/database/daos/segment_progress_dao.dart` - NEW
- `lib/app/database/app_database.dart` - MODIFY (update version to 3, add migration)
- UI files for chapter progress display (future)

**SegmentProgressDao Methods:**
```dart
class SegmentProgressDao {
  /// Mark a segment as listened
  Future<void> markListened(String bookId, int chapterIndex, int segmentIndex);
  
  /// Mark all segments in a chapter as listened
  Future<void> markChapterListened(String bookId, int chapterIndex);
  
  /// Mark all segments in a chapter as unlistened (clear progress)
  Future<void> clearChapterProgress(String bookId, int chapterIndex);
  
  /// Check if a specific segment has been listened to
  Future<bool> isSegmentListened(String bookId, int chapterIndex, int segmentIndex);
  
  /// Get progress for all chapters in a book
  /// Returns Map<chapterIndex, {total: int, listened: int}>
  Future<Map<int, ChapterProgress>> getBookProgress(String bookId);
  
  /// Get progress for a single chapter
  Future<ChapterProgress> getChapterProgress(String bookId, int chapterIndex);
  
  /// Clear all progress for a book (when resetting)
  Future<void> clearBookProgress(String bookId);
}

class ChapterProgress {
  final int totalSegments;
  final int listenedSegments;
  double get percentComplete => totalSegments > 0 
      ? (listenedSegments / totalSegments * 100) 
      : 0.0;
}
```

**Query Example (Chapter Progress):**
```sql
-- Get progress for all chapters in a book
SELECT 
  s.chapter_index,
  COUNT(*) as total_segments,
  COALESCE(COUNT(sp.segment_index), 0) as listened_segments
FROM segments s
LEFT JOIN segment_progress sp 
  ON s.book_id = sp.book_id 
  AND s.chapter_index = sp.chapter_index 
  AND s.segment_index = sp.segment_index
WHERE s.book_id = ?
GROUP BY s.chapter_index
ORDER BY s.chapter_index;
```

**UI Integration:**
- Book Details (chapters list): Show progress bar for each chapter
- Playback screen: Track segments as they complete
- Chapter options menu: "Mark as Read" / "Mark as Unread"

**Steps:**
- [x] **5.5.1** Create `migration_v3.dart` with segment_progress table
- [x] **5.5.2** Update `app_database.dart` to version 3, add migration
- [x] **5.5.3** Create `SegmentProgressDao` with all methods
- [x] **5.5.4** Create `ChapterProgress` model class
- [x] **5.5.5** Integrate with playback: Mark segment as listened when audio completes
- [x] **5.5.6** Update Book Details screen to show chapter progress bars
- [x] **5.5.7** Add "Mark Chapter Read/Unread" to chapter context menu

### Phase 5.6: Playback UX Improvements (Using SQLite Data) - COMPLETED

**Goal:** Leverage the new segment_progress tracking to improve playback UX.

**Related:** See `docs/design/playback_screen_audit.md` for full audit.

**Files modified:**
- `lib/ui/screens/playback_screen.dart`

**Steps (completed, commit 7f1958e):**
- [x] **5.6.1** Periodic progress auto-save (30-second timer)
  - Timer saves current chapter/segment position to SQLite
  - Prevents progress loss on crash or unexpected termination
- [x] **5.6.2** Time remaining display
  - Shows "Xh Ym left in chapter • Xh Ym left in book" below progress slider
  - Uses existing `ChapterProgress` and `BookProgressSummary` providers
  - Real-time updates as playback progresses

**Remaining from playback audit:**
- [ ] Chapter jump dialog from playback screen
- [ ] Bookmarks system (requires new `bookmarks` table - see Phase 8)
- [ ] Listening stats dashboard (requires new `listening_stats` table - see Phase 8)

### Phase 6: Download/Voice Manifest Migration (Package: downloads) - COMPLETED (kept as-is)

**Decision: Keep .manifest files (Option A)**

The `.manifest` files are intentionally NOT migrated to SQLite. They serve a specific purpose and
are well-suited to their current implementation:

**Why .manifest files are kept:**
1. **Atomic by design** - Written only after successful installation, ensuring consistency
2. **Collocated with assets** - Live in `voice_assets/{key}/` alongside the files they describe
3. **Self-contained** - Each voice's installation state is independent
4. **No cross-voice queries needed** - We only check "is voice X installed?" (filesystem check)
5. **Decoupled architecture** - Downloads package has no database dependency
6. **Recovery-friendly** - If manifest exists, voice is installed; simple and reliable

**What .manifest files contain:**
```json
{
  "key": "piper_en_US_lessac_medium",
  "files": ["model.onnx", "model.onnx.json", "..."],
  "installedAt": "2024-01-15T10:30:00Z",
  "checksum": "sha256:abc123..."
}
```

**How they're used:**
- `AtomicAssetManager.isInstalled(key)` → checks if `.manifest` file exists
- `AtomicAssetManager.install()` → writes `.manifest` as final step (atomic)
- `AtomicAssetManager.uninstall()` → deletes entire voice directory including manifest

**Steps (completed):**
- [x] **6.1** Decision: Keep manifests ✓
- [x] **6.2** Documented as "not migrated by design" ✓
- [x] **6.3** ~~Create VoiceInstallDao~~ → Not needed (manifests kept)

**Note:** The `downloaded_voices` table exists in the SQLite schema for fast UI queries
("show all installed voices"). This is populated by scanning manifest files on app startup
and provides a cached view for the UI, but the `.manifest` files remain the source of truth.

### Phase 7: Cleanup & Verification

- [ ] **7.1** Remove all JSON file read/write code (except .manifest if kept)
- [ ] **7.2** Remove all SharedPreferences access code from app layer
- [ ] **7.3** Remove SharedPreferences from playback package
- [ ] **7.4** Run full test suite
- [ ] **7.5** Manual testing checklist:
  - [ ] Fresh install works
  - [ ] Existing data migrates correctly
  - [ ] Add/remove books works
  - [ ] Progress saves correctly
  - [ ] Cache stats are accurate
  - [ ] Voice change clears cache
  - [ ] Settings persist across restart
  - [ ] Engine configs persist after profiling
  - [ ] Downloaded voices remain installed
- [ ] **7.6** Remove migration scripts (or keep for edge cases)
- [ ] **7.7** Update ARCHITECTURE.md to reflect SQLite storage

### Phase 8: Future SQLite Features (Planned)

These features require new SQLite tables and are planned for future implementation:

**8.1 Bookmarks System**
- New table: `bookmarks(book_id, chapter_index, segment_index, created_at, note)`
- DAO: `BookmarkDao`
- UI: Tap timestamp to create bookmark, bookmark list in playback menu
- Priority: MEDIUM

**8.2 Listening Stats Dashboard**
- New table: `listening_stats(date, total_ms, books_completed, chapters_completed)`
- Alternative: Compute from segment_progress table (no new table needed)
- DAO: `ListeningStatsDao` or extend `SegmentProgressDao`
- UI: Stats screen showing daily/weekly/total listening time
- Priority: LOW

---

## File Changes Summary

### Files to CREATE:

```
lib/app/database/
├── app_database.dart           # Singleton DB instance, pragmas
├── migrations/
│   └── migration_v1.dart       # Initial schema
└── daos/
    ├── book_dao.dart
    ├── chapter_dao.dart
    ├── segment_dao.dart          # ← NEW: text lives here
    ├── progress_dao.dart
    ├── completed_chapters_dao.dart
    ├── cache_dao.dart
    ├── settings_dao.dart
    ├── engine_config_dao.dart
    └── model_metrics_dao.dart
```

### Files to MODIFY (then delete legacy code):

| File | Modification |
|------|--------------|
| `lib/app/library_controller.dart` | Replace JSON ops with DAO calls |
| `lib/app/playback_providers.dart` | Remove metadata file, use CacheDao |
| `lib/app/settings_controller.dart` | Replace SharedPreferences with SettingsDao |
| `lib/app/config/runtime_playback_config.dart` | Use SettingsDao |
| `packages/tts_engines/lib/src/cache/intelligent_cache_manager.dart` | Replace JSON with DB queries |
| `packages/playback/lib/src/engine_config_manager.dart` | Replace SharedPreferences with EngineConfigDao |

### Files/Code to DELETE:

| Item | Location |
|------|----------|
| `library.json` read/write | `library_controller.dart` |
| `.cache_metadata.json` handling | `intelligent_cache_manager.dart` |
| `SharedPreferences` access (app) | `settings_controller.dart`, `runtime_playback_config.dart` |
| `SharedPreferences` access (playback) | `engine_config_manager.dart` |
| `_libraryFileName` constant | `library_controller.dart` |
| `metadataFile` parameter | `IntelligentCacheManager` |
| `_keyPrefix`, `_tunedPrefix` | `engine_config_manager.dart` |

### Dependencies to ADD:

```yaml
# pubspec.yaml (root)
dependencies:
  sqflite: ^2.3.0
  path: ^1.8.3  # if not already present

# Note: sqflite should be in root pubspec only
# Packages will receive Database instance via dependency injection
```

### Dependencies to REMOVE:

```yaml
# packages/playback/pubspec.yaml
# Remove shared_preferences if only used for engine_config_manager

# lib/pubspec.yaml (if no other code uses it)
# shared_preferences: ^2.x.x
```

### Package Architecture Change

**Before:** Each package manages its own persistence
```
lib/app/                     → SharedPreferences, library.json
packages/tts_engines/        → .cache_metadata.json
packages/playback/           → SharedPreferences (engine configs)
packages/downloads/          → .manifest files
```

**After:** Centralized database in app, packages receive DAOs
```
lib/app/database/            → Single SQLite database
  └── daos/                  → All DAOs
      ├── book_dao.dart
      ├── cache_dao.dart      → Injected into tts_engines
      ├── engine_config_dao.dart → Injected into playback
      └── settings_dao.dart
packages/tts_engines/        → Receives CacheDao (no file access)
packages/playback/           → Receives EngineConfigDao (no SharedPrefs)
packages/downloads/          → Keeps .manifest files (no change)
```

---

## Migration Script Execution Order

```
App Launch (first time after update)
         │
         ▼
    ┌────────────────┐
    │ Check: DB      │
    │ exists?        │
    └───────┬────────┘
            │
     NO     │     YES
     ▼      │      ▼
┌───────────────┐  └── Normal startup
│ Run One-Time  │
│ Migration     │
└───────┬───────┘
        │
        ▼
┌───────────────────────────────────────┐
│ 1. Create DB with schema             │
│ 2. Migrate library.json → books/etc  │
│ 3. Migrate .cache_metadata.json      │
│ 4. Migrate SharedPreferences (app)   │
│ 5. Migrate SharedPreferences (engine)│
│ 6. Delete old files                  │
└───────────────────────────────────────┘
        │
        ▼
    Normal startup
```

---

## Estimated Effort (Updated)

| Phase | Tasks | Effort |
|-------|-------|--------|
| 1. Infrastructure | 4 tasks | 2-3 hours |
| 2. Library | 7 tasks | 4-5 hours |
| 3. Cache | 5 tasks | 3-4 hours |
| 4. Settings | 5 tasks | 2-3 hours |
| 5. Engine Config | 4 tasks | 2 hours |
| 6. Cleanup | 6 tasks | 2 hours |

**Total: ~15-19 hours**

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Data loss during migration | Run migration in transaction, rollback on failure |
| Migration script bugs | Test with real library.json from device |
| Performance regression | Profile before/after, use batch inserts |
| Schema changes needed later | Schema versioning from day 1 |

---

## Success Criteria

- [ ] No JSON files used for persistence
- [ ] No SharedPreferences for app settings
- [ ] All queries complete in <10ms for typical operations
- [ ] "One Voice Per Book" model fully implemented
- [ ] Cache stats queries are O(1) not O(n)
- [ ] Full test suite passes
- [ ] Fresh install works
- [ ] Existing user data migrates correctly

---

## Refactoring Opportunities (Code Simplifications)

The SQLite migration enables **major code simplifications** by eliminating inefficient patterns.

### 1. Eliminate Full-Library Iteration for Single Updates

**Current Pattern** (`library_controller.dart` lines 207-283):
```dart
// Called on EVERY progress update, voice change, favorite toggle...
final updated = current.books.map((b) {
  if (b.id == bookId) {
    return b.copyWith(progress: newProgress);
  }
  return b;  // Iterate through ALL books to update ONE
}).toList();
await _saveLibrary(updated);  // Serialize entire library
```

**SQLite Replacement:**
```dart
Future<void> updateProgress(String bookId, int chapter, int segment) async {
  await db.execute('''
    UPDATE reading_progress 
    SET chapter_index = ?, segment_index = ?, updated_at = ?
    WHERE book_id = ?
  ''', [chapter, segment, DateTime.now().millisecondsSinceEpoch, bookId]);
}
```

**Impact:** 
- Remove 7+ `.map()` iteration patterns
- Remove `_saveLibrary()` completely
- Progress updates become O(1) indexed writes
- **~50 lines of repetitive code eliminated**

---

### 2. Delete Full JSON Serialization on Every Save

**Current Pattern** (`library_controller.dart` lines 76-86):
```dart
Future<void> _saveLibrary(List<Book> books) async {
  final data = {'books': books.map((b) => b.toJson()).toList()};
  await file.writeAsString(jsonEncode(data));  // Entire file rewritten
}
```

**SQLite Replacement:**
- Individual `INSERT/UPDATE/DELETE` statements
- No serialization
- No full file rewrites
- Atomic transactions for batch operations

**Impact:**
- Remove `_saveLibrary()` method entirely
- Remove `_loadLibrary()` JSON parsing
- Remove `book.toJson()` / `Book.fromJson()` usage for persistence
- **Faster progress saves (ms vs 50-100ms for large libraries)**

---

### 3. Simplify Cache Statistics (Kill Full Scans)

**Current Pattern** (`intelligent_cache_manager.dart` lines 157-182):
```dart
Future<CacheUsageStats> getUsageStats() async {
  final byBook = <String, int>{};
  final byVoice = <String, int>{};
  var compressedCount = 0;

  for (final entry in _metadata.values) {  // Full iteration
    byBook[entry.bookId] = (byBook[entry.bookId] ?? 0) + entry.sizeBytes;
    byVoice[entry.voiceId] = (byVoice[entry.voiceId] ?? 0) + entry.sizeBytes;
    if (entry.key.endsWith('.m4a')) compressedCount++;
  }
  
  final totalSize = await getTotalSize();  // Another filesystem scan
  // ...
}
```

**SQLite Replacement:**
```dart
Future<CacheUsageStats> getUsageStats() async {
  final byBook = await db.rawQuery('''
    SELECT book_id, SUM(size_bytes) as total FROM cache_entries GROUP BY book_id
  ''');
  
  final compressedCount = Sqflite.firstIntValue(await db.rawQuery('''
    SELECT COUNT(*) FROM cache_entries WHERE is_compressed = 1
  '''));
  
  final totalSize = Sqflite.firstIntValue(await db.rawQuery('''
    SELECT SUM(size_bytes) FROM cache_entries
  '''));
  
  return CacheUsageStats(
    totalSizeBytes: totalSize ?? 0,
    byBook: Map.fromEntries(byBook.map((r) => MapEntry(r['book_id'], r['total']))),
    compressedCount: compressedCount ?? 0,
  );
}
```

**Impact:**
- Remove in-memory `_metadata` map
- Remove full iteration loops
- Remove `_loadMetadata()` / `_saveMetadata()` methods
- **O(n) scans → O(1) aggregation queries**

---

### 4. Eliminate In-Memory Eviction Sorting

**Current Pattern** (`intelligent_cache_manager.dart` lines 260-273):
```dart
// Must load all entries, score them, sort in memory
final scoredEntries = _metadata.values.map((m) {
  var score = _scoreCalculator.calculateScore(m, ctx);
  if (m.key.endsWith('.wav')) score *= 0.5;
  return ScoredCacheEntry(metadata: m, score: score);
}).toList();

scoredEntries.sortByEvictionPriority();  // O(n log n) in RAM
```

**SQLite Replacement:**
```dart
Future<List<CacheEntry>> getLRUCandidates(int limit) async {
  // Let the database handle scoring and sorting!
  return await db.query('cache_entries',
    orderBy: '''
      CASE WHEN is_pinned = 1 THEN 1 ELSE 0 END,
      last_accessed_at ASC,
      access_count ASC,
      CASE WHEN is_compressed = 0 THEN 0 ELSE 1 END
    ''',
    limit: limit,
    where: 'is_pinned = 0',
  );
}
```

**Impact:**
- Remove `ScoredCacheEntry` class
- Remove `ScoreCalculator` class  
- Remove in-memory sorting
- **Memory usage drops significantly for large caches**

---

### 5. Delete Filesystem-Metadata Sync Complexity

**Current Pattern** (`intelligent_cache_manager.dart` lines 662-740):
```dart
Future<void> _syncWithFileSystem() async {
  final existingFiles = <String, File>{};
  await for (final entity in _cacheDir.list()) {  // Full dir scan
    existingFiles[entity.uri.pathSegments.last] = entity;
  }

  // O(n) check for stale entries
  final toRemove = <String>[];
  for (final key in _metadata.keys) {
    if (!existingFiles.containsKey(key)) toRemove.add(key);
  }
  // ... 80 more lines of sync logic
}
```

**SQLite Replacement:**
```dart
// Sync happens automatically - DB is source of truth
// Only check filesystem when actually needed (e.g., on eviction)
Future<void> verifyEntryExists(CacheEntry entry) async {
  final file = File(entry.filePath);
  if (!await file.exists()) {
    await db.delete('cache_entries', where: 'id = ?', whereArgs: [entry.id]);
  }
}
```

**Impact:**
- Remove `_syncWithFileSystem()` entirely (80+ lines)
- Database becomes single source of truth
- Only verify files when actually accessing them
- **Startup time dramatically faster**

---

### 6. Simplify Settings State Management

**Current Pattern** (`settings_controller.dart`):
```dart
// Multiple async calls to SharedPreferences
Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final darkMode = prefs.getBool('dark_mode') ?? false;
  final selectedVoice = prefs.getString('selected_voice');
  final autoAdvance = prefs.getBool('auto_advance_chapters') ?? true;
  // ... 15 more getters
}

// Each setter does individual save
Future<void> setDarkMode(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('dark_mode', value);
  state = state.copyWith(darkMode: value);
}
```

**SQLite Replacement:**
```dart
Future<SettingsState> loadAllSettings() async {
  final rows = await db.query('settings');
  final map = Map.fromEntries(rows.map((r) => 
    MapEntry(r['key'] as String, jsonDecode(r['value'] as String))
  ));
  return SettingsState.fromMap(map);
}

Future<void> setSetting(String key, dynamic value) async {
  await db.insert('settings', {
    'key': key, 
    'value': jsonEncode(value),
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
```

**Impact:**
- Remove individual getter/setter pairs
- Single `loadAllSettings()` call on startup
- Generic `setSetting()` for all values
- **~100 lines of boilerplate eliminated**

---

### 7. Remove "Multiple Sources of Truth" Problem

**Current Problem:**
- `SharedPreferences` holds settings
- `library.json` holds books/progress
- `.cache_metadata.json` holds cache index
- In-memory `_metadata` map
- In-memory `SegmentReadinessTracker` singleton
- Filesystem (actual audio files)

**All must be kept in sync manually!**

**SQLite Solution:**
- **Single source of truth**: SQLite database
- All reads query the database
- All writes update the database
- No in-memory caches to invalidate
- No JSON files to keep in sync

**Impact:**
- Delete `_metadata` in-memory map
- Delete `SegmentReadinessTracker.instance` singleton (query DB instead)
- Delete manual sync code
- **Eliminates entire category of "stale state" bugs**

---

### Summary: Lines of Code Impact

| File | Estimated Lines Deleted | Reason |
|------|------------------------|--------|
| `library_controller.dart` | ~150 lines | Remove JSON load/save, iteration patterns |
| `intelligent_cache_manager.dart` | ~200 lines | Remove metadata map, sync, scoring |
| `settings_controller.dart` | ~80 lines | Remove individual SharedPreferences accessors |
| `runtime_playback_config.dart` | ~50 lines | Consolidate into settings table |

**Total: ~480 lines of complex persistence code → ~150 lines of DAO methods**

### New Clean Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         App Layer                                │
│  LibraryController, SettingsController, CacheManager            │
└──────────────────────────────┬──────────────────────────────────┘
                               │ uses
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                          DAO Layer                               │
│  BookDao, ChapterDao, CacheDao, SettingsDao                     │
│  (clean interfaces, one responsibility each)                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │ queries
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SQLite (sqflite)                         │
│  Single source of truth, indexed, transactional                 │
└─────────────────────────────────────────────────────────────────┘
```

