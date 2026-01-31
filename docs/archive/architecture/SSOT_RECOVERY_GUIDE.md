# SSOT Recovery Guide

This guide covers procedures for recovering from SQLite database failures or corruption, and restoring data consistency in the audiobook application.

## Overview

The application follows a Single Source of Truth (SSOT) architecture where SQLite (`eist_audiobook.db`) is the authoritative store for all application data. This guide explains recovery procedures when SQLite is corrupted or inaccessible.

---

## Quick Recovery Checklist

| Scenario | Action | Data Loss |
|----------|--------|-----------|
| Database won't open | Delete `eist_audiobook.db` | Books/progress need re-import |
| Corrupted tables | Run database repair (see below) | None if repair succeeds |
| Lost settings | Restore from backup | Last backup only |
| Cache metadata corrupted | Rebuild from disk files | None - rebuilt automatically |
| SharedPreferences out of sync | Sync dark_mode from SQLite | None |

---

## Recovery Procedures

### 1. Database Corruption Detection

**Symptoms:**
- "database disk image malformed" errors
- App crashes when accessing settings or book data
- Database queries fail with SQL exceptions

**Diagnosis:**
```bash
# On development machine, check database integrity
sqlite3 eist_audiobook.db ".integrity_check"

# Or in Flutter, use this diagnostic code:
try {
  final result = await database.rawQuery('PRAGMA integrity_check');
  if (result.isNotEmpty && result[0]['integrity_check'] != 'ok') {
    // Database is corrupted
  }
} catch (e) {
  // Database cannot be opened
}
```

### 2. Database Rebuild (Hard Reset)

**When to use:** Database file is corrupted and cannot be opened.

**Data recovered:** None (starts fresh)

**Steps:**

1. **Delete corrupted database:**
   ```dart
   // In your database initialization code:
   final databasesPath = await getDatabasesPath();
   final dbPath = join(databasesPath, 'eist_audiobook.db');
   final file = File(dbPath);

   if (await file.exists()) {
     await file.delete();
   }
   ```

2. **Trigger re-migration:**
   - App will detect missing database and run `migration_service.dart`
   - If `library.json` exists, books will be re-imported
   - If `.cache_metadata.json` exists, cache metadata will be rebuilt

3. **Restore user data:**
   - Users must re-import books if no migration files exist
   - Cache will be rebuilt as users synthesize audio

4. **Verify recovery:**
   ```dart
   // Check database is accessible
   final books = await database.bookDao.getAllBooks();
   expect(books, isNotEmpty);
   ```

### 3. Database Repair (Soft Recovery)

**When to use:** Database can be opened but has integrity issues.

**Data recovered:** Most data (usually 100%)

**Steps:**

1. **Enable recovery mode:**
   ```dart
   // Before opening database, run PRAGMA recovery
   final db = await openDatabase(dbPath);
   try {
     // Attempt recovery
     await db.rawQuery('PRAGMA recovery_mode = 1');
     await db.rawQuery('VACUUM');

     // Verify integrity
     final result = await db.rawQuery('PRAGMA integrity_check');
     final isOk = result.isNotEmpty &&
                  result[0]['integrity_check'] == 'ok';

     if (!isOk) {
       throw Exception('Database integrity check failed');
     }
   } finally {
     await db.close();
   }
   ```

2. **Rebuild indices (optional):**
   ```dart
   await db.rawQuery('REINDEX');
   ```

3. **Re-open database:**
   The database should now be accessible with minimal data loss.

### 4. Cache Metadata Rebuild

**When to use:** Cache entries table is corrupted but audio files exist on disk.

**Data recovered:** Complete (rebuilt from actual files)

**Steps:**

1. **Delete cache_entries table:**
   ```dart
   await database.rawQuery('DELETE FROM cache_entries');
   ```

2. **Trigger sync with filesystem:**
   ```dart
   // In IntelligentCacheManager:
   await manager.initialize();  // Calls _syncWithFileSystem()
   ```

3. **Verify cache entries:**
   ```dart
   final entries = await database.cacheDao.getEntriesByFilePath();
   expect(entries.isNotEmpty, isTrue);
   ```

### 5. Settings Consistency Sync

**When to use:** SharedPreferences and SQLite are out of sync.

**Data recovered:** From SQLite (source of truth)

**Steps:**

1. **Sync dark_mode from SQLite:**
   ```dart
   // In SettingsController.setDarkMode():
   final dbValue = await _settingsDao.getBool(SettingsKeys.darkMode);
   await QuickSettingsService.instance.syncFromSqlite(dbValue);
   ```

2. **Verify sync:**
   ```dart
   final dbValue = await _settingsDao.getBool(SettingsKeys.darkMode);
   final spValue = QuickSettingsService.instance.darkMode;
   expect(dbValue, equals(spValue));
   ```

