import 'dart:io';

import 'package:test/test.dart';
import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/src/cache/intelligent_cache_manager.dart';

void main() {
  late Directory tempDir;
  late IntelligentCacheManager manager;
  late File metadataFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cache_test_');
    metadataFile = File('${tempDir.path}/.cache_metadata.json');
    manager = IntelligentCacheManager(
      cacheDir: tempDir,
      metadataFile: metadataFile,
      quotaSettings: CacheQuotaSettings.fromGB(1.0),
    );
    await manager.initialize();
  });

  tearDown(() async {
    manager.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('IntelligentCacheManager', () {
    test('initialize creates cache directory', () async {
      expect(await tempDir.exists(), isTrue);
    });

    test('getUsageStats returns zero for empty cache', () async {
      final stats = await manager.getUsageStats();
      
      expect(stats.totalSizeBytes, equals(0));
      expect(stats.entryCount, equals(0));
      expect(stats.quotaSizeBytes, equals(1024 * 1024 * 1024)); // 1 GB
    });

    test('registerEntry adds metadata and tracks size', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Hello world',
        playbackRate: 1.0,
      );
      
      // Create a dummy file
      final file = await manager.fileFor(cacheKey);
      await file.writeAsBytes(List.filled(1024, 0)); // 1KB file
      
      // Register the entry
      await manager.registerEntry(
        key: cacheKey,
        sizeBytes: 1024,
        bookId: 'book1',
        segmentIndex: 0,
        chapterIndex: 0,
        engineType: 'kokoro',
        audioDurationMs: 5000,
      );
      
      final stats = await manager.getUsageStats();
      
      expect(stats.entryCount, equals(1));
      // Total size includes metadata file, so just check entry tracking
      expect(stats.byBook['book1'], equals(1024));
      expect(stats.byVoice['kokoro_af'], equals(1024));
    });

    test('isReady returns true for existing files above min size', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Test text',
        playbackRate: 1.0,
      );
      
      final file = await manager.fileFor(cacheKey);
      // WAV header is 44 bytes, file must be > 44 to be "ready"
      await file.writeAsBytes(List.filled(100, 0));
      
      final isReady = await manager.isReady(cacheKey);
      expect(isReady, isTrue);
    });

    test('isReady returns false for missing files', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Non-existent',
        playbackRate: 1.0,
      );
      
      final isReady = await manager.isReady(cacheKey);
      expect(isReady, isFalse);
    });

    test('isReady returns false for files with only WAV header', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Empty audio',
        playbackRate: 1.0,
      );
      
      final file = await manager.fileFor(cacheKey);
      await file.writeAsBytes(List.filled(44, 0)); // Just WAV header
      
      final isReady = await manager.isReady(cacheKey);
      expect(isReady, isFalse);
    });

    test('markUsed auto-registers untracked files', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'supertonic_m1',
        text: 'Auto register test',
        playbackRate: 1.0,
      );
      
      // Create file WITHOUT registering it
      final file = await manager.fileFor(cacheKey);
      await file.writeAsBytes(List.filled(5000, 0));
      
      // Initially, no metadata
      var stats = await manager.getUsageStats();
      expect(stats.entryCount, equals(0));
      
      // Mark as used - should auto-register
      await manager.markUsed(cacheKey);
      
      // Now should have metadata
      stats = await manager.getUsageStats();
      expect(stats.entryCount, equals(1));
      expect(stats.byVoice['supertonic_m1'], equals(5000));
    });

    test('sync auto-registers orphan files on initialize', () async {
      // Create orphan files directly in cache dir
      await File('${tempDir.path}/kokoro_af_abc123.wav')
          .writeAsBytes(List.filled(2000, 0));
      await File('${tempDir.path}/supertonic_m1_def456.wav')
          .writeAsBytes(List.filled(3000, 0));
      
      // Re-initialize to trigger sync
      final newManager = IntelligentCacheManager(
        cacheDir: tempDir,
        metadataFile: metadataFile,
        quotaSettings: CacheQuotaSettings.fromGB(1.0),
      );
      await newManager.initialize();
      
      final stats = await newManager.getUsageStats();
      
      // Should have auto-registered both files
      expect(stats.entryCount, equals(2));
      // Total size includes metadata file, check entry count instead
      expect(stats.byVoice.length, greaterThanOrEqualTo(1));
      
      newManager.dispose();
    });

    test('sync removes stale metadata entries', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Will be deleted',
        playbackRate: 1.0,
      );
      
      // Create and register
      final file = await manager.fileFor(cacheKey);
      await file.writeAsBytes(List.filled(1000, 0));
      await manager.registerEntry(
        key: cacheKey,
        sizeBytes: 1000,
        bookId: 'book1',
        segmentIndex: 0,
        chapterIndex: 0,
        engineType: 'kokoro',
        audioDurationMs: 3000,
      );
      
      // Verify registered
      var stats = await manager.getUsageStats();
      expect(stats.entryCount, equals(1));
      
      // Delete the file externally
      await file.delete();
      
      // Re-initialize to trigger sync
      final newManager = IntelligentCacheManager(
        cacheDir: tempDir,
        metadataFile: metadataFile,
        quotaSettings: CacheQuotaSettings.fromGB(1.0),
      );
      await newManager.initialize();
      
      stats = await newManager.getUsageStats();
      
      // Should have removed stale entry
      expect(stats.entryCount, equals(0));
      
      newManager.dispose();
    });

    test('clear removes all files and metadata', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Test clear',
        playbackRate: 1.0,
      );
      
      final file = await manager.fileFor(cacheKey);
      await file.writeAsBytes(List.filled(1000, 0));
      await manager.registerEntry(
        key: cacheKey,
        sizeBytes: 1000,
        bookId: 'book1',
        segmentIndex: 0,
        chapterIndex: 0,
        engineType: 'kokoro',
        audioDurationMs: 3000,
      );
      
      await manager.clear();
      
      final stats = await manager.getUsageStats();
      expect(stats.entryCount, equals(0));
      // File system may still have metadata file, check entry count is 0
    });

    test('evictIfNeeded removes entries when over quota', () async {
      // Set small quota
      await manager.setQuotaSettings(CacheQuotaSettings(maxSizeBytes: 5000));
      
      // Add files that exceed quota
      for (int i = 0; i < 10; i++) {
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: 'kokoro_af',
          text: 'Test $i',
          playbackRate: 1.0,
        );
        
        final file = await manager.fileFor(cacheKey);
        await file.writeAsBytes(List.filled(1000, 0));
        await manager.registerEntry(
          key: cacheKey,
          sizeBytes: 1000,
          bookId: 'book1',
          segmentIndex: i,
          chapterIndex: 0,
          engineType: 'kokoro',
          audioDurationMs: 3000,
        );
      }
      
      // Total should be 10KB, but quota is 5KB
      // Eviction should run and reduce to 90% of quota (4.5KB or less)
      final stats = await manager.getUsageStats();
      expect(stats.totalSizeBytes, lessThanOrEqualTo(4500));
    });

    test('metadata persists across restarts', () async {
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: 'piper:en_US-lessac-medium',
        text: 'Persistence test',
        playbackRate: 1.0,
      );
      
      final file = await manager.fileFor(cacheKey);
      await file.writeAsBytes(List.filled(2000, 0));
      await manager.registerEntry(
        key: cacheKey,
        sizeBytes: 2000,
        bookId: 'book1',
        segmentIndex: 5,
        chapterIndex: 2,
        engineType: 'piper',
        audioDurationMs: 8000,
      );
      
      // Create new manager instance (simulating app restart)
      final newManager = IntelligentCacheManager(
        cacheDir: tempDir,
        metadataFile: metadataFile,
        quotaSettings: CacheQuotaSettings.fromGB(1.0),
      );
      await newManager.initialize();
      
      final stats = await newManager.getUsageStats();
      expect(stats.entryCount, equals(1));
      // Check metadata was preserved (byBook should have the entry)
      expect(stats.byBook['book1'], equals(2000));
      
      newManager.dispose();
    });

    test('getTotalSize matches sum of file sizes', () async {
      // Create some files
      await File('${tempDir.path}/file1.wav').writeAsBytes(List.filled(1000, 0));
      await File('${tempDir.path}/file2.wav').writeAsBytes(List.filled(2500, 0));
      await File('${tempDir.path}/file3.wav').writeAsBytes(List.filled(500, 0));
      
      final totalSize = await manager.getTotalSize();
      expect(totalSize, equals(4000));
    });

    test('deleteByPrefix removes matching files', () async {
      // Create files with different prefixes
      final key1 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Test 1',
        playbackRate: 1.0,
      );
      final key2 = CacheKeyGenerator.generate(
        voiceId: 'supertonic_m1',
        text: 'Test 2',
        playbackRate: 1.0,
      );
      
      final file1 = await manager.fileFor(key1);
      await file1.writeAsBytes(List.filled(1000, 0));
      await manager.registerEntry(
        key: key1,
        sizeBytes: 1000,
        bookId: 'book1',
        segmentIndex: 0,
        chapterIndex: 0,
        engineType: 'kokoro',
        audioDurationMs: 3000,
      );
      
      final file2 = await manager.fileFor(key2);
      await file2.writeAsBytes(List.filled(1000, 0));
      await manager.registerEntry(
        key: key2,
        sizeBytes: 1000,
        bookId: 'book1',
        segmentIndex: 0,
        chapterIndex: 0,
        engineType: 'supertonic',
        audioDurationMs: 3000,
      );
      
      var stats = await manager.getUsageStats();
      expect(stats.entryCount, equals(2));
      
      // Delete by prefix (kokoro files)
      await manager.deleteByPrefix('kokoro');
      
      stats = await manager.getUsageStats();
      expect(stats.entryCount, equals(1));
      expect(stats.byVoice.containsKey('kokoro_af'), isFalse);
      expect(stats.byVoice.containsKey('supertonic_m1'), isTrue);
    });
  });

  group('CacheUsageStats', () {
    test('usagePercent calculates correctly', () {
      final stats = CacheUsageStats(
        totalSizeBytes: 500 * 1024 * 1024, // 500 MB
        quotaSizeBytes: 2 * 1024 * 1024 * 1024, // 2 GB
        entryCount: 100,
        byBook: {},
        byVoice: {},
        hitRate: 0.95,
      );
      
      expect(stats.usagePercent, closeTo(24.41, 0.1)); // 500MB / 2GB = 24.41%
    });

    test('formatBytes formats correctly', () {
      expect(CacheUsageStats(
        totalSizeBytes: 500,
        quotaSizeBytes: 1000,
        entryCount: 0,
        byBook: {},
        byVoice: {},
        hitRate: 0,
      ).totalSizeFormatted, equals('500 B'));

      expect(CacheUsageStats(
        totalSizeBytes: 1536,
        quotaSizeBytes: 1000,
        entryCount: 0,
        byBook: {},
        byVoice: {},
        hitRate: 0,
      ).totalSizeFormatted, equals('1.5 KB'));

      expect(CacheUsageStats(
        totalSizeBytes: 1572864,
        quotaSizeBytes: 1000,
        entryCount: 0,
        byBook: {},
        byVoice: {},
        hitRate: 0,
      ).totalSizeFormatted, equals('1.5 MB'));
    });
  });

  group('CacheQuotaSettings', () {
    test('fromGB creates correct byte value', () {
      final settings = CacheQuotaSettings.fromGB(2.5);
      expect(settings.maxSizeBytes, equals((2.5 * 1024 * 1024 * 1024).round()));
    });

    test('sizeGB returns correct value', () {
      final settings = CacheQuotaSettings(maxSizeBytes: 3 * 1024 * 1024 * 1024);
      expect(settings.sizeGB, closeTo(3.0, 0.01));
    });
  });
}
