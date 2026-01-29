import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';

import 'aac_compression_service.dart';
import 'audio_cache.dart';
import 'cache_entry_metadata.dart';
import 'cache_metadata_storage.dart';

/// User-configurable cache quota settings.
class CacheQuotaSettings {
  const CacheQuotaSettings({
    this.maxSizeBytes = 2 * 1024 * 1024 * 1024, // 2 GB default
    this.warningThresholdPercent = 90,
    this.compressionThresholdPercent = 80,
  });

  /// Maximum cache size in bytes.
  final int maxSizeBytes;

  /// Percentage of quota at which to warn user.
  final int warningThresholdPercent;

  /// Percentage of quota at which to auto-compress WAV files.
  final int compressionThresholdPercent;

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
      compressionThresholdPercent: compressionThresholdPercent,
    );
  }

  Map<String, dynamic> toJson() => {
        'maxSizeBytes': maxSizeBytes,
        'warningThresholdPercent': warningThresholdPercent,
        'compressionThresholdPercent': compressionThresholdPercent,
      };

  factory CacheQuotaSettings.fromJson(Map<String, dynamic> json) {
    return CacheQuotaSettings(
      maxSizeBytes: json['maxSizeBytes'] as int? ?? (2 * 1024 * 1024 * 1024),
      warningThresholdPercent: json['warningThresholdPercent'] as int? ?? 90,
      compressionThresholdPercent: json['compressionThresholdPercent'] as int? ?? 80,
    );
  }
}

/// Cache usage statistics.
class CacheUsageStats {
  const CacheUsageStats({
    required this.totalSizeBytes,
    required this.quotaSizeBytes,
    required this.entryCount,
    required this.compressedCount,
    required this.byBook,
    required this.byVoice,
    required this.hitRate,
  });

  final int totalSizeBytes;
  final int quotaSizeBytes;
  final int entryCount;
  final int compressedCount; // Number of M4A (compressed) files
  final Map<String, int> byBook; // bookId -> size
  final Map<String, int> byVoice; // voiceId -> size
  final double hitRate;

  /// Number of uncompressed (WAV) files
  int get uncompressedCount => entryCount - compressedCount;

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
/// - Pluggable storage backend (JSON or SQLite)
class IntelligentCacheManager implements AudioCache {
  IntelligentCacheManager({
    required Directory cacheDir,
    required CacheMetadataStorage storage,
    CacheQuotaSettings? quotaSettings,
  })  : _cacheDir = cacheDir,
        _storage = storage,
        _quotaSettings = quotaSettings ?? const CacheQuotaSettings();

  final Directory _cacheDir;
  final CacheMetadataStorage _storage;
  CacheQuotaSettings _quotaSettings;

  /// Get the storage backend (for compression and other operations).
  CacheMetadataStorage get storage => _storage;

  // NO MORE _metadata! Database is the single source of truth.

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
    await _storage.saveQuotaSettings(settings);

    // Evict if new quota is smaller
    await evictIfNeeded();
  }

  /// Initialize the cache manager.
  /// 
  /// Simplified: just loads quota settings and syncs with filesystem.
  /// No in-memory cache of entries - DB is queried directly.
  Future<void> initialize() async {
    await _cacheDir.create(recursive: true);

    final quota = await _storage.loadQuotaSettings();
    if (quota != null) {
      _quotaSettings = quota;
    }

    final entryCount = await _storage.getEntryCount();
    developer.log(
      '📦 Database has $entryCount cache entries',
      name: 'IntelligentCacheManager',
    );

    await _syncWithFileSystem();
  }

  /// Get cache usage statistics.
  /// 
  /// Uses filesystem scan for compression counts (more accurate than DB)
  /// because DB state can become stale during background compression.
  Future<CacheUsageStats> getUsageStats() async {
    // Use storage backend for book/voice aggregation
    final byBook = await _storage.getSizeByBook();
    final byVoice = await _storage.getSizeByVoice();
    
    // Scan filesystem for accurate compression counts
    // DB compression_state can be stale if entries weren't updated properly
    int m4aCount = 0;
    int wavCount = 0;
    if (await _cacheDir.exists()) {
      await for (final entity in _cacheDir.list()) {
        if (entity is File) {
          final path = entity.path;
          if (path.endsWith('.m4a')) {
            m4aCount++;
          } else if (path.endsWith('.wav')) {
            wavCount++;
          }
        }
      }
    }

    final totalHits = _hits + _misses;
    final hitRate = totalHits > 0 ? _hits / totalHits : 0.0;
    
    // Total entry count from filesystem (more accurate)
    final entryCount = m4aCount + wavCount;

    return CacheUsageStats(
      totalSizeBytes: await getTotalSize(),
      quotaSizeBytes: _quotaSettings.maxSizeBytes,
      entryCount: entryCount,
      compressedCount: m4aCount,
      byBook: byBook,
      byVoice: byVoice,
      hitRate: hitRate,
    );
  }

