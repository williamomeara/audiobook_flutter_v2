import 'dart:io';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

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
/// Uses opus_dart/opus_flutter for native Opus encoding/decoding.
class CacheCompressor {
  CacheCompressor({
    required this.config,
    required this.cacheDir,
  });

  final CacheCompressionConfig config;
  final Directory cacheDir;
  
  /// Whether the Opus library has been initialized.
  bool _opusInitialized = false;
  
  /// Sample rate for WAV audio (our TTS engines use 22050 Hz).
  static const _sampleRate = 22050;
  
  /// Number of channels (mono audio).
  static const _channels = 1;
  
  /// Frame size in samples (20ms at 22050 Hz = 441 samples).
  static const _frameSizeSamples = 441;

  /// Initialize the Opus library if not already done.
  Future<void> _ensureOpusInitialized() async {
    if (_opusInitialized) return;
    
    try {
      // Load the native Opus library using opus_flutter
      final opusLib = await opus_flutter.load();
      // Initialize opus_dart with the library
      initOpus(opusLib);
      _opusInitialized = true;
      developer.log(
        '✅ Opus library initialized',
        name: 'CacheCompressor',
      );
    } catch (e) {
      developer.log(
        '❌ Failed to initialize Opus: $e',
        name: 'CacheCompressor',
      );
      rethrow;
    }
  }

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

  /// Read PCM audio data from a WAV file.
  /// Returns the audio samples as 16-bit signed integers.
  Future<Int16List> _readWavAsPcm(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    
    // WAV header is 44 bytes for standard PCM format
    // Skip header and read audio data
    if (bytes.length < 44) {
      throw Exception('Invalid WAV file: too short');
    }
    
    // Verify it's a WAV file
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw Exception('Invalid WAV file: not RIFF/WAVE format');
    }
    
    // Find data chunk (skip header)
    // Standard WAV: data starts at byte 44
    final audioData = bytes.sublist(44);
    
    // Convert bytes to Int16 samples
    final samples = Int16List(audioData.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = audioData[i * 2] | (audioData[i * 2 + 1] << 8);
    }
    
    return samples;
  }

  /// Write PCM audio data to a WAV file.
  Future<void> _writePcmAsWav(Int16List samples, File wavFile) async {
    final numSamples = samples.length;
    final byteRate = _sampleRate * _channels * 2;
    final blockAlign = _channels * 2;
    final dataSize = numSamples * 2;
    final fileSize = 36 + dataSize;
    
    final buffer = BytesBuilder();
    
    // RIFF header
    buffer.add('RIFF'.codeUnits);
    buffer.add(_int32ToBytes(fileSize));
    buffer.add('WAVE'.codeUnits);
    
    // fmt subchunk
    buffer.add('fmt '.codeUnits);
    buffer.add(_int32ToBytes(16)); // Subchunk1Size for PCM
    buffer.add(_int16ToBytes(1)); // AudioFormat: PCM = 1
    buffer.add(_int16ToBytes(_channels)); // NumChannels
    buffer.add(_int32ToBytes(_sampleRate)); // SampleRate
    buffer.add(_int32ToBytes(byteRate)); // ByteRate
    buffer.add(_int16ToBytes(blockAlign)); // BlockAlign
    buffer.add(_int16ToBytes(16)); // BitsPerSample
    
    // data subchunk
    buffer.add('data'.codeUnits);
    buffer.add(_int32ToBytes(dataSize));
    
    // Audio data
    for (final sample in samples) {
      buffer.add(_int16ToBytes(sample));
    }
    
    await wavFile.writeAsBytes(buffer.toBytes());
  }

  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = (value >> 16) & 0xFF
      ..[3] = (value >> 24) & 0xFF;
  }

  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF;
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
    final compressedFile = File(compressedPath);

    try {
      await _ensureOpusInitialized();
      
      // Read PCM audio from WAV
      final pcmSamples = await _readWavAsPcm(wavFile);
      
      // Create Opus encoder
      final encoder = SimpleOpusEncoder(
        sampleRate: _sampleRate,
        channels: _channels,
        application: Application.audio,
      );
      
      // Encode to Opus
      final opusPackets = <Uint8List>[];
      var offset = 0;
      
      while (offset < pcmSamples.length) {
        // Get frame of samples
        final frameEnd = (offset + _frameSizeSamples).clamp(0, pcmSamples.length);
        final frameSamples = pcmSamples.sublist(offset, frameEnd);
        
        // Pad if needed
        final paddedFrame = Int16List(_frameSizeSamples);
        paddedFrame.setRange(0, frameSamples.length, frameSamples);
        
        // Encode frame
        final encoded = encoder.encode(input: paddedFrame);
        if (encoded.isNotEmpty) {
          opusPackets.add(encoded);
        }
        
        offset = frameEnd;
      }
      
      encoder.destroy();
      
      // Write Opus file with custom header
      // Format: [magic:4][sampleRate:4][numPackets:4][packetSizes:4*N][packets]
      final buffer = BytesBuilder();
      buffer.add('OPUS'.codeUnits); // Magic number
      buffer.add(_int32ToBytes(_sampleRate));
      buffer.add(_int32ToBytes(opusPackets.length));
      
      for (final packet in opusPackets) {
        buffer.add(_int32ToBytes(packet.length));
      }
      for (final packet in opusPackets) {
        buffer.add(packet);
      }
      
      await compressedFile.writeAsBytes(buffer.toBytes());
      
      developer.log(
        '🗜️ Compressed ${wavFile.path} to $compressedPath',
        name: 'CacheCompressor',
      );
      
      return compressedFile;
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
    final wavFile = File(wavPath);

    try {
      await _ensureOpusInitialized();
      
      // Read our custom Opus file format
      final bytes = await opusFile.readAsBytes();
      
      // Parse header
      if (bytes.length < 12) {
        throw Exception('Invalid Opus file: too short');
      }
      
      final magic = String.fromCharCodes(bytes.sublist(0, 4));
      if (magic != 'OPUS') {
        throw Exception('Invalid Opus file: bad magic number');
      }
      
      final sampleRate = _bytesToInt32(bytes, 4);
      final numPackets = _bytesToInt32(bytes, 8);
      
      // Read packet sizes
      final packetSizes = <int>[];
      var offset = 12;
      for (var i = 0; i < numPackets; i++) {
        packetSizes.add(_bytesToInt32(bytes, offset));
        offset += 4;
      }
      
      // Read packets
      final packets = <Uint8List>[];
      for (final size in packetSizes) {
        packets.add(Uint8List.fromList(bytes.sublist(offset, offset + size)));
        offset += size;
      }
      
      // Create Opus decoder
      final decoder = SimpleOpusDecoder(
        sampleRate: sampleRate,
        channels: _channels,
      );
      
      // Decode all packets
      final decodedSamples = <int>[];
      for (final packet in packets) {
        final decoded = decoder.decode(input: packet);
        decodedSamples.addAll(decoded);
      }
      
      decoder.destroy();
      
      // Write WAV file
      await _writePcmAsWav(Int16List.fromList(decodedSamples), wavFile);
      
      developer.log(
        '📦 Decompressed ${opusFile.path} to $wavPath',
        name: 'CacheCompressor',
      );
      
      return wavFile;
    } catch (e) {
      developer.log(
        '❌ Decompression failed for ${opusFile.path}: $e',
        name: 'CacheCompressor',
      );
      return null;
    }
  }

  int _bytesToInt32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
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
            '🗜️ Compressed $filename: ${stat.size} → ${compressedStat.size} bytes',
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
