import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:tts_engines/tts_engines.dart';

/// Result of a cache reconciliation operation.
class ReconciliationResult {
  const ReconciliationResult({
    required this.filesScanned,
    required this.entriesScanned,
    required this.orphanFilesRegistered,
    required this.ghostEntriesRemoved,
    required this.compressionStateFixed,
    required this.duration,
    this.errors = const [],
  });

  /// Number of files found on disk.
  final int filesScanned;

  /// Number of entries found in database.
  final int entriesScanned;

  /// Files on disk that had no database entry (now registered).
  final int orphanFilesRegistered;

  /// Database entries that had no corresponding file (now removed).
  final int ghostEntriesRemoved;

  /// Entries where compression state didn't match file extension (now fixed).
  final int compressionStateFixed;

  /// Time taken for reconciliation.
  final Duration duration;

  /// Any errors encountered during reconciliation.
  final List<String> errors;

  /// Total number of discrepancies found and fixed.
  int get discrepanciesFixed =>
      orphanFilesRegistered + ghostEntriesRemoved + compressionStateFixed;

  /// Whether any changes were made.
  bool get hadChanges => discrepanciesFixed > 0;

  /// Summary string for logging.
  String get summary =>
      'Files: $filesScanned, DB entries: $entriesScanned, '
      'Orphans registered: $orphanFilesRegistered, '
      'Ghosts removed: $ghostEntriesRemoved, '
      'Compression fixed: $compressionStateFixed, '
      'Duration: ${duration.inMilliseconds}ms';

  @override
  String toString() => 'ReconciliationResult($summary)';
}

/// Service for reconciling cache state between disk and database.
///
/// This service ensures that:
/// 1. Every file on disk has a corresponding database entry (orphan recovery)
/// 2. Every database entry has a corresponding file (ghost cleanup)
/// 3. Compression state in database matches actual file extension
///
/// Usage:
/// ```dart
/// final service = CacheReconciliationService(cache: cacheManager);
/// final result = await service.reconcile();
/// print('Reconciliation: ${result.summary}');
/// ```
class CacheReconciliationService {
  CacheReconciliationService({
    required this.cache,
  });

  /// The cache manager to reconcile.
  final IntelligentCacheManager cache;

  /// Timer for periodic reconciliation.
  Timer? _periodicTimer;

  /// Whether a reconciliation is currently running.
  bool _isRunning = false;

  /// Perform full reconciliation between disk and database.
  ///
  /// If [dryRun] is true, only reports what would be changed without making changes.
  Future<ReconciliationResult> reconcile({bool dryRun = false}) async {
    if (_isRunning) {
      developer.log(
        '⚠️ Reconciliation already running, skipping',
        name: 'CacheReconciliation',
      );
      return const ReconciliationResult(
        filesScanned: 0,
        entriesScanned: 0,
        orphanFilesRegistered: 0,
        ghostEntriesRemoved: 0,
        compressionStateFixed: 0,
        duration: Duration.zero,
      );
    }

    _isRunning = true;
    final stopwatch = Stopwatch()..start();
    final errors = <String>[];

    try {
      developer.log(
        '🔄 Starting cache reconciliation${dryRun ? ' (dry run)' : ''}...',
        name: 'CacheReconciliation',
      );

      // Step 1: Scan disk files
      final diskFiles = await _scanDiskFiles();
      developer.log(
        '📂 Found ${diskFiles.length} files on disk',
        name: 'CacheReconciliation',
      );

      // Step 2: Get database entries (using cache's internal metadata)
      final dbEntries = cache.getAllMetadata();
      developer.log(
        '🗃️ Found ${dbEntries.length} entries in database',
        name: 'CacheReconciliation',
      );

      // Step 3: Find orphan files (on disk but not in DB)
      final orphanFiles = _findOrphanFiles(diskFiles, dbEntries);

      // Step 4: Find ghost entries (in DB but not on disk)
      final ghostEntries = _findGhostEntries(diskFiles, dbEntries);

      // Step 5: Find compression state mismatches
      final compressionMismatches =
          _findCompressionMismatches(diskFiles, dbEntries);

      developer.log(
        '🔍 Discrepancies: ${orphanFiles.length} orphans, '
        '${ghostEntries.length} ghosts, '
        '${compressionMismatches.length} compression mismatches',
        name: 'CacheReconciliation',
      );

      // Step 6: Fix discrepancies (unless dry run)
      int orphansRegistered = 0;
      int ghostsRemoved = 0;
      int compressionFixed = 0;

      if (!dryRun) {
        // Register orphan files
        for (final filename in orphanFiles) {
          try {
            await _registerOrphanFile(filename, diskFiles[filename]!);
            orphansRegistered++;
          } catch (e) {
            errors.add('Failed to register orphan $filename: $e');
          }
        }

        // Remove ghost entries
        for (final key in ghostEntries) {
          try {
            await cache.removeEntry(key);
            ghostsRemoved++;
          } catch (e) {
            errors.add('Failed to remove ghost $key: $e');
          }
        }

        // Fix compression state mismatches
        for (final entry in compressionMismatches) {
          try {
            await _fixCompressionState(entry.key, entry.value, diskFiles);
            compressionFixed++;
          } catch (e) {
            errors.add('Failed to fix compression state for ${entry.key}: $e');
          }
        }
      } else {
        orphansRegistered = orphanFiles.length;
        ghostsRemoved = ghostEntries.length;
        compressionFixed = compressionMismatches.length;
      }

      stopwatch.stop();

      final result = ReconciliationResult(
        filesScanned: diskFiles.length,
        entriesScanned: dbEntries.length,
        orphanFilesRegistered: orphansRegistered,
        ghostEntriesRemoved: ghostsRemoved,
        compressionStateFixed: compressionFixed,
        duration: stopwatch.elapsed,
        errors: errors,
      );

      developer.log(
        '✅ Reconciliation complete: ${result.summary}',
        name: 'CacheReconciliation',
      );

      return result;
    } catch (e) {
      stopwatch.stop();
      developer.log(
        '❌ Reconciliation failed: $e',
        name: 'CacheReconciliation',
      );
      errors.add('Reconciliation failed: $e');

      return ReconciliationResult(
        filesScanned: 0,
        entriesScanned: 0,
        orphanFilesRegistered: 0,
        ghostEntriesRemoved: 0,
        compressionStateFixed: 0,
        duration: stopwatch.elapsed,
        errors: errors,
      );
    } finally {
      _isRunning = false;
    }
  }

