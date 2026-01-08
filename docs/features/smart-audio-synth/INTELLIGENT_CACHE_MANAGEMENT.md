# Intelligent Cache Management System

## Overview

This document outlines the intelligent cache management system for synthesized audio segments, addressing two critical concerns:

1. **User-Configurable Storage Quota**: Users can specify maximum storage allocation
2. **Intelligent Cache Eviction**: Smart algorithms to maximize cache hit rate within storage limits

## Problem Statement

### Current Challenges

1. **Unbounded Cache Growth**: Without limits, synthesized audio can consume significant device storage
2. **No User Control**: Users cannot specify how much storage they're willing to dedicate
3. **Suboptimal Eviction**: Simple LRU (Least Recently Used) doesn't account for usage patterns
4. **No Visibility**: Users don't know how much storage is being used

### Storage Impact Analysis

| Content Type | Average Size | Example |
|--------------|--------------|---------|
| 1 audio segment (20 words) | ~150 KB | 8-10 seconds of audio |
| 1 chapter (50 segments) | ~7.5 MB | ~7 minutes of audio |
| 1 book (30 chapters) | ~225 MB | 3.5 hours of audio |
| 10 books fully cached | ~2.25 GB | 35 hours of audio |

Without management, power users could easily accumulate 5-10 GB of cached audio.

---

## Solution Design

### 1. User-Configurable Storage Quota

#### Settings UI

```dart
// lib/ui/screens/settings/cache_settings_screen.dart

class CacheSettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheState = ref.watch(cacheManagerProvider);
    
    return Column(
      children: [
        // Current Usage Display
        CacheUsageIndicator(
          used: cacheState.currentUsage,
          quota: cacheState.quota,
        ),
        
        // Quota Slider
        ListTile(
          title: Text('Maximum Cache Size'),
          subtitle: Slider(
            value: cacheState.quotaGB,
            min: 0.5,
            max: 10.0,
            divisions: 19, // 0.5 GB increments
            label: '${cacheState.quotaGB.toStringAsFixed(1)} GB',
            onChanged: (value) => ref
                .read(cacheManagerProvider.notifier)
                .setQuota(value),
          ),
          trailing: Text('${cacheState.quotaGB.toStringAsFixed(1)} GB'),
        ),
        
        // Quick Options
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(label: Text('500 MB'), selected: cacheState.quotaGB == 0.5),
            ChoiceChip(label: Text('1 GB'), selected: cacheState.quotaGB == 1.0),
            ChoiceChip(label: Text('2 GB'), selected: cacheState.quotaGB == 2.0),
            ChoiceChip(label: Text('5 GB'), selected: cacheState.quotaGB == 5.0),
          ],
        ),
        
        // Clear Cache Button
        ElevatedButton.icon(
          icon: Icon(Icons.delete_sweep),
          label: Text('Clear All Cache'),
          onPressed: () => _confirmClearCache(context, ref),
        ),
      ],
    );
  }
}
```

#### Default Quotas by Device

| Device Storage | Default Quota | Rationale |
|----------------|---------------|-----------|
| < 32 GB | 500 MB | Conserve limited storage |
| 32-64 GB | 1 GB | Balanced default |
| 64-128 GB | 2 GB | Comfortable default |
| > 128 GB | 5 GB | Generous for power users |

```dart
class CacheQuotaDefaults {
  static Future<double> getDefaultQuota() async {
    final storage = await _getDeviceStorage();
    
    if (storage < 32 * _GB) return 0.5;
    if (storage < 64 * _GB) return 1.0;
    if (storage < 128 * _GB) return 2.0;
    return 5.0;
  }
}
```

---

### 2. Intelligent Cache Eviction Strategy

The cache eviction system uses a multi-factor scoring algorithm rather than simple LRU.

#### Eviction Score Algorithm

