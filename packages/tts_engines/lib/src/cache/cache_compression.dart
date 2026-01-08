import 'dart:io';
import 'dart:developer' as developer;

/// Audio compression strategy for long-term cache storage.
///
/// Compresses WAV files to Opus format for storage efficiency.
/// Opus provides ~10x compression ratio for speech audio while
/// maintaining excellent quality.
enum CompressionLevel {
  /// No compression - keep original WAV files.
  none,

  /// Light compression - high quality Opus (64 kbps).
  /// ~6x compression ratio.
  light,

  /// Standard compression - good quality Opus (32 kbps).
  /// ~10x compression ratio.
  standard,

  /// Aggressive compression - acceptable quality Opus (24 kbps).
  /// ~15x compression ratio.
  aggressive,
}

/// Configuration for cache compression.
class CacheCompressionConfig {
  const CacheCompressionConfig({
    this.compressionLevel = CompressionLevel.standard,
    this.hotCacheThreshold = const Duration(hours: 1),
    this.compressOnEviction = true,
    this.decompressOnAccess = true,
  });

  /// Compression level to use.
  final CompressionLevel compressionLevel;

  /// Entries older than this are candidates for compression.
  /// Recently accessed entries stay uncompressed for fast access.
  final Duration hotCacheThreshold;

  /// Compress entries before evicting to save more space.
  final bool compressOnEviction;

  /// Automatically decompress when accessing compressed entries.
  final bool decompressOnAccess;

  /// Get target bitrate for compression level.
  int get targetBitrate {
    switch (compressionLevel) {
      case CompressionLevel.none:
        return 0;
      case CompressionLevel.light:
        return 64000; // 64 kbps
      case CompressionLevel.standard:
        return 32000; // 32 kbps
      case CompressionLevel.aggressive:
        return 24000; // 24 kbps
    }
  }

  /// Estimated compression ratio.
  double get estimatedCompressionRatio {
    switch (compressionLevel) {
      case CompressionLevel.none:
        return 1.0;
      case CompressionLevel.light:
        return 6.0;
      case CompressionLevel.standard:
        return 10.0;
      case CompressionLevel.aggressive:
        return 15.0;
    }
  }

  Map<String, dynamic> toJson() => {
        'compressionLevel': compressionLevel.index,
        'hotCacheThresholdMs': hotCacheThreshold.inMilliseconds,
        'compressOnEviction': compressOnEviction,
        'decompressOnAccess': decompressOnAccess,
      };

  factory CacheCompressionConfig.fromJson(Map<String, dynamic> json) {
    return CacheCompressionConfig(
      compressionLevel: CompressionLevel.values[json['compressionLevel'] as int? ?? 2],
      hotCacheThreshold: Duration(
        milliseconds: json['hotCacheThresholdMs'] as int? ?? 3600000,
      ),
      compressOnEviction: json['compressOnEviction'] as bool? ?? true,
      decompressOnAccess: json['decompressOnAccess'] as bool? ?? true,
    );
  }
}

/// Statistics about compression savings.
class CompressionStats {
  const CompressionStats({
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.compressedEntries,
    required this.uncompressedEntries,
  });

  final int originalSizeBytes;
  final int compressedSizeBytes;
  final int compressedEntries;
  final int uncompressedEntries;

  /// Space saved in bytes.
  int get spaceSaved => originalSizeBytes - compressedSizeBytes;

  /// Compression ratio achieved.
  double get compressionRatio =>
      compressedSizeBytes > 0 ? originalSizeBytes / compressedSizeBytes : 1.0;

  /// Percentage of space saved.
  double get savingsPercent =>
      originalSizeBytes > 0 ? (spaceSaved / originalSizeBytes * 100) : 0.0;

  String get formattedSavings => _formatBytes(spaceSaved);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Manages compression of cached audio files.
///
/// This class provides functionality to:
/// 1. Compress old cache entries to save space
/// 2. Decompress entries when accessed
/// 3. Track compression statistics
///
/// Note: Actual compression uses FFI to native audio codecs (Opus/LAME).
/// This implementation provides the interface and logic; native bindings
/// are in platform-specific packages.
class CacheCompressor {
  CacheCompressor({
    required this.config,
    required this.cacheDir,
  });

  final CacheCompressionConfig config;
  final Directory cacheDir;

  /// Check if a file is compressed (has .opus extension).
  bool isCompressed(String filename) => filename.endsWith('.opus');

  /// Get the compressed filename for a WAV file.
  String getCompressedFilename(String wavFilename) {
    if (wavFilename.endsWith('.wav')) {
      return wavFilename.replaceAll('.wav', '.opus');
    }
    return '$wavFilename.opus';
  }

  /// Get the original WAV filename from compressed file.
  String getOriginalFilename(String compressedFilename) {
    if (compressedFilename.endsWith('.opus')) {
      return compressedFilename.replaceAll('.opus', '.wav');
    }
    return compressedFilename;
  }

