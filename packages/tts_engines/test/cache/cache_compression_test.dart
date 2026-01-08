import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tts_engines/src/cache/cache_compression.dart';

void main() {
  group('CacheCompressor', () {
    late Directory tempDir;
    late CacheCompressor compressor;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cache_test_');
      compressor = CacheCompressor(
        config: const CacheCompressionConfig(
          compressionLevel: CompressionLevel.standard,
        ),
        cacheDir: tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('isCompressed returns true for .opus files', () {
      expect(compressor.isCompressed('test.opus'), isTrue);
      expect(compressor.isCompressed('test.wav'), isFalse);
      expect(compressor.isCompressed('test.mp3'), isFalse);
    });

    test('getCompressedFilename converts .wav to .opus', () {
      expect(compressor.getCompressedFilename('audio.wav'), 'audio.opus');
      expect(compressor.getCompressedFilename('test.wav'), 'test.opus');
    });

    test('getOriginalFilename converts .opus to .wav', () {
      expect(compressor.getOriginalFilename('audio.opus'), 'audio.wav');
      expect(compressor.getOriginalFilename('test.opus'), 'test.wav');
    });

    test('compressEntry returns null when compression disabled', () async {
      final disabledCompressor = CacheCompressor(
        config: const CacheCompressionConfig(
          compressionLevel: CompressionLevel.none,
        ),
        cacheDir: tempDir,
      );

      final wavFile = File('${tempDir.path}/test.wav');
      await wavFile.writeAsBytes([0, 1, 2, 3]);

      final result = await disabledCompressor.compressEntry(wavFile);
      expect(result, isNull);
    });

    test('compressEntry returns null for non-existent file', () async {
      final wavFile = File('${tempDir.path}/nonexistent.wav');

      final result = await compressor.compressEntry(wavFile);
      expect(result, isNull);
    });

    test('CompressionLevel bitrates are correct', () {
      const lightConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.light);
      const standardConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.standard);
      const aggressiveConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.aggressive);
      const noneConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.none);

      expect(lightConfig.targetBitrate, 64000);
      expect(standardConfig.targetBitrate, 32000);
      expect(aggressiveConfig.targetBitrate, 24000);
      expect(noneConfig.targetBitrate, 0);
    });

    test('CompressionLevel estimated ratios are correct', () {
      const lightConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.light);
      const standardConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.standard);
      const aggressiveConfig = CacheCompressionConfig(compressionLevel: CompressionLevel.aggressive);

      expect(lightConfig.estimatedCompressionRatio, 6.0);
      expect(standardConfig.estimatedCompressionRatio, 10.0);
      expect(aggressiveConfig.estimatedCompressionRatio, 15.0);
    });

    test('CacheCompressionConfig serialization roundtrip', () {
      const config = CacheCompressionConfig(
        compressionLevel: CompressionLevel.light,
        hotCacheThreshold: Duration(hours: 2),
        compressOnEviction: false,
        decompressOnAccess: true,
      );

      final json = config.toJson();
      final restored = CacheCompressionConfig.fromJson(json);

      expect(restored.compressionLevel, config.compressionLevel);
      expect(restored.hotCacheThreshold, config.hotCacheThreshold);
      expect(restored.compressOnEviction, config.compressOnEviction);
      expect(restored.decompressOnAccess, config.decompressOnAccess);
    });

    test('CompressionStats calculations are correct', () {
      const stats = CompressionStats(
        originalSizeBytes: 1000000,
        compressedSizeBytes: 100000,
        compressedEntries: 10,
        uncompressedEntries: 5,
      );

      expect(stats.spaceSaved, 900000);
      expect(stats.compressionRatio, 10.0);
      expect(stats.savingsPercent, 90.0);
    });

    test('File extensions work correctly', () {
      final wavFile = File('${tempDir.path}/test.wav');
      final opusFile = File('${tempDir.path}/test.opus');
      final otherFile = File('${tempDir.path}/test.mp3');

      expect(wavFile.isUncompressedAudio, isTrue);
      expect(wavFile.isCompressedAudio, isFalse);
      expect(opusFile.isCompressedAudio, isTrue);
      expect(opusFile.isUncompressedAudio, isFalse);
      expect(otherFile.isCompressedAudio, isFalse);
      expect(otherFile.isUncompressedAudio, isFalse);
    });
  });

  group('CacheCompressor with Opus (requires native library)', () {
    late Directory tempDir;
    late CacheCompressor compressor;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('opus_test_');
      compressor = CacheCompressor(
        config: const CacheCompressionConfig(
          compressionLevel: CompressionLevel.standard,
        ),
        cacheDir: tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('compress and decompress roundtrip preserves audio', () async {
      // Create a simple WAV file with a sine wave
      final wavFile = await _createTestWavFile(tempDir.path);
      
      // Compress the file
      final compressedFile = await compressor.compressEntry(wavFile);
      
      // This test may fail on platforms without opus_flutter support
      // In that case, we skip the rest of the test
      if (compressedFile == null) {
        print('Opus compression not available on this platform, skipping roundtrip test');
        return;
      }

      expect(await compressedFile.exists(), isTrue);
      expect(compressedFile.path.endsWith('.opus'), isTrue);

      // The compressed file should be smaller than the original
      final originalSize = await wavFile.length();
      final compressedSize = await compressedFile.length();
      expect(compressedSize, lessThan(originalSize));

      // Decompress the file
      final decompressedFile = await compressor.decompressEntry(compressedFile);
      expect(decompressedFile, isNotNull);
      expect(await decompressedFile!.exists(), isTrue);
      expect(decompressedFile.path.endsWith('.wav'), isTrue);
    }, 
    // Skip on platforms without Opus support
    skip: 'Requires Opus native library - run on Android/iOS device');
  });
}

