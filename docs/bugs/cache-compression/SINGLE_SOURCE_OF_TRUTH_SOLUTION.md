# Single Source of Truth (SSOT) - Cache Compression Architecture

## Current Problem

We have **TWO sources of truth**:
1. **File System** (actual files: `.wav`, `.m4a`)
2. **SQLite Database** (metadata records)

This causes:
- Metadata can fall out of sync with filesystem
- Manual compression bypasses metadata updates
- Double-compression risk if metadata is stale
- Cache size calculations based on stale metadata
- No single authoritative source for "which files are compressed"

## Solution: SQLite as Single Source of Truth

### Principle
- **SQLite Database = Authoritative Source**
- **File System = Storage Backend**
- All compression operations update DB first, then update files

### Key Changes

#### 1. Add Compression State to Database
```dart
// Current CacheEntryMetadata (in SQLite cache_entries table)
class CacheEntryMetadata {
  final String key;              // filename (e.g., "segment_001.m4a")
  final int sizeBytes;           // actual file size
  final DateTime createdAt;
  final DateTime lastAccessed;
  final int accessCount;
  final String bookId;
  final String voiceId;
  final int segmentIndex;
  final int chapterIndex;
  final String engineType;
  final int audioDurationMs;
  
  // ADD THIS:
  final CompressionState compressionState;  // WAV, COMPRESSING, M4A
  final DateTime? compressionStartedAt;     // track in-progress compression
}

enum CompressionState {
  wav,          // Uncompressed WAV file
  compressing,  // Compression in progress
  m4a,          // Compressed M4A file
  failed,       // Compression failed (keep original WAV)
}
```

#### 2. Refactor IntelligentCacheManager

**Current Flow**:
```
Synthesis Complete
  → compressEntryByFilenameInBackground()
    → Isolate.run(compress_in_isolate)
    → Update metadata map
    → Update SQLite
```

**New Flow**:
```
Synthesis Complete
  → Update DB: SET compressionState = COMPRESSING
  → compressEntryByFilenameInBackground()
    → Isolate.run(compress_in_isolate)
    → Update DB: SET compressionState = M4A, key = segment_001.m4a
  → Memory _metadata map stays in sync with DB
```

**Key Changes**:
- Database becomes authoritative
- Memory cache is secondary (loaded from DB)
- Always update DB before updating memory
- Read compression state from DB when making decisions

#### 3. Refactor AacCompressionService.compressDirectory()

**Current**:
```dart
Future<AacCompressionResult> compressDirectory(
  Directory cacheDir,
  {onProgress?, shouldCancel?}
) async {
  final wavFiles = find all .wav files in directory;
  for (wavFile in wavFiles) {
    await compressFile(wavFile);  // ❌ Only updates filesystem
  }
}
```

**New**:
```dart
Future<AacCompressionResult> compressDirectory(
  CacheMetadataStorage storage,  // ✅ Add storage parameter
  Directory cacheDir,
  {onProgress?, shouldCancel?}
) async {
  // Step 1: Query DB for all WAV entries (not filesystem scan)
  final wavEntries = await storage.getUncompressedEntries();
  
  for (entry in wavEntries) {
    // Step 2: Mark as "compressing" in DB
    await storage.updateCompressionState(entry.key, COMPRESSING);
    
    // Step 3: Compress file
    final result = await compressFile(entry.toFile());
    
    // Step 4: Update DB with new state
    if (result.success) {
      await storage.replaceEntry(
        oldKey: entry.key,           // segment_001.wav
        newEntry: entry.copy(
          key: newKey,               // segment_001.m4a
          sizeBytes: result.size,
          compressionState: M4A,
        ),
      );
    } else {
      await storage.updateCompressionState(entry.key, FAILED);
    }
  }
}
```

#### 4. New CacheMetadataStorage Methods