  /// Compress a cache entry to save space.
  ///
  /// Returns the compressed file, or null if compression failed.
  Future<File?> compressEntry(File wavFile) async {
    if (config.compressionLevel == CompressionLevel.none) {
      return null;
    }

    if (!await wavFile.exists()) {
      return null;
    }

    final compressedPath = getCompressedFilename(wavFile.path);
    // File will be created by native encoder once integrated
    // final compressedFile = File(compressedPath);

    try {
      // For now, we use a simple copy as a placeholder.
      // Real implementation would use FFI to native Opus encoder.
      // The compression would look like:
      //   await _opusEncoder.encode(wavFile, compressedFile, bitrate: config.targetBitrate);
      
      // Placeholder: Copy file as-is (real impl compresses)
      // TODO: Integrate with native Opus encoder
      developer.log(
        '🗜️ Would compress ${wavFile.path} to $compressedPath at ${config.targetBitrate} bps',
        name: 'CacheCompressor',
      );
      
      // For now, return null to indicate "not yet implemented"
      // Once native bindings are ready, this will actually compress
      return null;
    } catch (e) {
      developer.log(
        '❌ Compression failed for ${wavFile.path}: $e',
        name: 'CacheCompressor',
      );
      return null;
    }
  }

  /// Decompress a cache entry for playback.
  ///
  /// Returns the decompressed WAV file, or null if decompression failed.
  Future<File?> decompressEntry(File opusFile) async {
    if (!await opusFile.exists()) {
      return null;
    }

    final wavPath = getOriginalFilename(opusFile.path);
    // File will be created by native decoder once integrated
    // final wavFile = File(wavPath);

    try {
      // Placeholder: Real implementation uses FFI to Opus decoder
      // The decompression would look like:
      //   await _opusDecoder.decode(opusFile, wavFile);
      
      developer.log(
        '📦 Would decompress ${opusFile.path} to $wavPath',
        name: 'CacheCompressor',
      );
      
      return null;
    } catch (e) {
      developer.log(
        '❌ Decompression failed for ${opusFile.path}: $e',
        name: 'CacheCompressor',
      );
      return null;
    }
  }

  /// Compress all eligible entries in the cache.
  ///
  /// Entries are eligible if:
  /// - They are older than [config.hotCacheThreshold]
  /// - They are not already compressed
  /// - Compression is enabled
  Future<CompressionStats> compressOldEntries({
    required Map<String, DateTime> lastAccessTimes,
  }) async {
    if (config.compressionLevel == CompressionLevel.none) {
      return const CompressionStats(
        originalSizeBytes: 0,
        compressedSizeBytes: 0,
        compressedEntries: 0,
        uncompressedEntries: 0,
      );
    }

    if (!await cacheDir.exists()) {
      return const CompressionStats(
        originalSizeBytes: 0,
        compressedSizeBytes: 0,
        compressedEntries: 0,
        uncompressedEntries: 0,
      );
    }

    var originalSize = 0;
    var compressedSize = 0;
    var compressedCount = 0;
    var uncompressedCount = 0;
    final now = DateTime.now();

    await for (final entity in cacheDir.list()) {
      if (entity is! File) continue;
      final filename = entity.uri.pathSegments.last;

      // Skip already compressed files
      if (isCompressed(filename)) {
        final stat = await entity.stat();
        compressedSize += stat.size;
        compressedCount++;
        continue;
      }

      // Skip WAV files (they're the original format)
      if (!filename.endsWith('.wav')) continue;

      final stat = await entity.stat();
      final lastAccess = lastAccessTimes[filename] ?? stat.modified;
      final age = now.difference(lastAccess);

      // Check if eligible for compression
      if (age > config.hotCacheThreshold) {
        final compressed = await compressEntry(entity);
        if (compressed != null) {
          final compressedStat = await compressed.stat();
          compressedSize += compressedStat.size;
          compressedCount++;
          
          // Delete original after successful compression
          await entity.delete();
          
          developer.log(
            '🗜️ Compressed ${filename}: ${stat.size} → ${compressedStat.size} bytes',
            name: 'CacheCompressor',
          );
        } else {
          // Keep original if compression failed
          originalSize += stat.size;
          uncompressedCount++;
        }
      } else {
        // Keep hot entries uncompressed
        originalSize += stat.size;
        uncompressedCount++;
      }
    }

    return CompressionStats(
      originalSizeBytes: originalSize + (compressedSize * config.estimatedCompressionRatio).round(),
      compressedSizeBytes: originalSize + compressedSize,
      compressedEntries: compressedCount,
      uncompressedEntries: uncompressedCount,
    );
  }

  /// Estimate potential space savings if all entries were compressed.
  Future<int> estimatePotentialSavings() async {
    if (!await cacheDir.exists()) return 0;

    var totalWavSize = 0;
    await for (final entity in cacheDir.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        totalWavSize += await entity.length();
      }
    }

    final ratio = config.estimatedCompressionRatio;
    return totalWavSize - (totalWavSize / ratio).round();
  }
}

/// Extension methods for compression-aware file operations.
extension CompressionAwareFile on File {
  /// Check if this file is a compressed audio file.
  bool get isCompressedAudio => path.endsWith('.opus');

  /// Check if this file is an uncompressed audio file.
  bool get isUncompressedAudio => path.endsWith('.wav');

  /// Get the compressed version path of this file.
  String get compressedPath =>
      isUncompressedAudio ? path.replaceAll('.wav', '.opus') : '$path.opus';

  /// Get the uncompressed version path of this file.
  String get uncompressedPath =>
      isCompressedAudio ? path.replaceAll('.opus', '.wav') : path;
}