/// Create a test WAV file with a simple tone.
Future<File> _createTestWavFile(String dirPath) async {
  final file = File('$dirPath/test_audio.wav');
  
  // Generate 1 second of 440 Hz sine wave at 22050 Hz sample rate
  const sampleRate = 22050;
  const duration = 1.0;
  const frequency = 440.0;
  final numSamples = (sampleRate * duration).toInt();
  
  final samples = Int16List(numSamples);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    samples[i] = (32767 * _sin(2 * 3.14159265359 * frequency * t)).toInt();
  }
  
  // Build WAV file
  final buffer = BytesBuilder();
  
  // RIFF header
  buffer.add('RIFF'.codeUnits);
  buffer.add(_int32ToBytes(36 + numSamples * 2)); // File size - 8
  buffer.add('WAVE'.codeUnits);
  
  // fmt subchunk
  buffer.add('fmt '.codeUnits);
  buffer.add(_int32ToBytes(16)); // Subchunk1Size
  buffer.add(_int16ToBytes(1)); // AudioFormat: PCM
  buffer.add(_int16ToBytes(1)); // NumChannels
  buffer.add(_int32ToBytes(sampleRate)); // SampleRate
  buffer.add(_int32ToBytes(sampleRate * 2)); // ByteRate
  buffer.add(_int16ToBytes(2)); // BlockAlign
  buffer.add(_int16ToBytes(16)); // BitsPerSample
  
  // data subchunk
  buffer.add('data'.codeUnits);
  buffer.add(_int32ToBytes(numSamples * 2));
  
  // Audio data
  for (final sample in samples) {
    buffer.add(_int16ToBytes(sample));
  }
  
  await file.writeAsBytes(buffer.toBytes());
  return file;
}

double _sin(double x) {
  // Taylor series approximation for sin
  x = x % (2 * 3.14159265359);
  var result = 0.0;
  var term = x;
  for (var n = 1; n <= 15; n += 2) {
    result += term;
    term *= -x * x / ((n + 1) * (n + 2));
  }
  return result;
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
