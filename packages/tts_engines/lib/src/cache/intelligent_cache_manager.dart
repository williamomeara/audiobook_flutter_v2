import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';

import 'audio_cache.dart';
import 'cache_entry_metadata.dart';

/// User-configurable cache quota settings.
class CacheQuotaSettings {
  const CacheQuotaSettings({
    this.maxSizeBytes = 2 * 1024 * 1024 * 1024, // 2 GB default
    this.warningThresholdPercent = 90,
  });

  /// Maximum cache size in bytes.
  final int maxSizeBytes;

  /// Percentage of quota at which to warn user.
  final int warningThresholdPercent;

  /// Get size in GB for display.
  double get sizeGB => maxSizeBytes / (1024 * 1024 * 1024);

  /// Create settings from GB value.
  factory CacheQuotaSettings.fromGB(double gb) {
    return CacheQuotaSettings(
      maxSizeBytes: (gb * 1024 * 1024 * 1024).round(),
    );
  }

  /// Copy with new values.
  CacheQuotaSettings copyWith({int? maxSizeBytes}) {
    return CacheQuotaSettings(
      maxSizeBytes: maxSizeBytes ?? this.maxSizeBytes,
      warningThresholdPercent: warningThresholdPercent,
    );
  }

  Map<String, dynamic> toJson() => {
        'maxSizeBytes': maxSizeBytes,
        'warningThresholdPercent': warningThresholdPercent,
      };

  factory CacheQuotaSettings.fromJson(Map<String, dynamic> json) {
    return CacheQuotaSettings(
      maxSizeBytes: json['maxSizeBytes'] as int? ?? (2 * 1024 * 1024 * 1024),
      warningThresholdPercent: json['warningThresholdPercent'] as int? ?? 90,
    );
  }
}

/// Cache usage statistics.
class CacheUsageStats {
  const CacheUsageStats({
    required this.totalSizeBytes,
    required this.quotaSizeBytes,
    required this.entryCount,
    required this.byBook,
    required this.byVoice,
    required this.hitRate,
  });

  final int totalSizeBytes;
  final int quotaSizeBytes;
  final int entryCount;
  final Map<String, int> byBook; // bookId -> size
  final Map<String, int> byVoice; // voiceId -> size
  final double hitRate;

  double get usagePercent =>
      quotaSizeBytes > 0 ? (totalSizeBytes / quotaSizeBytes * 100) : 0;