  @override
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

    final entry = CacheEntryMetadata(
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

    // DB is the single source of truth
    await _storage.upsertEntry(entry);
    await evictIfNeeded();
  }

  /// Evict entries to meet quota.
  /// First tries to compress WAV files, then evicts if still over quota.
  Future<void> evictIfNeeded({EvictionContext? context}) async {
    var totalSize = await getTotalSize();
    
    // Check compression threshold (80% default)
    final compressionThreshold = _quotaSettings.maxSizeBytes *
        _quotaSettings.compressionThresholdPercent ~/
        100;
    
    // If over compression threshold, compress WAV files first
    if (totalSize > compressionThreshold) {
      final compressed = await _compressUncompressedFiles();
      if (compressed > 0) {
        totalSize = await getTotalSize();
        developer.log(
          '🗜️ Auto-compressed $compressed WAV files, new size: '
          '${CacheUsageStats._formatBytes(totalSize)}',
          name: 'IntelligentCacheManager',
        );
      }
    }
    
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
    final ctx = context ?? await _buildDefaultContext();

    // Get all entries from database
    final allEntries = await _storage.getAllEntries();
    
    // Score all entries - WAV files get lower scores (evict first)
    final scoredEntries = allEntries.map((m) {
      var score = _scoreCalculator.calculateScore(m, ctx);
      // Penalty for WAV files (prefer to evict over compressed)
      if (m.key.endsWith('.wav')) {
        score *= 0.5; // Lower score = higher eviction priority
      }
      return ScoredCacheEntry(
        metadata: m,
        score: score,
      );
    }).toList();

    // Sort by score (lowest first = evict first)
    scoredEntries.sortByEvictionPriority();

    // Evict until under 90% of quota (leave some headroom)
    final targetSize = (_quotaSettings.maxSizeBytes * 0.9).round();
    var currentSize = totalSize;
    var evicted = 0;
    final evictedKeys = <String>[];

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
          evictedKeys.add(entry.metadata.key);
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

    if (evictedKeys.isNotEmpty) {
      await _storage.removeEntries(evictedKeys);
    }
  }

  /// Compress all uncompressed WAV files in the cache.
  /// Returns the number of files compressed.
  Future<int> _compressUncompressedFiles() async {
    final compressionService = AacCompressionService();
    int compressed = 0;
    
    // Get all WAV entries from database
    final wavEntries = await _storage.getUncompressedEntries();
    
    if (wavEntries.isEmpty) return 0;
    
    developer.log(
      '🗜️ Auto-compressing ${wavEntries.length} WAV files...',
      name: 'IntelligentCacheManager',
    );
    
    for (final entry in wavEntries) {
      // Skip pinned files
      if (_pinnedFiles.contains(entry.key)) continue;
      
      final wavFile = File('${_cacheDir.path}/${entry.key}');
      if (!await wavFile.exists()) continue;
      
      try {
        final result = await compressionService.compressFile(
          wavFile,
          deleteOriginal: true,
        );
        
        if (result != null) {
          compressed++;

          // Update DB: replace old WAV entry with new M4A entry
          final m4aKey = entry.key.replaceAll('.wav', '.m4a');
          final m4aStat = await result.stat();

          final newEntry = CacheEntryMetadata(
            key: m4aKey,
            sizeBytes: m4aStat.size,
            createdAt: entry.createdAt,
            lastAccessed: entry.lastAccessed,
            accessCount: entry.accessCount,
            bookId: entry.bookId,
            voiceId: entry.voiceId,
            segmentIndex: entry.segmentIndex,
            chapterIndex: entry.chapterIndex,
            engineType: entry.engineType,
            audioDurationMs: entry.audioDurationMs,
            compressionState: CompressionState.m4a,
          );
          await _storage.replaceEntry(oldKey: entry.key, newEntry: newEntry);
        }
      } catch (e) {
        developer.log(
          '⚠️ Failed to compress ${entry.key}: $e',
          name: 'IntelligentCacheManager',
        );
      }
    }

    return compressed;
  }