```dart
class IntelligentCacheManager {
  /// Calculate eviction priority score (lower = evict first)
  double calculateEvictionScore(CacheEntry entry) {
    final score = 
        _recencyScore(entry) * 0.3 +       // 30% weight
        _frequencyScore(entry) * 0.2 +     // 20% weight
        _readingPositionScore(entry) * 0.3 + // 30% weight
        _bookProgressScore(entry) * 0.15 + // 15% weight
        _voiceMatchScore(entry) * 0.05;    // 5% weight
    
    return score;
  }
  
  /// Recent access is valuable (0.0 = old, 1.0 = recent)
  double _recencyScore(CacheEntry entry) {
    final hoursSinceAccess = DateTime.now()
        .difference(entry.lastAccessed)
        .inHours;
    
    // Decay curve: 50% value at 24 hours, 10% at 7 days
    return math.exp(-hoursSinceAccess / 48.0);
  }
  
  /// Frequently accessed segments are valuable
  double _frequencyScore(CacheEntry entry) {
    // Normalize by max frequency seen
    return (entry.accessCount / _maxAccessCount).clamp(0.0, 1.0);
  }
  
  /// Segments near reading position are most valuable
  double _readingPositionScore(CacheEntry entry) {
    final book = _getBook(entry.bookId);
    if (book == null) return 0.0;
    
    final readingPosition = _getReadingPosition(book);
    final segmentDistance = (entry.segmentIndex - readingPosition).abs();
    
    // High value for current position, decay for distance
    // Segments ahead are more valuable than segments behind
    if (entry.segmentIndex >= readingPosition) {
      // Ahead: high value, slow decay
      return math.exp(-segmentDistance / 20.0);
    } else {
      // Behind: lower value, faster decay
      return math.exp(-segmentDistance / 5.0) * 0.5;
    }
  }
  
  /// Books in progress are more valuable than finished/unstarted
  double _bookProgressScore(CacheEntry entry) {
    final book = _getBook(entry.bookId);
    if (book == null) return 0.0;
    
    final progress = book.readingProgress; // 0.0 to 1.0
    
    // Bell curve: 50% progress = highest value
    // Just started or nearly finished = lower value
    return 4.0 * progress * (1.0 - progress);
  }
  
  /// Current voice cache is more valuable
  double _voiceMatchScore(CacheEntry entry) {
    final currentVoice = _getCurrentVoice();
    return entry.voiceId == currentVoice.id ? 1.0 : 0.0;
  }
}
```

#### Eviction Priority Visualization

```
Cache Entry Scoring:

High Priority to Keep (score > 0.8):
├── Currently playing segment
├── Next 5 segments ahead of reading position
├── Segments from actively reading book
└── Current voice, accessed recently

Medium Priority (score 0.4-0.8):
├── Same chapter, different segments
├── Other books in progress
└── Recently synthesized for current voice

Low Priority (score < 0.4):
├── Finished books
├── Old voice (user changed voices)
├── Segments far behind reading position
└── Books not opened in > 7 days
```

#### Eviction Triggers

```dart
class CacheEvictionTriggers {
  /// Called after each synthesis
  Future<void> onSegmentCached(CacheEntry entry) async {
    final currentUsage = await _calculateCacheSize();
    final quota = _getQuota();
    
    if (currentUsage > quota) {
      await _evictUntilUnderQuota(quota * 0.9); // Target 90% of quota
    }
  }
  
  /// Called when quota is reduced
  Future<void> onQuotaReduced(double newQuota) async {
    await _evictUntilUnderQuota(newQuota);
  }
  
  /// Called periodically (daily)
  Future<void> performMaintenance() async {
    // Remove entries with score < 0.1
    await _evictLowScoreEntries(threshold: 0.1);
    
    // Verify quota compliance
    await _evictUntilUnderQuota(_getQuota());
    
    // Clean up orphaned files
    await _removeOrphanedFiles();
  }
}
```

---

### 3. Cache Entry Metadata

