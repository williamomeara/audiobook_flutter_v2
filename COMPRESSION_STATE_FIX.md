# Compression State Tracking Fix

**Date:** January 29, 2026
**Issue:** Compression statistics showing 0 compressed despite manual compression and auto-compression enabled
**Status:** ✅ Fixed

---

## Problem Analysis

When navigating to Settings → Storage, the cache showed:
- **325 cached segments**
- **0 compressed, 425 uncompressed**

Even after:
1. Manually compressing the cache
2. Having auto-compression enabled

This indicated that compression state was not being properly tracked in the database.

### Root Cause

The consolidated database migration was missing two critical columns needed for compression tracking:
1. `compression_state TEXT` - Stores the actual compression state ('wav', 'm4a', 'compressing', 'failed')
2. `compression_started_at INTEGER` - Tracks when compression operation started

Additionally, the cache DAO's `getCompressionStats()` method was querying the old `is_compressed INTEGER` column instead of the new `compression_state` column.

---

## Changes Made

### 1. Updated `migration_consolidated.dart`

Added the missing columns to the `cache_entries` table:

```sql
compression_state TEXT DEFAULT 'wav',
compression_started_at INTEGER,
```

**Why:** These columns are essential for the compression service and storage layer to properly track which files are compressed (`.m4a`) vs uncompressed (`.wav`).

### 2. Fixed `cache_dao.dart` `getCompressionStats()`

Changed from:
```dart
SELECT
  SUM(CASE WHEN is_compressed = 1 THEN 1 ELSE 0 END) as compressed,
  SUM(CASE WHEN is_compressed = 0 THEN 1 ELSE 0 END) as uncompressed
FROM cache_entries
```

To:
```dart
SELECT
  SUM(CASE WHEN compression_state = 'm4a' THEN 1 ELSE 0 END) as compressed,
  SUM(CASE WHEN compression_state != 'm4a' THEN 1 ELSE 0 END) as uncompressed
FROM cache_entries
```

**Why:** The `is_compressed` column is a legacy boolean flag that doesn't accurately reflect the actual compression state. The `compression_state` column stores the definitive state.

---

## How Compression Tracking Works

### Compression Flow

1. **User initiates compression** (manual or auto-triggered)
2. **AacCompressionService.compressDirectory()** finds uncompressed entries via `storage.getUncompressedEntries()`
3. **For each WAV file:**
   - Marks as "compressing" in database
   - Converts WAV to M4A format
   - Updates database with new filename and `compressionState: CompressionState.m4a`
4. **Settings screen queries** cache stats using `getCompressionStats()`
5. **UI displays** count of M4A files (compressed) vs WAV files (uncompressed)

### Database State Representation

The `CompressionState` enum in `CacheEntryMetadata`:
- `wav` - Original uncompressed file
- `compressing` - Compression operation in progress
- `m4a` - Successfully compressed to M4A format
- `failed` - Compression attempt failed, kept original WAV

---

## Verification

✅ All compression state columns properly created in consolidated migration
✅ Cache stats query updated to use `compression_state` column
✅ Code analysis passes with no issues
✅ Settings screen will now correctly display compression statistics

---

## Notes for Users

### If you had cached segments before this fix:

New cache files will have proper compression tracking. However, previously cached files may need to be:
1. **Cleared and re-cached** (simplest option)
2. **Manually compressed again** to update their compression state

### For new installations:

All compression operations will be properly tracked with the correct schema.

---

## Related Code

- **Compression Service:** `packages/tts_engines/lib/src/cache/aac_compression_service.dart`
- **Cache Metadata:** `packages/tts_engines/lib/src/cache/cache_entry_metadata.dart`
- **SQLite Storage:** `lib/app/database/sqlite_cache_metadata_storage.dart`
- **Cache DAO:** `lib/app/database/daos/cache_dao.dart`
- **Settings UI:** `lib/ui/screens/settings_screen.dart` (lines 1145-1158)