  /// Build default eviction context from current state.
  Future<EvictionContext> _buildDefaultContext() async {
    int maxAccessCount = 1;
    final entries = await _storage.getAllEntries();
    for (final m in entries) {
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
  Future<File?> playableFileFor(CacheKey key) async {
    final wavFile = await fileFor(key);
    final m4aPath = wavFile.path.replaceAll('.wav', '.m4a');
    final m4aFile = File(m4aPath);
    
    // Prefer M4A (compressed) if it exists
    if (await m4aFile.exists()) {
      final stat = await m4aFile.stat();
      if (stat.size > 0) return m4aFile;
    }
    
    // Fall back to WAV
    if (await wavFile.exists()) {
      final stat = await wavFile.stat();
      if (stat.size > kWavHeaderSize) return wavFile;
    }
    
    return null;
  }

  @override
  Directory get directory => _cacheDir;

  @override
  Future<bool> isReady(CacheKey key) async {
    final wavFile = await fileFor(key);
    final m4aPath = wavFile.path.replaceAll('.wav', '.m4a');
    final m4aFile = File(m4aPath);
    
    // Check M4A first (compressed version)
    if (await m4aFile.exists()) {
      final stat = await m4aFile.stat();
      if (stat.size > 0) {
        _hits++;
        return true;
      }
    }
    
    // Check WAV (uncompressed)
    if (await wavFile.exists()) {
      final stat = await wavFile.stat();
      if (stat.size > kWavHeaderSize) {
        _hits++;
        return true;
      }
    }

    _misses++;
    return false;
  }

  @override
  Future<void> markUsed(CacheKey key) async {
    final filename = key.toFilename();
    final entry = await _storage.getEntry(filename);
    if (entry != null) {
      final updated = entry.copyWith(
        lastAccessed: DateTime.now(),
        accessCount: entry.accessCount + 1,
      );
      await _storage.upsertEntry(updated);
    } else {
      // Auto-register entry if not in DB (supports legacy files)
      final file = File('${_cacheDir.path}/$filename');
      if (await file.exists()) {
        final stat = await file.stat();
        final newEntry = CacheEntryMetadata(
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
        await _storage.upsertEntry(newEntry);
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

  /// Q3: Bytes per second for WAV at 22050Hz mono 16-bit.
  static const _wavBytesPerSecond = 44100;

  /// Estimate duration from file size (WAV at 22050Hz mono 16-bit ≈ 44100 bytes/sec).
  int _estimateDurationFromSize(int bytes) {
    // Subtract WAV header, divide by bytes per second
    return ((bytes - kWavHeaderSize) / _wavBytesPerSecond * 1000).round().clamp(0, 3600000);
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

    if (toRemove.isNotEmpty) {
      await _storage.removeEntries(toRemove);
    }
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
    _hits = 0;
    _misses = 0;
    await _storage.clearAll();
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

    // Get all entries from DB to compare with filesystem
    final dbEntries = await _storage.getAllEntries();
    final dbKeys = dbEntries.map((e) => e.key).toSet();

    // Remove metadata for files that no longer exist
    final toRemove = <String>[];
    for (final key in dbKeys) {
      if (!existingFiles.containsKey(key)) {
        toRemove.add(key);
      }
    }

    if (toRemove.isNotEmpty) {
      await _storage.removeEntries(toRemove);
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
      
      if (!dbKeys.contains(filename)) {
        try {
          final stat = await file.stat();
          // Parse voice ID from filename (format: voiceId_hash.wav)
          final voiceId = _parseVoiceIdFromFilename(filename);
          
          final newEntry = CacheEntryMetadata(
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
          await _storage.upsertEntry(newEntry);
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

  /// Compress a single cache entry by filename without blocking UI.
  /// 
  /// Uses native platform codecs (MediaCodec on Android, AVFoundation on iOS)
  /// which run compression on a background thread, so this won't cause jank.
  /// Atomically updates metadata to ensure consistency.
  /// 
  /// NOTE: Platform channels only work on the main isolate, so we can't use
  /// Isolate.run() here. The native encoders handle background threading.
  /// 
  /// [filename] should be just the filename (e.g., "kokoro_af_1_00_hash.wav"),
  /// not the full path.
  /// 
  /// Returns true if compression was performed and successful.
  /// Returns false if file doesn't exist, is already compressed, or is pinned.
  Future<bool> compressEntryByFilenameInBackground(String filename) async {
    // DEBUG: Use print to ensure visibility in logcat
    print('[COMPRESSION] compressEntryByFilenameInBackground called: $filename');
    print('[COMPRESSION] _pinnedFiles: $_pinnedFiles');
    
    // Skip if not in DB
    final entry = await _storage.getEntry(filename);
    if (entry == null) {
      print('[COMPRESSION] ⚠️ SKIPPED (not in DB): $filename');
      developer.log(
        '⚠️ Compression skipped (not in DB): $filename',
        name: 'IntelligentCacheManager',
      );
      return false;
    }
    
    // Skip if already compressed
    if (filename.endsWith('.m4a') || filename.endsWith('.aac')) {
      print('[COMPRESSION] ⚠️ SKIPPED (already compressed): $filename');
      developer.log(
        '⚠️ Compression skipped (already compressed): $filename',
        name: 'IntelligentCacheManager',
      );
      return false;
    }
    
    // Skip if pinned (in use by prefetch)
    if (_pinnedFiles.contains(filename)) {
      print('[COMPRESSION] ⚠️ SKIPPED (pinned): $filename');
      developer.log(
        '⚠️ Compression skipped (file pinned for playback): $filename',
        name: 'IntelligentCacheManager',
      );
      return false;
    }
    
    final wavFile = File('${_cacheDir.path}/$filename');
    if (!await wavFile.exists()) {
      print('[COMPRESSION] ⚠️ SKIPPED (file not found): $filename');
      developer.log(
        '⚠️ Compression skipped (file not found): $filename',
        name: 'IntelligentCacheManager',
      );
      return false;
    }
    
    print('[COMPRESSION] ✅ All checks passed, starting compression for: $filename');
    try {
      // Step 1: Mark as compressing in DB (prevents concurrent compression)
      await _storage.updateCompressionState(
        filename,
        CompressionState.compressing,
        compressionStartedAt: DateTime.now(),
      );
      
      print('[COMPRESSION] Marked as compressing, starting native codec...');
      developer.log(
        '⏳ Starting background compression for: $filename',
        name: 'IntelligentCacheManager',
      );
      
      // Step 2: Run compression using native platform codec
      // NOTE: Do NOT use Isolate.run() here - platform channels (flutter_audio_toolkit)
      // only work on the main isolate. The native MediaCodec/AVFoundation encoder
      // already runs on a background thread, so this is still non-blocking.
      final compressionService = AacCompressionService();
      final m4aFile = await compressionService.compressFile(
        wavFile,
        deleteOriginal: true,
      );
      
      if (m4aFile == null) {
        // Compression failed - mark as failed in DB
        print('[COMPRESSION] ❌ Native codec returned null for: $filename');
        await _storage.updateCompressionState(
          filename,
          CompressionState.failed,
        );
        developer.log(
          '❌ Compression failed for $filename',
          name: 'IntelligentCacheManager',
        );
        return false;
      }
      
      print('[COMPRESSION] ✅ Native codec succeeded for: $filename');
      // Step 3: Update metadata atomically (DB-first approach)
      final m4aKey = filename.replaceAll('.wav', '.m4a');
      final m4aStat = await m4aFile.stat();
      
      final newEntry = CacheEntryMetadata(
        key: m4aKey,
        sizeBytes: m4aStat.size,
        createdAt: entry.createdAt,
        lastAccessed: entry.lastAccessed,
        accessCount: entry.accessCount,
        bookId: entry.bookId,
        voiceId: entry.voiceId,
        segmentIndex: entry.segmentIndex,
        chapterIndex: entry.chapterIndex,
        engineType: entry.engineType,
        audioDurationMs: entry.audioDurationMs,
        compressionState: CompressionState.m4a,
        compressionStartedAt: null,
      );
      
      // Replace in DB (atomic: delete WAV, insert M4A)
      await _storage.replaceEntry(oldKey: filename, newEntry: newEntry);
      
      developer.log(
        '✅ Background compressed $filename → $m4aKey '
        '(${entry.sizeBytes ~/ 1024}KB → ${newEntry.sizeBytes ~/ 1024}KB)',
        name: 'IntelligentCacheManager',
      );
      
      return true;
    } catch (e) {
      developer.log(
        '❌ Background compression failed for $filename: $e',
        name: 'IntelligentCacheManager',
      );
      // Try to mark as failed in DB
      await _storage.updateCompressionState(
        filename,
        CompressionState.failed,
      );
      return false;
    }
  }
  
  /// Compress a single cache entry in background without blocking.
  /// 
  /// Uses native platform codecs which handle background threading internally.
  /// Atomically updates metadata to ensure consistency.
  /// 
  /// Returns true if compression was performed and successful.
  /// Returns false if file doesn't exist, is already compressed, or is pinned.
  Future<bool> compressEntryInBackground(CacheKey key) async {
    final filename = key.toFilename();
    return compressEntryByFilenameInBackground(filename);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Reconciliation support methods
  // ══════════════════════════════════════════════════════════════════════════

  /// Get all metadata entries (for reconciliation).
  /// Queries the database directly.
  Future<Map<String, CacheEntryMetadata>> getAllMetadata() async {
    final entries = await _storage.getAllEntries();
    return {for (final e in entries) e.key: e};
  }

  /// Remove a single entry by key (for reconciliation - ghost entry cleanup).
  Future<void> removeEntry(String key) async {
    await _storage.removeEntries([key]);
  }

  /// Register an orphan entry discovered during reconciliation.
  ///
  /// This is used to add entries for files that exist on disk
  /// but don't have database entries.
  Future<void> registerOrphanEntry(CacheEntryMetadata entry) async {
    await _storage.upsertEntry(entry);
  }

  /// Dispose resources.
  void dispose() {
    _warningController.close();
    _pinnedFiles.clear();
  }
}
