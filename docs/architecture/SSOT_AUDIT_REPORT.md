# Single Source of Truth (SSOT) Audit Report

**Date:** January 29, 2026  
**Scope:** All persistence mechanisms in audiobook_flutter_v2

---

## Summary

✅ **SQLite is the Single Source of Truth** for all application data.

The codebase correctly follows SSOT principles. This audit identified:
- **0 violations** of SSOT
- **1 intentional dual-write** (dark_mode for startup performance)
- **1 legacy system** kept for migration only

---

## Persistence Mechanisms Inventory

### 1. SQLite Database (`eist_audiobook.db`) ✅ PRIMARY SSOT

All structured data is stored in SQLite:

| Table | Purpose | DAO |
|-------|---------|-----|
| `books` | Book metadata | `BookDao` |
| `chapters` | Chapter content | `ChapterDao` |
| `segments` | TTS text segments | `SegmentDao` |
| `reading_progress` | Per-book progress | `ProgressDao` |
| `chapter_positions` | Resume positions | `ChapterPositionDao` |
| `cache_entries` | Audio cache metadata | `CacheDao` |
| `settings` | App settings | `SettingsDao` |
| `completed_chapters` | Completion tracking | `CompletedChaptersDao` |
| `downloaded_voices` | Voice model metadata | `DownloadedVoicesDao` |
| `model_metrics` | TTS performance data | `ModelMetricsDao` |

### 2. SharedPreferences ❌ REMOVED

**SharedPreferences has been completely removed in favor of SQLite-only storage.**

Previously, `dark_mode` was cached in SharedPreferences for instant startup theme loading.
This has been refactored with `QuickSettingsService` now preloading `dark_mode` directly from SQLite.

**Current flow:**
1. App startup calls `QuickSettingsService.initialize()` before rendering
2. This loads `dark_mode` from SQLite and caches it in memory
3. UI uses cached value for instant theme application
4. SQLite remains the single source of truth

**Benefits:**
- No dual-write complexity
- No SharedPreferences dependency
- Cleaner SSOT implementation

### 3. JSON Files 📦 MIGRATION ONLY (LEGACY)

| File | Purpose | Status |
|------|---------|--------|
| `library.json` | Legacy book storage | **Migrated to SQLite** |
| `.cache_metadata.json` | Legacy cache index | **Migrated to SQLite** |

These files are:
- Read one-time during migration to SQLite (if they exist)
- Backed up as `.migrated` files after successful migration
- Never written to in production
- `JsonCacheMetadataStorage` class was removed - migration logic moved to `CacheMigrationService`

### 4. Marker/Manifest Files ✅ NOT DATA PERSISTENCE

| File | Purpose |
|------|---------|
| `.manifest` | Download verification marker |
| `.ready` | Download completion marker |

These are operational markers, not data persistence. They don't duplicate SQLite data.

### 5. In-Memory Caches ✅ CORRECTLY SYNCED

| Class | Cache | Sync Method |
|-------|-------|-------------|
| `IntelligentCacheManager` | `_metadata` map | Loaded from `_storage` on `initialize()`, all mutations call `_storage.upsertEntry()` or `_storage.removeEntries()` |
| `JsonCacheMetadataStorage` | `_entriesCache` | In-memory cache of its own JSON file (legacy) |

---

## Potential Risk Areas (All Verified Safe)

### 1. IntelligentCacheManager._metadata

The in-memory `_metadata` map mirrors the SQLite `cache_entries` table.

**Finding:** All mutations to `_metadata` are paired with storage calls:
- `registerEntry()` → calls `_storage.upsertEntry(entry)`
- `evictIfNeeded()` → calls `_storage.removeEntries(evictedKeys)` after batch removal
- `compressEntryByFilename()` → calls `_storage.replaceEntry()` for atomic WAV→M4A swap

**Verdict:** ✅ Safe - SQLite remains SSOT

### 2. RuntimePlaybackConfig.synthesisStrategyState

Learned TTS performance data (RTF values) is persisted in SQLite via `SettingsDao`:

```dart
// RuntimePlaybackConfig.load()
final configMap = await settingsDao.getSetting<Map<String, dynamic>>(
  SettingsKeys.runtimePlaybackConfig,
);
```

**Verdict:** ✅ Safe - SQLite is SSOT

### 3. Compression State Tracking

Recent refactor (commit 1b6a0d2) introduced `CompressionState` enum:

```dart
enum CompressionState { wav, compressing, m4a, failed }
```

**Finding:** Counts are derived from `cache_entries.compression_state` column, not file extensions. Recent fix (commit 5f3428b) corrected `getCompressedCount()` to use DB state.

**Verdict:** ✅ Safe - DB is SSOT for compression state

---

## Recommendations

### Already Implemented ✅

1. **SQLite as SSOT** - All settings, books, cache metadata in one database
2. **SQLite-only settings** - Removed SharedPreferences dependency; `QuickSettingsService` now preloads from SQLite
3. **Removed legacy JSON storage** - `JsonCacheMetadataStorage` deleted; migration logic consolidated in `CacheMigrationService`
4. **Migration services** - One-time migration from JSON to SQLite with automatic backup
5. **Compression state in DB** - `compression_state` column is authoritative
6. **SSOT consistency tests** - Added `ssot_consistency_test.dart` for cache/settings validation
7. **Performance metrics** - Added `SsotMetrics` for database query latency tracking
8. **Recovery documentation** - Created `SSOT_RECOVERY_GUIDE.md` with disaster recovery procedures

### Recently Implemented ✨

1. **Remove legacy JSON storage classes** ✅ - `JsonCacheMetadataStorage` deleted
   - Migration logic moved directly into `CacheMigrationService`
   - Tests updated to use `MockCacheMetadataStorage` instead
   - All imports and dependencies removed

2. **Remove SharedPreferences package** ✅ - SQLite-only implementation completed
   - `QuickSettingsService` now preloads `dark_mode` from SQLite at startup
   - Eliminates dual-write complexity and SharedPreferences dependency
   - Maintains instant theme loading by caching dark_mode in memory

### Future Considerations

3. **Implement SSOT consistency validation tests**
   - Automated tests to verify in-memory caches (`IntelligentCacheManager._metadata`) match SQLite state after operations
   - Add integrity checks in CI/CD to detect SSOT violations early
   - Test simulated database failures and verify fallback behavior

4. **Monitor SSOT performance metrics**
   - Track database query latency (especially for frequently-accessed settings and cache metadata)
   - Alert if SQLite becomes a bottleneck during concurrent downloads/compression
   - Consider read replicas or connection pooling if performance issues emerge

5. **Document fallback and recovery procedures**
   - What happens if SQLite database file is corrupted
   - How to rebuild cache metadata from disk files if needed
   - Backup strategy for user library data

6. **Add feature flags for zero-downtime migrations**
   - If future schema changes are needed, use feature flags to coordinate app versions
   - Prevents data loss during migrations to new table structures

---

## Files Reviewed

- `lib/app/database/` - All DAOs and AppDatabase
- `lib/app/settings_controller.dart` - Settings persistence
- `lib/app/quick_settings_service.dart` - SharedPreferences usage
- `lib/app/config/runtime_playback_config.dart` - Runtime config persistence
- `packages/tts_engines/lib/src/cache/` - Cache persistence
- `packages/downloads/lib/src/` - Download manifests
- `lib/app/database/migrations/` - Migration services
