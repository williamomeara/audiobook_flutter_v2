import 'package:sqflite/sqflite.dart';

/// Consolidated database schema for audiobook_flutter_v2
///
/// This single migration creates the complete final schema,
/// combining what would have been V1-V6 into one initial schema.
///
/// Pre-release optimization: Since no production users exist,
/// we consolidate 6 migrations into 1 comprehensive schema creation.
///
/// Tables: 13 total
/// Indexes: 9 total
class MigrationConsolidated {
  static Future<void> up(Database db) async {
    // Create schema_version table (for migration tracking)
    await db.execute('''
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL,
        description TEXT
      )
    ''');

    // ============ CORE LIBRARY TABLES ============

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

    // Book chapters
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        segment_count INTEGER NOT NULL,
        word_count INTEGER,
        char_count INTEGER,
        estimated_duration_ms INTEGER,
        is_playable INTEGER DEFAULT 1 NOT NULL,
        UNIQUE(book_id, chapter_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // Chapter chapters (text content)
    await db.execute('''
      CREATE TABLE segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        char_count INTEGER NOT NULL,
        estimated_duration_ms INTEGER NOT NULL,
        segment_type TEXT DEFAULT 'text',
        metadata_json TEXT,
        UNIQUE(book_id, chapter_index, segment_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // ============ PLAYBACK POSITION TRACKING ============

    // Book-level progress (kept for compatibility, but deprecated)
    await db.execute('''
      CREATE TABLE reading_progress (
        book_id TEXT PRIMARY KEY,
        chapter_index INTEGER NOT NULL DEFAULT 0,
        segment_index INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER,
        total_listen_time_ms INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // Chapter-level position tracking (primary position source)
    await db.execute('''
      CREATE TABLE chapter_positions (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // Segment-level listening history
    await db.execute('''
      CREATE TABLE segment_progress (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        listened_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter_index, segment_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // Completed chapter tracking
    await db.execute('''
      CREATE TABLE completed_chapters (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        completed_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // ============ AUDIO CACHING ============

    // Audio file cache metadata
    await db.execute('''
      CREATE TABLE cache_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        duration_ms INTEGER,
        is_compressed INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL,
        access_count INTEGER DEFAULT 1,
        engine_type TEXT,
        voice_id TEXT,
        compression_state TEXT DEFAULT 'wav',
        compression_started_at INTEGER,
        UNIQUE(book_id, chapter_index, segment_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // ============ SETTINGS & CONFIGURATION ============

    // Application settings (key-value store)
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // TTS engine configuration (per-engine settings)
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

    // TTS model performance metrics
    await db.execute('''
      CREATE TABLE model_metrics (
        model_id TEXT PRIMARY KEY,
        engine_id TEXT NOT NULL,
        avg_latency_ms INTEGER,
        avg_chars_per_second REAL,
        total_syntheses INTEGER DEFAULT 0,
        total_chars_synthesized INTEGER DEFAULT 0,
        last_used_at INTEGER,
        FOREIGN KEY(engine_id) REFERENCES engine_configs(engine_id)
      )
    ''');

    // Downloaded voice models tracking
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

    // ============ INDEXES FOR QUERY OPTIMIZATION ============

    // Chapters lookup
    await db.execute('CREATE INDEX idx_chapters_book ON chapters(book_id)');

    // Segments lookup
    await db.execute(
        'CREATE INDEX idx_segments_book_chapter ON segments(book_id, chapter_index)');

    // Cache lookups
    await db.execute('CREATE INDEX idx_cache_book ON cache_entries(book_id)');
    await db.execute(
        'CREATE INDEX idx_cache_book_chapter ON cache_entries(book_id, chapter_index)');
    await db.execute(
        'CREATE INDEX idx_cache_accessed ON cache_entries(last_accessed_at)');
    await db.execute(
        'CREATE INDEX idx_cache_file_path ON cache_entries(file_path)');

    // Model metrics lookup
    await db.execute(
        'CREATE INDEX idx_model_engine ON model_metrics(engine_id)');

    // Segment progress lookup
    await db.execute(
        'CREATE INDEX idx_segment_progress_chapter ON segment_progress(book_id, chapter_index)');

    // Chapter positions lookup (filtered)
    await db.execute(
        'CREATE INDEX idx_chapter_positions_primary ON chapter_positions(book_id) WHERE is_primary = 1');

    // ============ RECORD SCHEMA VERSION ============

    // Record that we've created the schema
    await db.insert('schema_version', {
      'version': 6,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
      'description': 'Consolidated schema (V1-V6 merged for pre-release)',
    });
  }
}
