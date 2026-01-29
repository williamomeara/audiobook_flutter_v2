import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter_audio_toolkit/flutter_audio_toolkit.dart';

import 'cache_entry_metadata.dart';
import 'cache_metadata_storage.dart';

/// Result of compressing the audio cache.
class AacCompressionResult {
  const AacCompressionResult({
    required this.filesCompressed,
    required this.filesFailed,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.durationMs,
  });

  /// Number of files successfully compressed.
  final int filesCompressed;

  /// Number of files that failed to compress.
  final int filesFailed;

  /// Total size of original WAV files in bytes.
  final int originalSizeBytes;

  /// Total size of compressed M4A files in bytes.
  final int compressedSizeBytes;

  /// Total compression duration in milliseconds.
  final int durationMs;

  /// Space saved in bytes.
  int get spaceSavedBytes => originalSizeBytes - compressedSizeBytes;

  /// Compression ratio (e.g., 17.0 = 17x compression).
  double get compressionRatio =>
      compressedSizeBytes > 0 ? originalSizeBytes / compressedSizeBytes : 1.0;

  /// Percentage of space saved.
  double get savingsPercent =>
      originalSizeBytes > 0 ? (spaceSavedBytes / originalSizeBytes * 100) : 0.0;

  /// Format space saved as human-readable string.
  String get formattedSavings => _formatBytes(spaceSavedBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Service for compressing WAV audio cache to AAC/M4A format.
///
/// Uses flutter_audio_toolkit for native platform-optimized compression
/// via MediaCodec (Android) and AVFoundation (iOS).
/// 
/// Benefits over FFmpeg:
/// - Zero app size impact (uses OS built-in encoders)
/// - Hardware-accelerated encoding (faster, less battery)
/// - Better quality at low bitrates
/// - No third-party binary maintenance
class AacCompressionService {
  AacCompressionService({
    this.bitrate = 64, // 64 kbps - excellent for speech
    this.sampleRate = 44100, // Match TTS output sample rate (must be standard rate)
  });

  /// Target bitrate in kbps.
  final int bitrate;

  /// Sample rate in Hz.
  final int sampleRate;

  /// The native audio toolkit instance.
  final _audioToolkit = FlutterAudioToolkit();

  /// Check if a file is already compressed (M4A format).
  bool isCompressed(String path) =>
      path.endsWith('.m4a') || path.endsWith('.aac');

  /// Get the compressed filename for a WAV file.
  String getCompressedPath(String wavPath) {
    if (wavPath.endsWith('.wav')) {
      return wavPath.replaceAll('.wav', '.m4a');
    }
    return '$wavPath.m4a';
  }

  /// Compress a single WAV file to M4A using native codecs.
  ///
  /// Returns the compressed file, or null if compression failed.
  /// The original WAV file is deleted on success.
  Future<File?> compressFile(
    File wavFile, {
    bool deleteOriginal = true,
    void Function(double progress)? onProgress,
  }) async {
    if (!await wavFile.exists()) {
      developer.log(
        'File does not exist: ${wavFile.path}',
        name: 'AacCompressionService',
      );
      return null;
    }

    final m4aPath = getCompressedPath(wavFile.path);
    final m4aFile = File(m4aPath);

    // Delete existing M4A if present (re-compress)
    if (await m4aFile.exists()) {
      await m4aFile.delete();
    }

    developer.log(
      'Compressing: ${wavFile.path}',
      name: 'AacCompressionService',
    );

    try {
      final result = await _audioToolkit.convertAudio(
        inputPath: wavFile.path,
        outputPath: m4aPath,
        format: AudioFormat.m4a,
        bitRate: bitrate,
        sampleRate: sampleRate,
        onProgress: onProgress,
      );

      // Verify the output file exists and has content
      if (await m4aFile.exists()) {
        final m4aStat = await m4aFile.stat();
        if (m4aStat.size > 0) {
          // Success - delete original if requested
          if (deleteOriginal) {
            await wavFile.delete();
          }

          developer.log(
            '✅ Compressed ${wavFile.path} → $m4aPath '
            '(${result.bitRate}bps, ${result.sampleRate}Hz)',
            name: 'AacCompressionService',
          );
          return m4aFile;
        }
      }

      developer.log(
        '❌ Conversion succeeded but output file is missing/empty',
        name: 'AacCompressionService',
      );
      return null;
    } catch (e) {
      developer.log(
        '❌ Conversion failed: $e',
        name: 'AacCompressionService',
      );
      return null;
    }
  }

  /// Compress all WAV files in a directory to M4A.
  ///
  /// Calls [onProgress] after each file with (completed, total).
  /// Returns compression statistics.
  Future<AacCompressionResult> compressDirectory(
    CacheMetadataStorage? storage,
    Directory cacheDir, {
    void Function(int completed, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (!await cacheDir.exists()) {
      return const AacCompressionResult(
        filesCompressed: 0,
        filesFailed: 0,
        originalSizeBytes: 0,
        compressedSizeBytes: 0,
        durationMs: 0,
      );
    }

    // Step 1: Get uncompressed entries from DB (not filesystem scan)
    List<CacheEntryMetadata> wavEntries = [];
    if (storage != null) {
      wavEntries = await storage.getUncompressedEntries();
    } else {
      // Fallback: scan filesystem if storage not available
      final wavFiles = <File>[];
      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path.endsWith('.wav')) {
          wavFiles.add(entity);
        }
      }
      if (wavFiles.isEmpty) {
        return const AacCompressionResult(
          filesCompressed: 0,
          filesFailed: 0,
          originalSizeBytes: 0,
          compressedSizeBytes: 0,
          durationMs: 0,
        );
      }
    }

    int filesCompressed = 0;
    int filesFailed = 0;
    int originalSizeBytes = 0;
    int compressedSizeBytes = 0;

    for (int i = 0; i < wavEntries.length; i++) {
      // Check for cancellation
      if (shouldCancel?.call() ?? false) {
        developer.log(
          'Compression cancelled at $i/${wavEntries.length}',
          name: 'AacCompressionService',
        );
        break;
      }

      final entry = wavEntries[i];
      final wavFile = File('${cacheDir.path}/${entry.key}');
      final wavStat = await wavFile.stat();
      originalSizeBytes += wavStat.size;

      // Step 2: Mark as compressing in DB
      if (storage != null) {
        await storage.updateCompressionState(
          entry.key,
          CompressionState.compressing,
          compressionStartedAt: DateTime.now(),
        );
      }

      // Step 3: Compress file
      final m4aFile = await compressFile(wavFile);
      
      // Step 4: Update DB based on result
      if (m4aFile != null) {
        final m4aStat = await m4aFile.stat();
        compressedSizeBytes += m4aStat.size;
        filesCompressed++;
        
        // Update DB: replace WAV with M4A
        if (storage != null) {
          final m4aKey = entry.key.replaceAll('.wav', '.m4a');
          // Can't easily update key in copyWith, so use replaceEntry
          await storage.replaceEntry(
            oldKey: entry.key,
            newEntry: CacheEntryMetadata(
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
            ),
          );
        }
      } else {
        // Compression failed - keep original size and mark as failed in DB
        compressedSizeBytes += wavStat.size;
        filesFailed++;
        
        if (storage != null) {
          await storage.updateCompressionState(
            entry.key,
            CompressionState.failed,
          );
        }
      }

      onProgress?.call(i + 1, wavEntries.length);
    }

    stopwatch.stop();

    developer.log(
      '📊 Compression complete: $filesCompressed files, '
      '${AacCompressionResult._formatBytes(originalSizeBytes - compressedSizeBytes)} saved',
      name: 'AacCompressionService',
    );

    return AacCompressionResult(
      filesCompressed: filesCompressed,
      filesFailed: filesFailed,
      originalSizeBytes: originalSizeBytes,
      compressedSizeBytes: compressedSizeBytes,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Estimate potential space savings if all WAV files were compressed.
  ///
  /// Uses estimated 17x compression ratio for 64kbps AAC speech.
  Future<int> estimatePotentialSavings(Directory cacheDir) async {
    if (!await cacheDir.exists()) return 0;

    int totalWavSize = 0;
    int wavFileCount = 0;

    await for (final entity in cacheDir.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        totalWavSize += await entity.length();
        wavFileCount++;
      }
    }

    // Estimated compression ratio: ~17x for 64kbps AAC vs 24kHz 16-bit mono WAV
    const estimatedRatio = 17.0;
    final estimatedCompressedSize = totalWavSize ~/ estimatedRatio;

    developer.log(
      'Estimated savings: $wavFileCount WAV files, '
      '${AacCompressionResult._formatBytes(totalWavSize)} total, '
      '~${AacCompressionResult._formatBytes(totalWavSize - estimatedCompressedSize)} savable',
      name: 'AacCompressionService',
    );

    return totalWavSize - estimatedCompressedSize;
  }

  /// Get current compression statistics for the cache.
  Future<({int wavCount, int wavBytes, int m4aCount, int m4aBytes})>
      getCacheStats(Directory cacheDir) async {
    if (!await cacheDir.exists()) {
      return (wavCount: 0, wavBytes: 0, m4aCount: 0, m4aBytes: 0);
    }

    int wavCount = 0;
    int wavBytes = 0;
    int m4aCount = 0;
    int m4aBytes = 0;

    await for (final entity in cacheDir.list()) {
      if (entity is File) {
        final size = await entity.length();
        if (entity.path.endsWith('.wav')) {
          wavCount++;
          wavBytes += size;
        } else if (entity.path.endsWith('.m4a')) {
          m4aCount++;
          m4aBytes += size;
        }
      }
    }

    return (
      wavCount: wavCount,
      wavBytes: wavBytes,
      m4aCount: m4aCount,
      m4aBytes: m4aBytes,
    );
  }
}

/// Comprehensive cache compression statistics.
class CacheCompressionStats {
  const CacheCompressionStats({
    required this.uncompressedFiles,
    required this.uncompressedBytes,
    required this.compressedFiles,
    required this.compressedBytes,
    required this.estimatedSavings,
  });

  /// Number of uncompressed (WAV) files.
  final int uncompressedFiles;

  /// Total size of uncompressed files in bytes.
  final int uncompressedBytes;

  /// Number of compressed (M4A) files.
  final int compressedFiles;

  /// Total size of compressed files in bytes.
  final int compressedBytes;

  /// Estimated bytes that could be saved by compressing remaining WAV files.
  final int estimatedSavings;

  /// Total number of audio files.
  int get totalFiles => uncompressedFiles + compressedFiles;

  /// Total cache size in bytes.
  int get totalBytes => uncompressedBytes + compressedBytes;

  /// Whether there are files that can be compressed.
  bool get canCompress => uncompressedFiles > 0;

  /// Percentage of files that are compressed.
  double get compressionPercent =>
      totalFiles > 0 ? (compressedFiles / totalFiles * 100) : 0.0;

  /// Format estimated savings as human-readable string.
  String get formattedEstimatedSavings =>
      AacCompressionResult._formatBytes(estimatedSavings);

  /// Format total cache size as human-readable string.
  String get formattedTotalSize => AacCompressionResult._formatBytes(totalBytes);

  /// Format uncompressed size as human-readable string.
  String get formattedUncompressedSize =>
      AacCompressionResult._formatBytes(uncompressedBytes);

  /// Format compressed size as human-readable string.
  String get formattedCompressedSize =>
      AacCompressionResult._formatBytes(compressedBytes);

  /// Create stats from a cache directory.
  static Future<CacheCompressionStats> fromDirectory(
    Directory cacheDir,
    AacCompressionService service,
  ) async {
    final stats = await service.getCacheStats(cacheDir);
    final estimatedSavings = await service.estimatePotentialSavings(cacheDir);

    return CacheCompressionStats(
      uncompressedFiles: stats.wavCount,
      uncompressedBytes: stats.wavBytes,
      compressedFiles: stats.m4aCount,
      compressedBytes: stats.m4aBytes,
      estimatedSavings: estimatedSavings,
    );
  }

  @override
  String toString() {
    return 'CacheCompressionStats('
        'uncompressed: $uncompressedFiles files ($formattedUncompressedSize), '
        'compressed: $compressedFiles files ($formattedCompressedSize), '
        'potential savings: $formattedEstimatedSavings)';
  }
}
