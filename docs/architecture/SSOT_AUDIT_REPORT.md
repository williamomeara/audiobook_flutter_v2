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

### 2. SharedPreferences ⚠️ INTENTIONAL DUAL-WRITE

**Only `dark_mode` is stored in SharedPreferences.**

This is intentional for instant theme loading at startup (avoiding flash):

```dart
// settings_controller.dart
Future<void> setDarkMode(bool value) async {
  state = state.copyWith(darkMode: value);
  // Write to both SharedPreferences (for instant startup) and SQLite
  if (QuickSettingsService.isInitialized) {
    await QuickSettingsService.instance.setDarkMode(value);
  }
  await _settingsDao?.setBool(SettingsKeys.darkMode, value);
}
```

**SQLite remains the SSOT.** SharedPreferences is a read-optimized cache that gets synced from SQLite during migration.

### 3. JSON Files 📦 MIGRATION/FALLBACK ONLY

| File | Purpose | Status |
|------|---------|--------|
| `library.json` | Legacy book storage | **Read-only for migration** |
| `.cache_metadata.json` | Legacy cache index | **Read-only for migration** |

These files are:
- Only read during one-time migration to SQLite
- Not written to after migration
- `JsonCacheMetadataStorage` class is kept as fallback but not used in production

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
2. **Documented dual-write** - dark_mode SharedPreferences is documented in `QuickSettingsService`
3. **Migration services** - One-time migration from JSON to SQLite completed
4. **Compression state in DB** - `compression_state` column is authoritative

### Future Considerations

1. **Remove legacy JSON storage classes** - `JsonCacheMetadataStorage` could be removed after confirming no users need migration
2. **Remove SharedPreferences package** - If startup theme flash is acceptable, could simplify to SQLite-only

---

## Files Reviewed

- `lib/app/database/` - All DAOs and AppDatabase
- `lib/app/settings_controller.dart` - Settings persistence
- `lib/app/quick_settings_service.dart` - SharedPreferences usage
- `lib/app/config/runtime_playback_config.dart` - Runtime config persistence
- `packages/tts_engines/lib/src/cache/` - Cache persistence
- `packages/downloads/lib/src/` - Download manifests
- `lib/app/database/migrations/` - Migration services