  /// Start periodic reconciliation.
  ///
  /// Runs reconciliation at the specified [interval].
  /// Only runs if app is idle (no reconciliation already running).
  void startPeriodic({
    Duration interval = const Duration(hours: 6),
  }) {
    stopPeriodic();

    developer.log(
      '⏰ Starting periodic reconciliation (every ${interval.inHours}h)',
      name: 'CacheReconciliation',
    );

    _periodicTimer = Timer.periodic(interval, (_) async {
      if (!_isRunning) {
        developer.log(
          '⏰ Running periodic reconciliation...',
          name: 'CacheReconciliation',
        );
        await reconcile();
      }
    });
  }

  /// Stop periodic reconciliation.
  void stopPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Dispose the service and stop periodic reconciliation.
  void dispose() {
    stopPeriodic();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Scan all audio files in the cache directory.
  Future<Map<String, File>> _scanDiskFiles() async {
    final cacheDir = cache.directory;
    final files = <String, File>{};

    if (!await cacheDir.exists()) return files;

    await for (final entity in cacheDir.list()) {
      if (entity is File) {
        final filename = entity.uri.pathSegments.last;
        // Only include audio files
        if (filename.endsWith('.wav') || filename.endsWith('.m4a')) {
          files[filename] = entity;
        }
      }
    }

    return files;
  }

  /// Find files on disk that don't have database entries.
  List<String> _findOrphanFiles(
    Map<String, File> diskFiles,
    Map<String, CacheEntryMetadata> dbEntries,
  ) {
    final orphans = <String>[];

    for (final filename in diskFiles.keys) {
      // Check if DB has entry for this file (with either extension)
      final wavKey = filename.replaceAll('.m4a', '.wav');
      final m4aKey = filename.replaceAll('.wav', '.m4a');

      if (!dbEntries.containsKey(filename) &&
          !dbEntries.containsKey(wavKey) &&
          !dbEntries.containsKey(m4aKey)) {
        orphans.add(filename);
      }
    }

    return orphans;
  }

  /// Find database entries that don't have corresponding files.
  List<String> _findGhostEntries(
    Map<String, File> diskFiles,
    Map<String, CacheEntryMetadata> dbEntries,
  ) {
    final ghosts = <String>[];

    for (final entry in dbEntries.entries) {
      final key = entry.key;
      // Check if file exists (with either extension)
      final wavKey = key.replaceAll('.m4a', '.wav');
      final m4aKey = key.replaceAll('.wav', '.m4a');

      if (!diskFiles.containsKey(key) &&
          !diskFiles.containsKey(wavKey) &&
          !diskFiles.containsKey(m4aKey)) {
        ghosts.add(key);
      }
    }

    return ghosts;
  }

  /// Find entries where compression state doesn't match file extension.
  List<MapEntry<String, CacheEntryMetadata>> _findCompressionMismatches(
    Map<String, File> diskFiles,
    Map<String, CacheEntryMetadata> dbEntries,
  ) {
    final mismatches = <MapEntry<String, CacheEntryMetadata>>[];

    for (final entry in dbEntries.entries) {
      final key = entry.key;
      final metadata = entry.value;

      // Determine actual file extension
      final m4aKey = key.replaceAll('.wav', '.m4a');
      final wavKey = key.replaceAll('.m4a', '.wav');

      final hasM4a = diskFiles.containsKey(m4aKey);
      final hasWav = diskFiles.containsKey(wavKey);

      // Determine what the compression state SHOULD be
      CompressionState? expectedState;
      if (hasM4a && !hasWav) {
        expectedState = CompressionState.m4a;
      } else if (hasWav && !hasM4a) {
        expectedState = CompressionState.wav;
      } else if (hasM4a && hasWav) {
        // Both exist - prefer m4a
        expectedState = CompressionState.m4a;
      }

      // Check for mismatch
      if (expectedState != null && metadata.compressionState != expectedState) {
        mismatches.add(MapEntry(key, metadata));
      }
    }

    return mismatches;
  }

  /// Register an orphan file in the database.
  Future<void> _registerOrphanFile(String filename, File file) async {
    final stat = await file.stat();
    final voiceId = _parseVoiceIdFromFilename(filename);
    final isCompressed = filename.endsWith('.m4a');

    final entry = CacheEntryMetadata(
      key: filename,
      sizeBytes: stat.size,
      createdAt: stat.changed,
      lastAccessed: stat.accessed,
      accessCount: 1,
      bookId: 'unknown', // Can't determine from filename
      voiceId: voiceId,
      segmentIndex: 0, // Can't determine from filename
      chapterIndex: 0, // Can't determine from filename
      engineType: _engineTypeForVoice(voiceId),
      audioDurationMs: _estimateDurationFromSize(stat.size, isCompressed),
      compressionState: isCompressed ? CompressionState.m4a : CompressionState.wav,
    );

    // Use the cache manager's internal method to register
    await cache.registerOrphanEntry(entry);
  }

  /// Fix compression state mismatch for an entry.
  Future<void> _fixCompressionState(
    String key,
    CacheEntryMetadata metadata,
    Map<String, File> diskFiles,
  ) async {
    final m4aKey = key.replaceAll('.wav', '.m4a');
    final wavKey = key.replaceAll('.m4a', '.wav');

    final hasM4a = diskFiles.containsKey(m4aKey);
    final hasWav = diskFiles.containsKey(wavKey);

    CompressionState newState;
    String newKey;
    File file;

    if (hasM4a) {
      newState = CompressionState.m4a;
      newKey = m4aKey;
      file = diskFiles[m4aKey]!;
    } else if (hasWav) {
      newState = CompressionState.wav;
      newKey = wavKey;
      file = diskFiles[wavKey]!;
    } else {
      // No file exists - this is a ghost entry, should have been caught earlier
      return;
    }

    final stat = await file.stat();
    final updated = metadata.copyWith(
      key: newKey,
      sizeBytes: stat.size,
      compressionState: newState,
    );

    // Remove old entry and add new one
    await cache.removeEntry(key);
    await cache.registerOrphanEntry(updated);
  }

  /// Parse voice ID from cache filename.
  String _parseVoiceIdFromFilename(String filename) {
    // Filename format: voiceId_hash.wav or voiceId_hash.m4a
    final withoutExtension = filename.replaceAll('.wav', '').replaceAll('.m4a', '');
    final parts = withoutExtension.split('_');

    if (parts.isEmpty) return 'unknown';

    // Kokoro: kokoro_af, kokoro_af_bella, etc.
    if (parts[0] == 'kokoro' && parts.length >= 2) {
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
      for (int i = parts.length - 1; i >= 2; i--) {
        if (parts[i].length >= 10) {
          return parts.sublist(0, i).join('_');
        }
      }
      return parts.sublist(0, parts.length - 1).join('_');
    }

    // Fallback: first part
    return parts[0];
  }

  /// Determine engine type from voice ID.
  String _engineTypeForVoice(String voiceId) {
    if (voiceId.startsWith('kokoro')) return 'kokoro';
    if (voiceId.startsWith('piper')) return 'piper';
    if (voiceId.startsWith('supertonic')) return 'supertonic';
    return 'unknown';
  }

  /// Estimate audio duration from file size.
  int _estimateDurationFromSize(int bytes, bool isCompressed) {
    if (isCompressed) {
      // M4A: roughly 16kbps for speech = 2KB/s
      return (bytes / 2000 * 1000).round().clamp(0, 3600000);
    } else {
      // WAV at 22050Hz mono 16-bit = 44100 bytes/sec
      const wavBytesPerSecond = 44100;
      const wavHeaderSize = 44;
      return ((bytes - wavHeaderSize) / wavBytesPerSecond * 1000)
          .round()
          .clamp(0, 3600000);
    }
  }
}
