import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations/cache_migration_service.dart';
import 'migrations/json_migration_service.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';
import 'migrations/migration_v3.dart';
import 'migrations/migration_v4.dart';
import 'migrations/migration_v5.dart';
import 'migrations/settings_migration_service.dart';

/// Singleton database instance for the Eist audiobook app.
///
/// Uses WAL mode for concurrent read/write performance and includes
/// schema versioning for future migrations.
///
/// Usage:
/// ```dart
/// final db = await AppDatabase.instance;
/// final books = await db.query('books');
/// ```
class AppDatabase {
  static Database? _database;
  static const String _dbName = 'eist_audiobook.db';
  static const int _dbVersion = 5;

  // Private constructor to prevent instantiation
  AppDatabase._();

  /// Get the singleton database instance.
  /// Creates and initializes the database on first access.
  static Future<Database> get instance async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database with optimal mobile settings.
  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
      onConfigure: _onConfigure,
    );
  }

  /// Configure database connection settings before opening.
  /// Called before onCreate/onUpgrade/onOpen and OUTSIDE of any transaction.
  /// This is the correct place for PRAGMA settings that cannot run in transactions.
  /// NOTE: Use rawQuery for PRAGMA statements, not execute.
  static Future<void> _onConfigure(Database db) async {
    // Enable foreign key constraints
    await db.rawQuery('PRAGMA foreign_keys = ON');
    // WAL mode MUST be set here, not in onCreate (which runs in a transaction)
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA synchronous = NORMAL');
    await db.rawQuery('PRAGMA cache_size = -2000'); // 2MB cache
  }

  /// Create initial database schema.
  static Future<void> _onCreate(Database db, int version) async {
    // Note: Pragmas are set in _onConfigure, not here (onCreate runs in a transaction)

    // Create all tables
    await MigrationV1.up(db);
    await MigrationV2.up(db);
    await MigrationV3.up(db);
    // Note: MigrationV4 added content_confidence columns, MigrationV5 removes them
    // For new databases, we skip adding them entirely by not running V4
    // and calling V5 which handles the case gracefully

    // Record schema version
    await db.insert('schema_version', {
      'version': version,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
      'description': 'Initial schema (content confidence feature removed)',
    });
  }

  /// Handle schema upgrades for future versions.
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await MigrationV2.up(db);
      await db.insert('schema_version', {
        'version': 2,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
        'description': 'Add cache metadata extensions (access_count, engine_type, voice_id)',
      });
    }
    if (oldVersion < 3) {
      await MigrationV3.up(db);
      await db.insert('schema_version', {
        'version': 3,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
        'description': 'Add segment progress tracking for per-segment listening history',
      });
    }
    if (oldVersion < 4) {
      await MigrationV4.up(db);
      await db.insert('schema_version', {
        'version': 4,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
        'description': 'Add content confidence scoring for smart chapter detection',
      });
    }
    if (oldVersion < 5) {
      await MigrationV5.up(db);
      await db.insert('schema_version', {
        'version': 5,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
        'description': 'Remove content confidence columns (feature removed)',
      });
    }
  }

  /// Called each time the database is opened.
  /// Runs any pending migrations (WAL mode already set in _onConfigure).
  static Future<void> _onOpen(Database db) async {
    // Note: WAL mode is set in _onConfigure, no need to re-apply here

    // Check and run JSON migrations if needed
    if (await JsonMigrationService.needsMigration(db)) {
      if (kDebugMode) debugPrint('Running library.json migration...');
      final count = await JsonMigrationService.migrate(db);
      if (kDebugMode) debugPrint('Migration complete: $count books migrated');
    }

    // Check and run cache metadata migration if needed
    if (await CacheMigrationService.needsMigration(db)) {
      if (kDebugMode) debugPrint('Running cache metadata migration...');
      final count = await CacheMigrationService.migrate(db);
      if (kDebugMode) debugPrint('Cache migration complete: $count entries migrated');
    }

    // Check and run settings migration if needed
    if (await SettingsMigrationService.needsMigration(db)) {
      if (kDebugMode) debugPrint('Running settings migration...');
      final count = await SettingsMigrationService.migrate(db);
      if (kDebugMode) debugPrint('Settings migration complete: $count settings migrated');
    }
  }

  /// Close the database connection.
  /// Typically called when the app is terminated.
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Batch insert helper for optimal performance during migrations.
  ///
  /// Groups inserts into transactions of [batchSize] rows to balance
  /// performance and memory usage.
  static Future<void> batchInsert(
    Database db,
    String table,
    List<Map<String, dynamic>> rows, {
    int batchSize = 500,
  }) async {
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.skip(i).take(batchSize).toList();
      await db.transaction((txn) async {
        final dbBatch = txn.batch();
        for (final row in batch) {
          dbBatch.insert(table, row);
        }
        await dbBatch.commit(noResult: true);
      });
    }
  }

  /// Execute multiple statements in a single transaction.
  /// Returns true if all statements succeed.
  static Future<bool> executeInTransaction(
    Database db,
    List<Future<void> Function(Transaction txn)> operations,
  ) async {
    try {
      await db.transaction((txn) async {
        for (final operation in operations) {
          await operation(txn);
        }
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get the database file path (useful for debugging/export).
  static Future<String> getDatabasePath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, _dbName);
  }

  /// Check if the database file exists.
  static Future<bool> exists() async {
    final path = await getDatabasePath();
    return databaseExists(path);
  }

  /// Delete the database file (use with caution - for testing/reset only).
  static Future<void> deleteDatabase() async {
    await close();
    final path = await getDatabasePath();
    await databaseFactory.deleteDatabase(path);
  }
}