```dart
class CacheEntry {
  final String key;           // "{voiceId}_{bookId}_{segmentIndex}"
  final String filePath;      // Path to cached audio file
  final int sizeBytes;        // File size
  final DateTime createdAt;   // When synthesized
  final DateTime lastAccessed; // Last playback
  final int accessCount;      // Times played
  
  // Book context
  final String bookId;
  final String voiceId;
  final int segmentIndex;
  final int chapterIndex;
  
  // Synthesis metadata
  final String engineType;    // supertonic, piper, kokoro
  final Duration audioDuration;
  final double synthesisRTF;  // How long synthesis took vs audio length
}
```

#### Database Schema

```sql
CREATE TABLE cache_entries (
  key TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  last_accessed INTEGER NOT NULL,
  access_count INTEGER DEFAULT 1,
  
  book_id TEXT NOT NULL,
  voice_id TEXT NOT NULL,
  segment_index INTEGER NOT NULL,
  chapter_index INTEGER NOT NULL,
  
  engine_type TEXT NOT NULL,
  audio_duration_ms INTEGER NOT NULL,
  synthesis_rtf REAL NOT NULL
);

CREATE INDEX idx_book_voice ON cache_entries(book_id, voice_id);
CREATE INDEX idx_last_accessed ON cache_entries(last_accessed);
CREATE INDEX idx_eviction ON cache_entries(book_id, segment_index);
```

---

### 4. Proactive Cache Management

#### Pre-emptive Eviction

Rather than waiting until quota is exceeded, intelligently prepare for upcoming synthesis:

```dart
class ProactiveCacheManager {
  /// Called before starting synthesis batch
  Future<void> prepareForSynthesis({
    required int segmentCount,
    required double averageSegmentSize,
  }) async {
    final estimatedSize = segmentCount * averageSegmentSize;
    final currentUsage = await _calculateCacheSize();
    final quota = _getQuota();
    final available = quota - currentUsage;
    
    if (estimatedSize > available) {
      // Pre-emptively evict to make room
      final targetUsage = quota - estimatedSize - (quota * 0.1); // 10% buffer
      await _evictUntilUnderQuota(targetUsage);
      
      developer.log(
        '📦 Pre-emptive eviction: freed ${(currentUsage - targetUsage) / _MB} MB '
        'for ${segmentCount} segments',
      );
    }
  }
}
```

#### Smart Book Unloading

When a book is finished or not accessed for extended period:

```dart
class BookCacheManager {
  /// Unload book cache when finished
  Future<void> onBookFinished(String bookId) async {
    // Keep first chapter for quick re-access
    // Evict remaining chapters over time
    await _scheduleGradualEviction(bookId, keepChapters: 1);
  }
  
  /// Reduce cache for inactive books
  Future<void> onBookInactive(String bookId, Duration inactivity) async {
    if (inactivity > Duration(days: 7)) {
      // Keep only bookmarked positions
      await _evictNonBookmarkedSegments(bookId);
    }
    
    if (inactivity > Duration(days: 30)) {
      // Full eviction for very old books
      await _evictAllForBook(bookId);
    }
  }
}
```

---

### 5. Long-Term Storage Compression

To maximize the effective storage capacity within the user's quota, older cache entries are compressed using the Opus audio codec.

#### Compression Strategy

| Level | Bitrate | Compression Ratio | Use Case |
|-------|---------|-------------------|----------|
| **None** | N/A | 1x | Fastest access, most storage |
| **Light** | 64 kbps | ~6x | High quality, good savings |
| **Standard** | 32 kbps | ~10x | Good quality, excellent savings |
| **Aggressive** | 24 kbps | ~15x | Acceptable quality, maximum savings |

#### How It Works

1. **Hot Cache**: Recently accessed entries (<1 hour) stay uncompressed for instant playback
2. **Warm Cache**: Entries 1-24 hours old remain uncompressed but are candidates for compression
3. **Cold Cache**: Entries >24 hours are compressed to Opus format