  String get totalSizeFormatted => _formatBytes(totalSizeBytes);
  String get quotaSizeFormatted => _formatBytes(quotaSizeBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Intelligent cache manager with multi-factor eviction scoring.
///
/// Features:
/// - User-configurable storage quota
/// - Multi-factor eviction scoring (recency, frequency, position, progress, voice)
/// - Proactive cache management
/// - Cache analytics
class IntelligentCacheManager implements AudioCache {
  IntelligentCacheManager({
    required Directory cacheDir,
    required this.metadataFile,
    CacheQuotaSettings? quotaSettings,
  })  : _cacheDir = cacheDir,
        _quotaSettings = quotaSettings ?? const CacheQuotaSettings();

  final Directory _cacheDir;
  final File metadataFile;
  CacheQuotaSettings _quotaSettings;

  /// Metadata for all cache entries.
  final Map<String, CacheEntryMetadata> _metadata = {};

  /// Hit/miss tracking for statistics.
  int _hits = 0;
  int _misses = 0;

  /// Eviction score calculator.
  final _scoreCalculator = const EvictionScoreCalculator();

  /// Stream controller for quota warnings.
  final _warningController = StreamController<String>.broadcast();

  /// Stream of quota warnings.
  Stream<String> get warnings => _warningController.stream;

  /// Current quota settings.
  CacheQuotaSettings get quotaSettings => _quotaSettings;

  /// Update quota settings.
  Future<void> setQuotaSettings(CacheQuotaSettings settings) async {
    _quotaSettings = settings;
    await _saveMetadata();

    // Evict if new quota is smaller
    await evictIfNeeded();
  }

  /// Initialize the cache manager by loading persisted metadata.
  Future<void> initialize() async {
    await _cacheDir.create(recursive: true);
    await _loadMetadata();
    await _syncWithFileSystem();
  }

  /// Get cache usage statistics.
  Future<CacheUsageStats> getUsageStats() async {
    final byBook = <String, int>{};
    final byVoice = <String, int>{};

    for (final entry in _metadata.values) {
      byBook[entry.bookId] = (byBook[entry.bookId] ?? 0) + entry.sizeBytes;
      byVoice[entry.voiceId] = (byVoice[entry.voiceId] ?? 0) + entry.sizeBytes;
    }

    final totalHits = _hits + _misses;
    final hitRate = totalHits > 0 ? _hits / totalHits : 0.0;

    return CacheUsageStats(
      totalSizeBytes: await getTotalSize(),
      quotaSizeBytes: _quotaSettings.maxSizeBytes,
      entryCount: _metadata.length,
      byBook: byBook,
      byVoice: byVoice,
      hitRate: hitRate,
    );
  }

  /// Register a new cache entry with metadata.
  Future<void> registerEntry({
    required CacheKey key,
    required int sizeBytes,
    required String bookId,
    required int segmentIndex,
    required int chapterIndex,
    required String engineType,
    required int audioDurationMs,
  }) async {
    final filename = key.toFilename();

    _metadata[filename] = CacheEntryMetadata(
      key: filename,
      sizeBytes: sizeBytes,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      accessCount: 1,
      bookId: bookId,
      voiceId: key.voiceId,
      segmentIndex: segmentIndex,
      chapterIndex: chapterIndex,
      engineType: engineType,
      audioDurationMs: audioDurationMs,
    );

    await _saveMetadata();
    await evictIfNeeded();
  }

  /// Evict entries to meet quota.
  Future<void> evictIfNeeded({EvictionContext? context}) async {
    final totalSize = await getTotalSize();
    if (totalSize <= _quotaSettings.maxSizeBytes) {
      // Check for warning threshold
      final warningThreshold = _quotaSettings.maxSizeBytes *
          _quotaSettings.warningThresholdPercent ~/
          100;
      if (totalSize > warningThreshold) {
        _warningController.add(
          'Cache usage at ${(totalSize / _quotaSettings.maxSizeBytes * 100).toStringAsFixed(0)}% of quota',
        );
      }
      return;
    }

    developer.log(
      '📦 Cache eviction needed: ${CacheUsageStats._formatBytes(totalSize)} > '
      '${CacheUsageStats._formatBytes(_quotaSettings.maxSizeBytes)}',
      name: 'IntelligentCacheManager',
    );

    // Build eviction context if not provided
    final ctx = context ?? _buildDefaultContext();

    // Score all entries
    final scoredEntries = _metadata.values.map((m) {
      return ScoredCacheEntry(
        metadata: m,
        score: _scoreCalculator.calculateScore(m, ctx),
      );
    }).toList();

    // Sort by score (lowest first = evict first)
    scoredEntries.sortByEvictionPriority();

    // Evict until under 90% of quota (leave some headroom)
    final targetSize = (_quotaSettings.maxSizeBytes * 0.9).round();
    var currentSize = totalSize;
    var evicted = 0;

    for (final entry in scoredEntries) {
      if (currentSize <= targetSize) break;
      
      // Skip pinned files - they are currently in use by prefetch
      if (_pinnedFiles.contains(entry.metadata.key)) {
        developer.log(
          '📌 Skipping pinned file: ${entry.metadata.key}',
          name: 'IntelligentCacheManager',
        );
        continue;
      }

      final file = File('${_cacheDir.path}/${entry.metadata.key}');
      try {
        if (await file.exists()) {
          await file.delete();
          currentSize -= entry.metadata.sizeBytes;
          _metadata.remove(entry.metadata.key);
          evicted++;

          developer.log(
            '🗑️ Evicted: ${entry.metadata.key} (score: ${entry.score.toStringAsFixed(2)})',
            name: 'IntelligentCacheManager',
          );
        }
      } catch (e) {
        developer.log(
          '❌ Failed to evict ${entry.metadata.key}: $e',
          name: 'IntelligentCacheManager',
        );
      }
    }

    developer.log(
      '📦 Eviction complete: removed $evicted entries, '
      'new size: ${CacheUsageStats._formatBytes(currentSize)}',
      name: 'IntelligentCacheManager',
    );

    await _saveMetadata();
  }

  /// Build default eviction context from current state.
  EvictionContext _buildDefaultContext() {
    int maxAccessCount = 1;
    for (final m in _metadata.values) {
      if (m.accessCount > maxAccessCount) {
        maxAccessCount = m.accessCount;
      }
    }

    return EvictionContext(
      currentVoiceId: '', // Will be set by caller if needed
      activeBookIds: {},
      bookReadingPositions: {},
      bookProgress: {},
      maxAccessCount: maxAccessCount,
    );
  }

  /// Prepare space for upcoming synthesis batch.
  Future<void> prepareForSynthesis({
    required int segmentCount,
    required int averageSegmentSizeBytes,
    EvictionContext? context,
  }) async {
    final estimatedSize = segmentCount * averageSegmentSizeBytes;
    final currentSize = await getTotalSize();
    final available = _quotaSettings.maxSizeBytes - currentSize;

    if (estimatedSize > available) {
      developer.log(
        '📦 Pre-emptive eviction: need ${CacheUsageStats._formatBytes(estimatedSize)}, '
        'available: ${CacheUsageStats._formatBytes(available)}',
        name: 'IntelligentCacheManager',
      );

      // Temporarily reduce quota to make room
      final tempSettings = _quotaSettings.copyWith(
        maxSizeBytes: _quotaSettings.maxSizeBytes - (estimatedSize - available),
      );
      final savedSettings = _quotaSettings;
      _quotaSettings = tempSettings;

      await evictIfNeeded(context: context);

      _quotaSettings = savedSettings;
    }
  }

  // ============= AudioCache interface implementation =============

  @override
  Future<File> fileFor(CacheKey key) async {
    await _cacheDir.create(recursive: true);
    return File('${_cacheDir.path}/${key.toFilename()}');
  }

  @override
  Future<bool> isReady(CacheKey key) async {
    final file = await fileFor(key);
    if (!await file.exists()) {
      _misses++;
      return false;
    }

    final stat = await file.stat();
    if (stat.size <= 44) {
      _misses++;
      return false;
    }

    _hits++;
    return true;
  }

  @override
  Future<void> markUsed(CacheKey key) async {
    final filename = key.toFilename();
    final entry = _metadata[filename];
    if (entry != null) {
      _metadata[filename] = entry.copyWith(
        lastAccessed: DateTime.now(),
        accessCount: entry.accessCount + 1,
      );
      // Don't save immediately - batch saves for performance
    } else {
      // Auto-register entry if not in metadata (supports legacy files)
      final file = File('${_cacheDir.path}/$filename');
      if (await file.exists()) {
        final stat = await file.stat();
        _metadata[filename] = CacheEntryMetadata(
          key: filename,
          sizeBytes: stat.size,
          createdAt: stat.changed,
          lastAccessed: DateTime.now(),
          accessCount: 1,
          bookId: 'unknown',
          voiceId: key.voiceId,
          segmentIndex: 0,
          chapterIndex: 0,
          engineType: _engineTypeForVoice(key.voiceId),
          audioDurationMs: _estimateDurationFromSize(stat.size),
        );
        await _saveMetadata();
      }
    }
  }

  /// Estimate engine type from voice ID.
  String _engineTypeForVoice(String voiceId) {
    if (voiceId.startsWith('kokoro')) return 'kokoro';
    if (voiceId.startsWith('piper')) return 'piper';
    if (voiceId.startsWith('supertonic')) return 'supertonic';
    return 'unknown';
  }

  /// Estimate duration from file size (WAV at 22050Hz mono 16-bit ≈ 44100 bytes/sec).
  int _estimateDurationFromSize(int bytes) {
    // Subtract WAV header (44 bytes), divide by bytes per second
    return ((bytes - 44) / 44100 * 1000).round().clamp(0, 3600000);
  }

  @override
  Future<void> pruneIfNeeded({CacheBudget budget = CacheBudget.defaultBudget}) async {
    // Use intelligent eviction instead of simple LRU
    await evictIfNeeded();
  }

  @override
  Future<void> deleteByPrefix(String prefix) async {
    if (!await _cacheDir.exists()) return;

    final toRemove = <String>[];
    await for (final entity in _cacheDir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if (name.startsWith(prefix)) {
          try {
            await entity.delete();
            toRemove.add(name);
          } catch (_) {}
        }
      }
    }

    for (final name in toRemove) {
      _metadata.remove(name);
    }

    await _saveMetadata();
  }

  @override
  Future<int> getTotalSize() async {
    if (!await _cacheDir.exists()) return 0;

    var total = 0;
    await for (final entity in _cacheDir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  @override
  Future<void> clear() async {
    if (!await _cacheDir.exists()) return;

    await for (final entity in _cacheDir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
    _metadata.clear();
    _hits = 0;
    _misses = 0;
    await _saveMetadata();
  }

  // ============= Persistence =============

  Future<void> _loadMetadata() async {
    try {
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        if (json['quota'] != null) {
          _quotaSettings = CacheQuotaSettings.fromJson(
            json['quota'] as Map<String, dynamic>,
          );
        }

        if (json['entries'] != null) {
          final entries = json['entries'] as Map<String, dynamic>;
          for (final e in entries.entries) {
            _metadata[e.key] = CacheEntryMetadata.fromJson(
              e.value as Map<String, dynamic>,
            );
          }
        }

        developer.log(
          '📦 Loaded ${_metadata.length} cache entries',
          name: 'IntelligentCacheManager',
        );
      }
    } catch (e) {
      developer.log(
        '⚠️ Failed to load cache metadata: $e',
        name: 'IntelligentCacheManager',
      );
    }
  }

  Future<void> _saveMetadata() async {
    try {
      final json = {
        'quota': _quotaSettings.toJson(),
        'entries': {
          for (final e in _metadata.entries) e.key: e.value.toJson(),
        },
      };
      await metadataFile.writeAsString(jsonEncode(json));
    } catch (e) {
      developer.log(
        '⚠️ Failed to save cache metadata: $e',
        name: 'IntelligentCacheManager',
      );
    }
  }

  /// Sync metadata with actual files on disk.
  Future<void> _syncWithFileSystem() async {
    if (!await _cacheDir.exists()) return;

    final existingFiles = <String, File>{};
    await for (final entity in _cacheDir.list()) {
      if (entity is File) {
        existingFiles[entity.uri.pathSegments.last] = entity;
      }
    }

    // Remove metadata for files that no longer exist
    final toRemove = <String>[];
    for (final key in _metadata.keys) {
      if (!existingFiles.containsKey(key)) {
        toRemove.add(key);
      }
    }

    for (final key in toRemove) {
      _metadata.remove(key);
    }

    if (toRemove.isNotEmpty) {
      developer.log(
        '🔄 Removed ${toRemove.length} stale metadata entries',
        name: 'IntelligentCacheManager',
      );
    }

    // Auto-register orphan files (files without metadata entries)
    // This supports upgrading from FileAudioCache to IntelligentCacheManager
    int orphansRegistered = 0;
    for (final entry in existingFiles.entries) {
      final filename = entry.key;
      final file = entry.value;
      
      // Skip metadata file itself
      if (filename.endsWith('.json')) continue;
      
      if (!_metadata.containsKey(filename)) {
        try {
          final stat = await file.stat();
          // Parse voice ID from filename (format: voiceId_hash.wav)
          final voiceId = _parseVoiceIdFromFilename(filename);
          
          _metadata[filename] = CacheEntryMetadata(
            key: filename,
            sizeBytes: stat.size,
            createdAt: stat.changed,
            lastAccessed: stat.accessed,
            accessCount: 1,
            bookId: 'unknown',
            voiceId: voiceId,
            segmentIndex: 0,
            chapterIndex: 0,
            engineType: _engineTypeForVoice(voiceId),
            audioDurationMs: _estimateDurationFromSize(stat.size),
          );
          orphansRegistered++;
        } catch (e) {
          developer.log(
            '⚠️ Failed to register orphan file: $filename - $e',
            name: 'IntelligentCacheManager',
          );
        }
      }
    }

    if (orphansRegistered > 0) {
      developer.log(
        '📦 Auto-registered $orphansRegistered orphan cache files',
        name: 'IntelligentCacheManager',
      );
    }

    if (toRemove.isNotEmpty || orphansRegistered > 0) {
      await _saveMetadata();
    }
  }

  /// Parse voice ID from cache filename.
  String _parseVoiceIdFromFilename(String filename) {
    // Filename format: voiceId_hash.wav
    // Voice IDs can contain underscores, so we need to handle that
    final withoutExtension = filename.replaceAll('.wav', '');
    final parts = withoutExtension.split('_');
    
    // Try to detect common voice ID patterns
    if (parts.isNotEmpty) {
      // Kokoro: kokoro_af, kokoro_af_bella, etc.
      if (parts[0] == 'kokoro' && parts.length >= 2) {
        // Find where the hash starts (last part that looks like a hash)
        for (int i = parts.length - 1; i >= 2; i--) {
          if (parts[i].length >= 10) {
            return parts.sublist(0, i).join('_');
          }
        }
        return parts.sublist(0, parts.length - 1).join('_');
      }
      // Supertonic: supertonic_m1, supertonic_f2, etc.
      if (parts[0] == 'supertonic' && parts.length >= 2) {
        return '${parts[0]}_${parts[1]}';
      }
      // Piper: piper_en_US-lessac-medium, etc.
      if (parts[0] == 'piper' && parts.length >= 2) {
        return parts.sublist(0, parts.length - 1).join('_').replaceAll('_', ':');
      }
    }
    return 'unknown';
  }
  
  // ============ File Pinning (for coordination with prefetch) ============
  
  /// Set of pinned filenames that should not be evicted.
  final Set<String> _pinnedFiles = {};
  
  @override
  bool pin(CacheKey key) {
    final filename = _filenameForKey(key);
    if (_pinnedFiles.contains(filename)) return false;
    _pinnedFiles.add(filename);
    return true;
  }
  
  @override
  bool unpin(CacheKey key) {
    final filename = _filenameForKey(key);
    return _pinnedFiles.remove(filename);
  }
  
  @override
  bool isPinned(CacheKey key) {
    return _pinnedFiles.contains(_filenameForKey(key));
  }
  
  String _filenameForKey(CacheKey key) {
    return key.toFilename();
  }

  /// Dispose resources.
  void dispose() {
    _warningController.close();
    _pinnedFiles.clear();
  }
}
