# Cache Architecture Redesign Plan

**Date:** January 29, 2026
**Status:** Planning Phase
**Problem:** Multiple sources of truth causing cache inconsistency, broken compression statistics, and orphaned cache entries

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Industry Best Practices](#industry-best-practices)
4. [Available Architectural Patterns](#available-architectural-patterns)
5. [Detailed Option Analysis](#detailed-option-analysis)
6. [Recommended Solution](#recommended-solution)
7. [Implementation Roadmap](#implementation-roadmap)
8. [Technical Specifications](#technical-specifications)
9. [Risk Assessment](#risk-assessment)
10. [References](#references)

---

## Executive Summary

The audiobook app's cache system has **multiple overlapping sources of truth**:
- Disk files (.wav, .m4a)
- SQLite cache_entries table
- In-memory state (usage times, pinned files)
- Generated cache keys

This architectural inconsistency caused the recent bug where compression statistics showed "0 compressed" despite files existing on disk and compression service running.

**Recommended Solution:** Implement a **Reconciliation-Based Cache Architecture** (Option C) where:
- Database remains the authoritative source for cache metadata
- Disk holds actual audio files
- A periodic reconciliation service detects and fixes inconsistencies
- Clear, well-defined ownership of each component

---

## Current State Analysis

### Sources of Truth (Current)

```
DISK FILES (.wav, .m4a)
    ↑
    ├─ file existence indicates "cached"
    ├─ filename encodes cache key
    └─ no metadata stored

DATABASE (cache_entries table)
    ↑
    ├─ tracks compression_state
    ├─ tracks duration, size
    ├─ tracks book_id, chapter_index
    └─ may be out of sync with disk

IN-MEMORY STATE (FileAudioCache)
    ├─ _usageTimes (Map<String, DateTime>)
    ├─ _pinnedFiles (Set<String>)
    └─ lost on app restart

CACHE KEYS (Generated)
    ├─ CacheKeyGenerator.generate(voiceId, text, playbackRate)
    └─ used to derive filenames
```

### The Problem

1. **Two checks for "is cached?"**
   ```dart
   cache.isReady(key)              // checks disk files
   getCompressionStats()           // queries database
   ```
   These can disagree!

2. **Registration Happens Mid-Pipeline**
   - My recent fix calls `registerEntry()` inside `SynthesisCoordinator`
   - Couples synthesis logic to persistence
   - If registration fails, file exists but metadata is missing

3. **No Recovery Mechanism**
   - Orphaned files: file exists, no DB entry → invisible to compression
   - Ghost entries: DB entry exists, no file → queries fail
   - No automatic detection or cleanup

4. **Split Responsibilities**
   ```
   FileAudioCache          → manages disk + in-memory state
   IntelligentCacheManager → manages disk + database
   SynthesisCoordinator    → orchestrates synthesis + now registration
   ```
   No clear ownership

---

## Industry Best Practices

### From Research

**1. Database as Source of Truth** ([RedHat SSOT Architecture](https://www.redhat.com/en/blog/single-source-truth-architecture))
- Organize data so each piece has one authoritative location
- Apply real-time synchronization for dependent copies
- Reduces duplication and inconsistency

**2. Caching Patterns** ([AWS Database Caching Strategies](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/caching-patterns.html), [CodeAhoy Caching Strategies](https://codeahoy.com/2017/08/11/caching-strategies-and-how-to-choose-the-right-one/))

Three main patterns:

- **Cache-Aside (Lazy Loading)**
  - Application checks cache first, then database
  - On miss: load from DB, update cache
  - Risk: stale data, inconsistency
  - Best for: read-heavy workloads with acceptable staleness

- **Write-Through**
  - Every write updates both cache and database synchronously
  - Guarantees consistency
  - Slower (2x write latency)
  - Best for: consistency-critical systems

- **Write-Behind (Write-Back)**
  - Write to cache immediately
  - Asynchronously write to database
  - Fast writes, eventual consistency
  - Risk: data loss if cache fails before flush
  - Best for: high-throughput write scenarios

**3. Cache Coherence** ([Vintasoftware on Cache Consistency](https://www.vintasoftware.com/blog/scaling-software-how-to-manage-cache-consistency))
- Snooping protocols: every operation seen by all (broadcast-based)
- Directory protocols: point-to-point messages
- Write-invalidate: discard stale copies (most common)
- Write-update: update all copies (less common)

**4. Multi-Layer Cache Management** ([Hazelcast Microservices Caching](https://hazelcast.com/blog/architectural-patterns-for-caching-microservices/))
- Multiple cache layers require explicit coherence strategy
- Event-driven invalidation for real-time consistency
- Regular reconciliation detects and fixes inconsistencies

**5. Metadata Caching Best Practices** ([Comprehensive Data Reconciliation Guide](https://www.montecarlodata.com/blog-data-reconciliation/))
- Metadata must be kept in sync with actual state
- Automatic reconciliation detects divergence
- TTL-based stale cache eviction
- Audit trails for debugging

---

## Available Architectural Patterns

### Pattern A: Database as Single Source of Truth

```
┌─────────────────────────────────────────┐
│  Application Layer                      │
└─────────────────────────────────────────┘
                  ↓
    ┌─────────────────────────────┐
    │  CacheManager (Interface)   │
    │  - Single access point      │
    │  - Enforces DB-first policy │
    └─────────────────────────────┘
         ↓                    ↓
    ┌────────────┐        ┌──────────┐
    │  Database  │        │   Disk   │
    │  (Source)  │←──────→│  (Files) │
    └────────────┘        └──────────┘
         ↓ (metadata)
    ┌──────────────────┐
    │  In-Memory Cache │
    │  (L1, optional)  │
    └──────────────────┘
```

**Characteristics:**
- Database is authoritative for all metadata
- Disk files enumeration only on startup or manual trigger
- Disk files are "owned" by database entries
- Orphaned files detected and removed
- Ghost entries indicate corruption

**Advantages:**
- ✅ Single clear source of truth
- ✅ Strongly consistent
- ✅ Easy to understand and debug
- ✅ Transactions ensure atomicity
- ✅ Works with existing IntelligentCacheManager

**Disadvantages:**
- ❌ Startup cost: must scan and reconcile all files
- ❌ Large caches (10k+ files) slow down startup
- ❌ Requires IntelligentCacheManager everywhere
- ❌ FileAudioCache becomes incomplete

**Best For:**
- Medium caches (< 10k files)
- Strongly consistent requirements
- Existing complex database infrastructure

---

### Pattern B: Disk as Single Source of Truth

```
┌─────────────────────────────────────────┐
│  Application Layer                      │
└─────────────────────────────────────────┘
                  ↓
    ┌─────────────────────────────┐
    │  CacheManager (Interface)   │
    │  - Enumerates disk first    │
    │  - Database is cache of FS  │
    └─────────────────────────────┘
         ↓                    ↓
    ┌────────────┐        ┌──────────┐
    │  Database  │        │   Disk   │
    │  (Cache)   │←──────→│ (Source) │
    └────────────┘        └──────────┘
         ↓ (rebuilt on startup)
    ┌──────────────────┐
    │  In-Memory Cache │
    │  (L1, optional)  │
    └──────────────────┘
```

**Characteristics:**
- Disk files are authoritative
- Database rebuilt on startup from disk scan
- Database is optimization (faster queries)
- Orphaned DB entries cleaned on startup
- Missing files indicate data loss

**Advantages:**
- ✅ Simple to understand
- ✅ Disk is obvious, immutable
- ✅ No startup synchronization complexity
- ✅ FileAudioCache sufficient for basic use

**Disadvantages:**
- ❌ Slow for large caches (full disk scan)
- ❌ No metadata persistence across restarts
- ❌ Database queries become cache lookups
- ❌ Lose compression state, duration info
- ❌ Breaks existing metadata features

**Best For:**
- Small caches (< 1k files)
- Simple systems without metadata needs
- Read-only or append-only patterns

---

### Pattern C: Reconciliation-Based (RECOMMENDED)

```
┌──────────────────────────────────────────────┐
│  Application Layer                           │
└──────────────────────────────────────────────┘
                  ↓
    ┌────────────────────────────────┐
    │  CacheManager Interface        │
    │  - Database-first for ops      │
    │  - Disk-first for enumeration  │
    │  - Handles graceful failures   │
    └────────────────────────────────┘
         ↓                      ↓
    ┌──────────────┐        ┌──────────────┐
    │  Database    │←──────→│  Disk Files  │
    │  (Metadata)  │        │  (Audio)     │
    └──────────────┘        └──────────────┘
         ↑                         ↑
         └─────┬──────────────┬────┘
               │              │
    ┌──────────────────────────────────┐
    │  CacheReconciliationService      │
    │  - Runs on startup               │
    │  - Periodic background task      │
    │  - Detects & fixes discrepancies │
    │  - Logs all changes              │
    └──────────────────────────────────┘
```

**Characteristics:**
- Database owns metadata (source of truth)
- Disk owns audio files
- Clear separation of concerns
- Periodic reconciliation handles drift
- Graceful handling of failures
- Detailed audit trail

**Advantages:**
- ✅ Database remains authoritative (strong consistency)
- ✅ Clear ownership boundaries
- ✅ Handles failures gracefully
- ✅ Detects corruption automatically
- ✅ Provides audit trail for debugging
- ✅ Non-blocking: reconciliation in background
- ✅ Minimal startup overhead
- ✅ Easy to test and reason about

**Disadvantages:**
- ❌ Slightly more complex implementation
- ❌ Brief windows of inconsistency (acceptable)
- ❌ Requires reconciliation service

**Best For:**
- Production systems
- Large caches
- Systems that value resilience
- Applications needing audit trails

---

### Pattern D: Write-Behind (Asynchronous Registration)

```
┌──────────────────────────────────────┐
│  Application Layer                   │
└──────────────────────────────────────┘
         ↓                    ↓
    ┌──────────┐    ┌──────────────────┐
    │Synthesis │───→│  Queue/Cache     │
    │ Pipeline │    │  (Registration   │
    └──────────┘    │   jobs)          │
                    └──────────────────┘
         ↓                    ↓
    ┌──────────┐    ┌──────────────────┐
    │   Disk   │    │ Background       │
    │  (Files) │    │ Worker Service   │
    │          │    │ (Batch register) │
    └──────────┘    └──────────────────┘
         ↓                    ↓
    ┌───────────────────────────────────┐
    │      Database (Eventually)        │
    │      (Metadata registered)        │
    └───────────────────────────────────┘
```

**Characteristics:**
- Synthesis creates file immediately
- Registration queued asynchronously
- Worker processes registration batch
- Eventual consistency model

**Advantages:**
- ✅ Fast synthesis (don't wait for DB)
- ✅ Batches improve DB efficiency
- ✅ Natural backpressure handling

**Disadvantages:**
- ❌ Eventual consistency (can be stale for hours)
- ❌ Requires failure handling (queue persistence)
- ❌ Complex debugging
- ❌ Window where file exists but isn't "cached"
- ❌ Doesn't fit compression use case

**Best For:**
- Loose consistency requirements
- Background processing
- Non-critical metadata

---

## Detailed Option Analysis

### Option Comparison Matrix

| Criterion | Pattern A | Pattern B | Pattern C | Pattern D |
|-----------|-----------|-----------|-----------|-----------|
| **Consistency** | Strong | Eventual | Strong | Eventual |
| **Performance** | Medium | Medium | Medium | Fast |
| **Startup Time** | Slow | Slow | Fast | Fast |
| **Complexity** | Medium | Low | Medium-High | High |
| **Debuggability** | High | High | Very High | Medium |
| **Scalability** | Medium | Low | High | High |
| **Error Recovery** | Automatic | Manual | Automatic | Needs repair |
| **Compression Use** | ✅ | ❌ | ✅ | ❌ |
| **Audit Trail** | Possible | Difficult | ✅ | Possible |
| **Data Loss Risk** | Low | Low | Low | Medium |

### Why Pattern C (Reconciliation) Is Best

1. **Matches Real-World Needs**
   - Audio compression requires strong consistency
   - Files exist on disk (immutable)
   - Metadata must be accurate for statistics
   - Failures can occur at any time

2. **Minimal Performance Impact**
   - Reconciliation runs on startup (one-time cost)
   - Can be background task with throttling
   - Doesn't block normal cache operations
   - No change to synthesis pipeline performance

3. **Industry Standard**
   - Distributed systems use reconciliation ([Ceph MDS](https://docs.ceph.io/en/latest/cephfs/mdcache/))
   - Data warehouses use reconciliation ([Data Reconciliation Guide](https://www.montecarlodata.com/blog-data-reconciliation/))
   - Event-driven architectures standardize this approach

4. **Aligns with Code Structure**
   - `IntelligentCacheManager` already has database
   - `FileAudioCache` already enumerates disk
   - Easy to add reconciliation layer

---

## Recommended Solution

### Architecture Overview

```dart
// Core interface - no changes needed
abstract interface class AudioCache {
  Future<File> fileFor(CacheKey key);
  Future<bool> isReady(CacheKey key);
  Future<void> markUsed(CacheKey key);
  Future<void> registerEntry({...});  // Already added
  // ... other methods
}

// NEW: Reconciliation Service
class CacheReconciliationService {
  final AudioCache cache;
  final Database db;

  Future<ReconciliationResult> reconcile({
    bool dryRun = false,
  });
}

// Startup sequence
Future<void> initializeApp() {
  // 1. Open database
  final db = await AppDatabase.instance;

  // 2. Initialize cache
  final cache = IntelligentCacheManager(...);

  // 3. Reconcile (CRITICAL)
  final result = await CacheReconciliationService(cache, db)
      .reconcile(dryRun: false);

  // 4. Log reconciliation results
  debugPrint('Cache reconciliation: ${result.summary}');

  // 5. Run periodic reconciliation
  _startPeriodicReconciliation(cache, db);
}
```

### Reconciliation Service Responsibilities

**On Startup:**
1. Scan disk cache directory
2. Query database for all cache entries
3. Detect discrepancies:
   - Files on disk not in database → **Create DB entry**
   - DB entries not on disk → **Remove DB entry** (or mark as failed)
   - Metadata mismatches → **Update DB** from file stat
4. Generate report of changes
5. Log audit trail

**Periodic (Optional):**
- Run daily at low priority
- Detect new orphaned files
- Detect new ghost entries
- Clean up corrupted entries

**When Synthesis Fails:**
- File may be partially written
- Reconciliation detects incomplete files
- Marks as failed or removes

### Key Behaviors

**When Disk File Exists But DB Entry Missing:**
```dart
// Reconciliation detects this
// Action: Create DB entry with inferred metadata
// - compression_state = 'wav'
// - size = file.length()
// - duration = null (unknown)
// - bookId = null (unknown)
// Reason: We know file exists, should be tracked
```

**When DB Entry Exists But Disk File Missing:**
```dart
// Reconciliation detects this
// Action: Mark DB entry as 'failed' (don't delete)
// Create alert/notification
// User can clear cache to recover
// Reason: DB is source of truth, deletion
//         must be explicit
```

**When Compression State Mismatched:**
```dart
// Example: DB says 'm4a' but only .wav exists
// Action: Update DB to match disk reality
// Reason: Disk is immutable physical reality
```

---

## Implementation Roadmap

### Phase 1: Create Reconciliation Service (1-2 days)

**Files to create:**
- `lib/app/cache/cache_reconciliation_service.dart`
- `lib/app/cache/reconciliation_result.dart`

**Responsibilities:**
```dart
class CacheReconciliationService {
  // Read disk and database state
  Future<CacheState> _readDiskState();
  Future<CacheState> _readDatabaseState();

  // Detect discrepancies
  Future<List<Discrepancy>> _detectDiscrepancies();

  // Fix discrepancies
  Future<void> _fixDiscrepancy(Discrepancy d, {required bool dryRun});

  // Public entry point
  Future<ReconciliationResult> reconcile({bool dryRun = false});
}
```

**Tests:**
- Test disk file → DB entry creation
- Test DB entry → disk file deletion
- Test metadata reconciliation
- Test idempotency (running twice = same result)

---

### Phase 2: Integrate into Startup (1 day)

**Files to modify:**
- `lib/main.dart` - add reconciliation before cache initialization
- Logging - add reconciliation results to startup logs

**Changes:**
```dart
void main() async {
  // ... existing setup ...

  // Initialize cache with reconciliation
  final cache = await _initializeCacheWithReconciliation();

  // ... continue with app ...
}

Future<AudioCache> _initializeCacheWithReconciliation() async {
  final db = await AppDatabase.instance;
  final cache = IntelligentCacheManager(...);

  final reconciliation = CacheReconciliationService(cache, db);
  final result = await reconciliation.reconcile();

  // Log results
  developer.log(
    'Cache reconciliation complete: '
    '${result.filesAdded} added, '
    '${result.entriesRemoved} removed, '
    '${result.metadataFixed} metadata fixed'
  );

  return cache;
}
```

---

### Phase 3: Periodic Reconciliation (Optional, 1-2 days)

**Create service:**
- `lib/app/cache/periodic_reconciliation_service.dart`

**Behavior:**
- Runs daily at 3 AM
- Throttled to minimize impact
- Skips if app is in active use
- Results logged (not shown to user)

**Configuration:**
```dart
class PeriodicReconciliationConfig {
  final Duration interval = const Duration(days: 1);
  final TimeOfDay preferredTime = TimeOfDay(hour: 3, minute: 0);
  final bool enableDetailedLogging = false;
  final int maxConcurrentOps = 2; // Throttle
}
```

---

### Phase 4: Monitoring & Alerts (Optional, 1 day)

**Track metrics:**
- Discrepancies per reconciliation
- File cleanup rate
- Entry creation rate
- Reconciliation duration
- Error rate

**Alerts triggered when:**
- Orphaned files > 10% of cache
- Ghost entries > 5
- Reconciliation takes > 30 seconds
- Reconciliation fails

---

### Phase 5: Remove Current Fix (1-2 days)

**After reconciliation is confident, remove:**
- My registerEntry() call from SynthesisCoordinator
- Revert synthesis pipeline to simpler version
- Reconciliation now handles registration

**Why:** Single responsibility - synthesis makes audio, reconciliation ensures it's tracked.

---

## Technical Specifications

### CacheReconciliationService API

```dart
class CacheReconciliationService {
  CacheReconciliationService({
    required this.cache,
    required this.database,
    this.logger = _defaultLogger,
  });

  final AudioCache cache;
  final Database database;
  final Logger logger;

  /// Perform full reconciliation.
  /// Returns detailed report of all changes made.
  Future<ReconciliationResult> reconcile({
    bool dryRun = false,
    VoidCallback? onProgress,
  });

  /// Reconcile a single cache key.
  /// Called after synthesis for immediate consistency.
  Future<void> reconcileSingle(CacheKey key) async {
    // ...
  }
}

class ReconciliationResult {
  // Counts
  final int filesScanned;
  final int entriesScanned;
  final int discrepanciesFound;
  final int discrepanciesFixed;

  // Details
  final List<Discrepancy> filesAddedToDb;  // Disk → DB
  final List<Discrepancy> entriesRemovedFromDb;  // DB→Disk
  final List<Discrepancy> metadataFixed;

  // Timing
  final Duration duration;

  String get summary =>
    'Files: $filesScanned, Entries: $entriesScanned, '
    'Discrepancies: $discrepanciesFound, Fixed: $discrepanciesFixed, '
    'Duration: ${duration.inSeconds}s';
}

enum DiscrepancyType {
  /// File exists on disk but not in database
  orphanedFile,

  /// Database entry exists but file missing
  ghostEntry,

  /// File size doesn't match DB
  sizeMismatch,

  /// Compression state doesn't match file extension
  compressionStateMismatch,
}

class Discrepancy {
  final DiscrepancyType type;
  final String fileOrEntry;  // filename or cache key
  final String description;
  final DateTime detectedAt;
  late DateTime? fixedAt;

  bool get wasFixed => fixedAt != null;
}
```

### Database Audit Table (Optional)

```sql
CREATE TABLE cache_audit (
  id INTEGER PRIMARY KEY,
  event_type TEXT NOT NULL,  -- 'reconcile_start', 'file_added', etc
  details TEXT,               -- JSON with specifics
  affected_cache_key TEXT,
  timestamp INTEGER NOT NULL,
  reconciliation_batch_id INTEGER
);
```

---

## Risk Assessment

### Risk 1: Reconciliation Deletes Wrong Files

**Severity:** High
**Likelihood:** Low
**Mitigation:**
- Extensive testing with various disk states
- Dry-run mode for first reconciliation
- Backup before reconciliation
- Explicit file confirmation before deletion

---

### Risk 2: Reconciliation is Too Slow

**Severity:** Medium
**Likelihood:** Low
**Mitigation:**
- Run on background thread
- Batch database operations
- Limit to 100 files per second
- Show progress UI

---

### Risk 3: Database Corruption Undetected

**Severity:** High
**Likelihood:** Low
**Mitigation:**
- Validate all DB entries on read
- Checksum critical fields
- Audit trail for debugging
- Regular backups

---

### Risk 4: Reconciliation Conflicts with Synthesis

**Severity:** Medium
**Likelihood:** Medium
**Mitigation:**
- Reconciliation only on startup
- Periodic runs at low priority
- Locks for exclusive access if needed
- Or: `reconcileSingle()` after synthesis

---

## References

- [AWS Database Caching Strategies](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/caching-patterns.html)
- [RedHat SSOT Architecture](https://www.redhat.com/en/blog/single-source-truth-architecture)
- [CodeAhoy Caching Strategies](https://codeahoy.com/2017/08/11/caching-strategies-and-how-to-choose-the-right-one/)
- [Vintasoftware Cache Consistency](https://www.vintasoftware.com/blog/scaling-software-how-to-manage-cache-consistency)
- [Hazelcast Microservices Caching Patterns](https://hazelcast.com/blog/architectural-patterns-for-caching-microservices/)
- [Comprehensive Data Reconciliation Guide](https://www.montecarlodata.com/blog-data-reconciliation/)
- [GeeksforGeeks System Design Caching](https://www.geeksforgeeks.org/system-design/caching-system-design-concept-for-beginners/)
- [Medium: Cache Layers](https://medium.com/@shivanimutke2501/day-5-system-design-concept-caching-layers-cae17d6ad605)
- [Ceph Distributed Metadata Cache](https://docs.ceph.io/en/latest/cephfs/mdcache/)
- [Oracle Read/Write Through Caching](https://docs.oracle.com/cd/E16459_01/coh.350/e14510/readthrough.htm)
- [Medium: Cache Synchronization](https://medium.com/@nagpal.upasana.un/understanding-cache-synchronization-write-through-write-back-and-write-around-efad9d1b5539)
- [Microsoft Azure Cache-Aside Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/cache-aside)

---

## Appendix: Decision Table

**Decision:** Use Pattern C (Reconciliation-Based Architecture)

**Rationale:**
1. ✅ Industry-standard approach (Ceph, data warehouses)
2. ✅ Matches current architecture (database + disk)
3. ✅ Strong consistency for compression feature
4. ✅ Automatic failure recovery
5. ✅ Detailed audit trail for debugging
6. ✅ Minimal performance impact
7. ✅ Works with existing code structure
8. ❌ Slightly more complex (acceptable trade-off)

**Next Steps:**
1. Review this plan with team
2. Get approval to proceed
3. Implement Phase 1 (Reconciliation Service)
4. Test extensively before Phase 5 (remove current fix)

---

## Conclusion

The current fix (registerEntry in synthesis) solves the immediate problem but creates technical debt. A proper reconciliation-based architecture provides:

- **Single source of truth** (database)
- **Clear ownership** (database: metadata, disk: files)
- **Automatic consistency** (reconciliation detects/fixes drift)
- **Production-ready resilience** (handles failures gracefully)
- **Industry-standard pattern** (proven in large systems)

This plan provides a path to move from the quick fix to a robust, maintainable architecture.