```dart
class CacheCompressionConfig {
  /// Compression level (none, light, standard, aggressive)
  final CompressionLevel compressionLevel;
  
  /// Entries older than this threshold get compressed
  final Duration hotCacheThreshold; // Default: 1 hour
  
  /// Compress entries before eviction to save more space
  final bool compressOnEviction;
  
  /// Decompress automatically when accessed
  final bool decompressOnAccess;
}
```

#### Space Savings Example

With **Standard** compression (10x ratio):

| Scenario | Uncompressed | Compressed | Savings |
|----------|--------------|------------|---------|
| 1 hour audio | 540 MB | 54 MB | 486 MB (90%) |
| 10 hours audio | 5.4 GB | 540 MB | 4.86 GB (90%) |
| Full 2 GB quota | 2 GB | ~3.7 hours | ~37 hours effective capacity |

#### User Controls

```dart
// Settings UI for compression
ListTile(
  title: Text('Audio Compression'),
  subtitle: Text(_getCompressionDescription(level)),
  trailing: DropdownButton<CompressionLevel>(
    value: currentLevel,
    items: [
      DropdownMenuItem(value: CompressionLevel.none, child: Text('Off (fastest)')),
      DropdownMenuItem(value: CompressionLevel.light, child: Text('Light (6x)')),
      DropdownMenuItem(value: CompressionLevel.standard, child: Text('Standard (10x)')),
      DropdownMenuItem(value: CompressionLevel.aggressive, child: Text('Maximum (15x)')),
    ],
    onChanged: _updateCompressionLevel,
  ),
),
```

#### Decompression On Access

When a compressed entry is accessed:

1. Check if compressed version exists (`.opus` extension)
2. Decompress to temporary WAV file
3. Play the decompressed file
4. Move to hot cache (won't be re-compressed for hotCacheThreshold)

```dart
Future<File> getPlayableFile(CacheKey key) async {
  final wavFile = await fileFor(key);
  if (await wavFile.exists()) {
    return wavFile; // Already uncompressed
  }
  
  final opusFile = File(wavFile.path.replaceAll('.wav', '.opus'));
  if (await opusFile.exists()) {
    // Decompress for playback
    return await _compressor.decompressEntry(opusFile);
  }
  
  throw CacheMissException(key);
}
```

---

### 6. Cache Analytics & Insights

#### User-Facing Statistics

```dart
class CacheInsights {
  /// Get cache breakdown for settings screen
  Future<CacheBreakdown> getBreakdown() async {
    final entries = await _getAllEntries();
    
    return CacheBreakdown(
      totalSize: entries.fold(0, (sum, e) => sum + e.sizeBytes),
      byBook: _groupByBook(entries),
      byVoice: _groupByVoice(entries),
      byAge: _groupByAge(entries),
      hitRate: _calculateHitRate(),
      estimatedSavings: _calculateEvictionPotential(),
    );
  }
}

// Display in settings:
// "Audio Cache: 1.2 GB / 2.0 GB"
// "Pride and Prejudice: 180 MB (25 chapters)"
// "Great Gatsby: 95 MB (12 chapters)"
// "Cache hit rate: 87%"
// "Tap to manage individual books..."
```

#### Developer Metrics

```dart
class CacheMetrics {
  void logCacheEvent(CacheEvent event) {
    switch (event) {
      case CacheEvent.hit:
        _incrementCounter('cache_hits');
        break;
      case CacheEvent.miss:
        _incrementCounter('cache_misses');
        break;
      case CacheEvent.eviction:
        _incrementCounter('cache_evictions');
        _logEvictionReason(event.reason);
        break;
      case CacheEvent.synthesis:
        _trackSynthesisTime(event.duration);
        break;
    }
  }
  
  Map<String, dynamic> getMetrics() => {
    'hit_rate': _hitRate,
    'miss_rate': _missRate,
    'eviction_rate': _evictionRate,
    'average_entry_age_hours': _averageAge,
    'total_size_mb': _totalSizeMB,
    'quota_utilization': _quotaUtilization,
  };
}
```

---

### 7. Edge Cases & Robustness

#### Handling Low Disk Space

```dart
class DiskSpaceMonitor {
  Stream<DiskSpaceEvent> get events async* {
    while (true) {
      final available = await _getAvailableDiskSpace();
      
      if (available < _CRITICAL_THRESHOLD) { // < 500 MB
        yield DiskSpaceEvent.critical;
        await _emergencyEviction();
      } else if (available < _WARNING_THRESHOLD) { // < 1 GB
        yield DiskSpaceEvent.warning;
        // Reduce cache quota temporarily
        await _reduceQuotaTemporarily();
      }
      
      await Future.delayed(Duration(minutes: 5));
    }
  }
  
  Future<void> _emergencyEviction() async {
    // Aggressive eviction to free disk space
    final targetFree = _CRITICAL_THRESHOLD * 2;
    await _evictUntilDiskSpaceAvailable(targetFree);
    
    // Notify user
    _showNotification(
      'Disk space low. Cleared audio cache to free space.',
    );
  }
}
```

#### Corruption Recovery

```dart
class CacheIntegrityChecker {
  Future<void> verifyIntegrity() async {
    final entries = await _getAllEntries();
    
    for (final entry in entries) {
      final file = File(entry.filePath);
      
      if (!await file.exists()) {
        // File missing - remove database entry
        await _removeEntry(entry.key);
        continue;
      }
      
      if (await file.length() != entry.sizeBytes) {
        // File corrupted - remove both
        await file.delete();
        await _removeEntry(entry.key);
        continue;
      }
      
      // Optional: verify audio file header
      if (!await _isValidAudioFile(entry.filePath)) {
        await file.delete();
        await _removeEntry(entry.key);
      }
    }
    
    // Check for orphaned files (files without database entries)
    await _cleanupOrphanedFiles();
  }
}
```

---

## Implementation Plan

### Phase 1: Core Cache Manager (Week 1)

1. ✅ Create `CacheEntryMetadata` model with full metadata
2. ✅ Implement JSON-based persistence for cache tracking
3. ✅ Build basic eviction algorithm (LRU baseline)
4. ✅ Add cache size calculation

### Phase 2: Intelligent Eviction (Week 1-2)

1. ✅ Implement multi-factor scoring algorithm (`EvictionScoreCalculator`)
2. ✅ Add reading position awareness
3. ✅ Integrate with book progress tracking
4. ✅ Add voice-aware eviction

### Phase 3: User Settings (Week 2)

1. Build cache settings screen
2. Implement quota slider with presets
3. Add cache breakdown visualization
4. Create per-book cache management

### Phase 4: Long-Term Storage Compression (Week 2-3)

1. ✅ Create `CacheCompressor` with compression levels (none/light/standard/aggressive)
2. ✅ Implement hot/cold cache threshold logic
3. Integrate with native Opus encoder (FFI bindings)
4. Add compression statistics and user controls
5. Implement decompression-on-access for compressed entries

### Phase 5: Advanced Features (Week 3)

1. ✅ Proactive cache management (`prepareForSynthesis`)
2. Disk space monitoring
3. Cache integrity verification
4. Analytics and metrics

### Phase 6: Testing & Polish (Week 3-4)

1. Unit tests for eviction algorithm
2. Integration tests for quota enforcement
3. Stress tests for edge cases
4. Compression/decompression performance testing
5. Performance optimization

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Cache never exceeds user quota | 100% compliance |
| Cache hit rate | > 80% for active books |
| Eviction algorithm latency | < 100ms for 1000 entries |
| Compression ratio achieved | > 8x for standard level |
| Decompression latency | < 200ms per segment |
| Effective capacity increase | 5-10x with compression |
| User complaints about storage | < 1% of users |
| Disk space warnings triggered | < 0.1% of sessions |

---

## Related Documentation

- `MASTER_PLAN.md`: Overall smart synthesis strategy
- `BUFFERING_REDUCTION_STRATEGY.md`: Why caching matters for buffering
- `PHASE1_IMPLEMENTATION.md`: Initial caching implementation

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-07  
**Status**: Ready for Implementation
