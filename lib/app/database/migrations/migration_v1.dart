import 'package:sqflite/sqflite.dart';

/// Initial database schema (version 1).
///
/// Creates all core tables for the Eist audiobook app:
/// - books: Library of imported books
/// - chapters: Chapter metadata (no content)
/// - segments: Pre-segmented text (content lives here)
/// - reading_progress: Current position per book
/// - completed_chapters: Tracks finished chapters
/// - cache_entries: Audio cache metadata
/// - settings: App configuration
/// - engine_configs: TTS engine calibration
/// - model_metrics: Per-model performance data
/// - downloaded_voices: Installed voice models
/// - schema_version: Migration tracking
class MigrationV1 {
  /// Apply the initial schema.
  static Future<void> up(Database db) async {
    // Schema version tracking
    await db.execute('''
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL,
        description TEXT
      )
    ''');

    // Books library
    await db.execute('''
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
      )
    ''');

    // Chapters (metadata only - no content, segments have the text)
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        segment_count INTEGER NOT NULL,
        word_count INTEGER,
        char_count INTEGER,
        estimated_duration_ms INTEGER,
        UNIQUE(book_id, chapter_index)
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_chapters_book ON chapters(book_id)');

    // Segments (pre-segmented at import - text lives here)
    await db.execute('''
      CREATE TABLE segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        char_count INTEGER NOT NULL,
        estimated_duration_ms INTEGER NOT NULL,
        UNIQUE(book_id, chapter_index, segment_index)
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_segments_book_chapter ON segments(book_id, chapter_index)');

    // Reading progress (one per book)
    await db.execute('''
      CREATE TABLE reading_progress (
        book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL DEFAULT 0,
        segment_index INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER,
        total_listen_time_ms INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Completed chapters
    await db.execute('''
      CREATE TABLE completed_chapters (
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL,
        completed_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter_index)
      )
    ''');

    // Cache entries (NO voice_id - voice is per-book, not per-entry)
    await db.execute('''
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
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_cache_book ON cache_entries(book_id)');
    await db.execute(
        'CREATE INDEX idx_cache_book_chapter ON cache_entries(book_id, chapter_index)');
    await db.execute(
        'CREATE INDEX idx_cache_accessed ON cache_entries(last_accessed_at)');

    // Settings (key-value store for app configuration)
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Engine configuration and calibration
    await db.execute('''
      CREATE TABLE engine_configs (
        engine_id TEXT PRIMARY KEY,
        device_tier TEXT,
        max_concurrency INTEGER DEFAULT 1,
        buffer_ahead_count INTEGER DEFAULT 5,
        prefer_compression INTEGER DEFAULT 0,
        avg_synthesis_time_ms INTEGER,
        last_calibrated_at INTEGER,
        config_json TEXT
      )
    ''');

    // Per-model performance metrics
    await db.execute('''
      CREATE TABLE model_metrics (
        model_id TEXT PRIMARY KEY,
        engine_id TEXT NOT NULL REFERENCES engine_configs(engine_id),
        avg_latency_ms INTEGER,
        avg_chars_per_second REAL,
        total_syntheses INTEGER DEFAULT 0,
        total_chars_synthesized INTEGER DEFAULT 0,
        last_used_at INTEGER
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_model_engine ON model_metrics(engine_id)');

    // Downloaded voice models
    await db.execute('''
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
      )
    ''');
  }

  /// Rollback the initial schema (for testing).
  static Future<void> down(Database db) async {
    await db.execute('DROP TABLE IF EXISTS downloaded_voices');
    await db.execute('DROP TABLE IF EXISTS model_metrics');
    await db.execute('DROP TABLE IF EXISTS engine_configs');
    await db.execute('DROP TABLE IF EXISTS settings');
    await db.execute('DROP TABLE IF EXISTS cache_entries');
    await db.execute('DROP TABLE IF EXISTS completed_chapters');
    await db.execute('DROP TABLE IF EXISTS reading_progress');
    await db.execute('DROP TABLE IF EXISTS segments');
    await db.execute('DROP TABLE IF EXISTS chapters');
    await db.execute('DROP TABLE IF EXISTS books');
    await db.execute('DROP TABLE IF EXISTS schema_version');
  }
}