```dart
abstract class CacheMetadataStorage {
  // Existing methods...
  
  // New methods for compression workflow
  
  /// Get all uncompressed (WAV) entries from database.
  /// Queries DB, not filesystem.
  Future<List<CacheEntryMetadata>> getUncompressedEntries();
  
  /// Mark an entry as "compressing" to prevent race conditions.
  Future<void> updateCompressionState(
    String key, 
    CompressionState state,
  );
  
  /// Replace an entry (old WAV with new M4A).
  /// Atomic operation: delete old, insert new.
  Future<void> replaceEntry({
    required String oldKey,
    required CacheEntryMetadata newEntry,
  });
  
  /// Update only the compression state.
  /// Used for marking COMPRESSING → M4A or COMPRESSING → FAILED.
  Future<void> updateCompressionState(
    String key,
    CompressionState state,
  );
}
```

#### 5. Update Settings Screen

**Current**:
```dart
final result = await service.compressDirectory(
  manager.directory,
  onProgress: onProgress,
  shouldCancel: shouldCancel,
);
// ❌ Metadata never updated
```

**New**:
```dart
final result = await service.compressDirectory(
  manager.storage,  // ✅ Pass storage for DB updates
  manager.directory,
  onProgress: onProgress,
  shouldCancel: shouldCancel,
);
// ✅ Metadata automatically updated by compressDirectory()
```

### Benefits of This Approach

| Issue | Current | With SSOT |
|-------|---------|-----------|
| **Double Compression** | Possible (metadata stale) | ❌ Impossible (DB state checked) |
| **Metadata Sync** | Manual in 2 places | ✅ Automatic in 1 place (DB) |
| **Cache Size Accuracy** | Based on old metadata | ✅ Always accurate from DB |
| **Compression State** | Implicit (file exists?) | ✅ Explicit (DB field) |
| **Race Conditions** | Possible (no locking) | ✅ Prevented (DB transaction) |
| **Recovery** | Scan filesystem | ✅ Query DB (faster) |

### Implementation Strategy

**Phase 1: Database Schema**
1. Add `compressionState` column to `cache_entries` table
2. Add `compressionStartedAt` column to track in-progress
3. Create migration script

**Phase 2: Storage Interface**
1. Add new methods to `CacheMetadataStorage`
2. Implement in `SqliteCacheMetadataStorage`
3. Implement in `JsonCacheMetadataStorage` (fallback)

**Phase 3: Core Manager**
1. Update `IntelligentCacheManager.compressEntryByFilenameInBackground()`
2. Change metadata updates to use DB-first approach
3. Always read compression state from DB

**Phase 4: Compression Service**
1. Refactor `AacCompressionService.compressDirectory()`
2. Accept `CacheMetadataStorage` parameter
3. Update DB instead of just filesystem

**Phase 5: Settings UI**
1. Pass `manager.storage` to `compressDirectory()`
2. Remove any manual metadata updates
3. Trust DB is authoritative

### Code Example: New Pattern

```dart
// Instead of this (filesystem-first):
final wavFiles = find_all_wav_files();
compress_all(wavFiles);  // No DB updates

// Do this (database-first):
final wavEntries = await storage.getUncompressedEntries();
for (entry in wavEntries) {
  // Always update DB before/during/after filesystem ops
  await storage.updateCompressionState(entry.key, COMPRESSING);
  await compress_file(entry.path);
  await storage.replaceEntry(entry, newM4aEntry);
}
// DB is now source of truth
```

### Safety Guarantees

1. **Atomicity**: DB transaction → file update (not other way around)
2. **Consistency**: DB state = filesystem state (always)
3. **Isolation**: `compressionState = COMPRESSING` prevents double-compression
4. **Durability**: SQLite ensures data persists

### Backward Compatibility

- Old JSON storage still works
- New compression state defaults to "WAV"
- Migration handles existing entries
- No breaking changes to public API

## Testing Strategy

1. **Unit Tests**
   - Verify DB state after compression
   - Test concurrent compression attempts
   - Test failure recovery

2. **Integration Tests**
   - Manual compress updates DB
   - Auto-compress updates DB
   - No double-compression
   - Cache stats match DB

3. **Device Tests**
   - Verify on Pixel 8 with multiple syntheses
   - Manual compress after auto-compress
   - Verify metadata consistency

## Summary

**Before**: File system + In-Memory Metadata + SQLite (3 sources)
**After**: SQLite is Source of Truth → File system is Storage

This eliminates ambiguity and makes the system more robust.