---

## Prevention Strategies

### 1. Regular Backups

Implement automatic backup of `eist_audiobook.db` to:
- Cloud storage (Google Drive, iCloud)
- External USB storage
- Network drive

**Backup schedule:** Daily or after each app session

**Backup code example:**
```dart
class DatabaseBackupService {
  static Future<void> backupDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final source = File(join(databasesPath, 'eist_audiobook.db'));

      if (!await source.exists()) return;

      // Example: Copy to Documents/backups/
      final backupDir = Directory('${appDir.path}/backups');
      await backupDir.create(recursive: true);

      final timestamp = DateTime.now().toIso8601String();
      final dest = File('${backupDir.path}/eist_audiobook_$timestamp.db');

      await source.copy(dest.path);

      logger.info('Database backed up to ${dest.path}');
    } catch (e) {
      logger.error('Backup failed: $e');
    }
  }
}
```

### 2. Transaction Safety

Ensure all multi-step operations use transactions:

```dart
// ✅ Good: Atomic operation
await database.transaction((txn) async {
  await txn.insert('books', bookData);
  await txn.insert('chapters', chapterData);
  // Both succeed or both rollback
});

// ❌ Bad: Non-atomic
await database.insert('books', bookData);
await database.insert('chapters', chapterData);
// If second fails, book is orphaned
```

### 3. Integrity Checks

Run periodic integrity checks:

```dart
class DatabaseHealthMonitor {
  static Future<bool> isHealthy() async {
    try {
      final result = await database.rawQuery('PRAGMA integrity_check');
      return result.isNotEmpty &&
             result[0]['integrity_check'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  static Future<void> monitorPeriodically() async {
    while (true) {
      await Future.delayed(const Duration(hours: 1));
      final healthy = await isHealthy();
      if (!healthy) {
        logger.error('Database integrity check failed!');
        // Trigger user notification or recovery
      }
    }
  }
}
```

### 4. WAL Mode for Better Durability

SQLite is configured with WAL (Write-Ahead Logging) mode in `app_database.dart`:

```dart
// Already enabled in config:
// - Prevents corruption from sudden app crashes
// - Multiple readers while writing
// - Faster writes
// - Checkpoint happens automatically
```

---

## Testing Recovery Procedures

### Simulate Database Corruption

```dart
void main() {
  group('Database Recovery', () {
    test('can recover from corrupted database', () async {
      // 1. Corrupt the database
      final dbPath = join(await getDatabasesPath(), 'eist_audiobook.db');
      final file = File(dbPath);
      await file.writeAsBytes([1, 2, 3]); // Invalid data

      // 2. Attempt recovery
      final shouldRecreate = !await isValidDatabase(dbPath);
      if (shouldRecreate) {
        await file.delete();
        await initializeDatabase();
      }

      // 3. Verify recovery
      final books = await database.bookDao.getAllBooks();
      expect(books, isNotEmpty);
    });
  });
}
```

---

## When to Involve User

**Automatic recovery (no user intervention needed):**
- Cache metadata corrupted → Rebuilt from files
- Settings out of sync → Resync from SQLite
- Database file missing → Recreated on first run

**Requires user action:**
- Books lost → User re-imports books
- Reading progress lost → User continues from last saved position
- Cache cleared → User re-synthesizes audio files

**Communication template:**
```
"We detected an issue with your data. Your library has been restored,
but audio cache needs to be regenerated. This will happen automatically
as you listen. (No data loss)"
```

---

## Monitoring in Production

### Key Metrics to Track

1. **Database health:**
   - PRAGMA integrity_check results
   - Query error rates
   - Slow query detection (>100ms)

2. **Sync consistency:**
   - SharedPreferences ↔ SQLite mismatches
   - Cache metadata ↔ filesystem mismatches

3. **Recovery attempts:**
   - Count of database rebuilds
   - Count of migrations triggered
   - Success rate of recoveries

### Example Monitoring Code

```dart
Future<void> monitorSsotHealth() async {
  final metrics = {
    'db_integrity': await checkIntegrity(),
    'cache_consistency': await checkCacheConsistency(),
    'settings_sync': await checkSettingsSync(),
    'slow_queries': SsotMetrics.getQueryMetrics(),
  };

  // Send to analytics/monitoring service
  await analytics.recordEvent('ssot_health', metrics);

  // Alert if issues detected
  for (final entry in metrics.entries) {
    if (entry.value == false) {
      logger.error('SSOT health issue: ${entry.key}');
      // Trigger recovery or user notification
    }
  }
}
```

---

## Related Documentation

- [SSOT Architecture Overview](./SSOT_AUDIT_REPORT.md)
- [Database Schema](./DATABASE_SCHEMA.md)
- [Migration Services](../../lib/app/database/migrations/)

