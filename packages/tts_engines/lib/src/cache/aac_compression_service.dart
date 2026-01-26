import 'dart:io';
import 'dart:developer' as developer;

import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';

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
/// Uses FFmpeg via ffmpeg_kit_flutter_audio for cross-platform compression.
/// AAC in M4A container is chosen for native playback support on iOS and Android
/// via just_audio - no decompression needed at playback time.
class AacCompressionService {
  AacCompressionService({
    this.bitrate = 64000, // 64 kbps - excellent for speech
  });

  /// Target bitrate in bits per second.
  final int bitrate;

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

  /// Compress a single WAV file to M4A.
  ///
  /// Returns the compressed file, or null if compression failed.
  /// The original WAV file is deleted on success.
  Future<File?> compressFile(
    File wavFile, {
    bool deleteOriginal = true,
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

    // Build FFmpeg command: -i input.wav -c:a aac -b:a 64k output.m4a
    final bitrateKbps = bitrate ~/ 1000;
    final command = '-i "${wavFile.path}" -c:a aac -b:a ${bitrateKbps}k "$m4aPath"';

    developer.log(
      'Compressing: ${wavFile.path}',
      name: 'AacCompressionService',
    );

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // Verify the output file exists and has content
        if (await m4aFile.exists()) {
          final m4aStat = await m4aFile.stat();
          if (m4aStat.size > 0) {
            // Success - delete original if requested
            if (deleteOriginal) {
              await wavFile.delete();
            }

            developer.log(
              '✅ Compressed ${wavFile.path} → $m4aPath',
              name: 'AacCompressionService',
            );
            return m4aFile;
          }
        }

        developer.log(
          '❌ FFmpeg succeeded but output file is missing/empty',
          name: 'AacCompressionService',
        );
        return null;
      } else {
        final logs = await session.getAllLogs();
        final output = logs.map((l) => l.getMessage()).join('\n');
        developer.log(
          '❌ FFmpeg failed: $output',
          name: 'AacCompressionService',
        );
        return null;
      }
    } catch (e) {
      developer.log(
        '❌ FFmpeg exception: $e',
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

    // Find all WAV files
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

    int filesCompressed = 0;
    int filesFailed = 0;
    int originalSizeBytes = 0;
    int compressedSizeBytes = 0;

    for (int i = 0; i < wavFiles.length; i++) {
      // Check for cancellation
      if (shouldCancel?.call() ?? false) {
        developer.log(
          'Compression cancelled at $i/${wavFiles.length}',
          name: 'AacCompressionService',
        );
        break;
      }

      final wavFile = wavFiles[i];
      final wavStat = await wavFile.stat();
      originalSizeBytes += wavStat.size;

      final m4aFile = await compressFile(wavFile);
      if (m4aFile != null) {
        final m4aStat = await m4aFile.stat();
        compressedSizeBytes += m4aStat.size;
        filesCompressed++;
      } else {
        // Keep original size in total if compression failed
        compressedSizeBytes += wavStat.size;
        filesFailed++;
      }

      onProgress?.call(i + 1, wavFiles.length);
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
