import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/src/cache/audio_cache.dart';

void main() {
  late Directory tempDir;
  late FileAudioCache cache;
  
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_cache_test_');
    cache = FileAudioCache(cacheDir: tempDir);
  });
  
  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
  
  CacheKey createKey(String text, {String voice = 'test-voice', double rate = 1.0}) {
    return CacheKeyGenerator.generate(
      voiceId: voice,
      text: text,
      playbackRate: rate,
    );
  }
  
  Future<File> createCachedFile(CacheKey key, {int sizeBytes = 1000}) async {
    final file = await cache.fileFor(key);
    // Create a file with WAV-like content (at least 44 bytes header)
    final header = List<int>.filled(44, 0);
    final content = List<int>.filled(sizeBytes - 44, 0);
    await file.writeAsBytes([...header, ...content]);
    return file;
  }
  
  group('AudioCache file pinning', () {
    test('pin returns true for new pin', () {
      final key = createKey('test text');
      expect(cache.pin(key), isTrue);
    });
    
    test('pin returns false if already pinned', () {
      final key = createKey('test text');
      cache.pin(key);
      expect(cache.pin(key), isFalse);
    });
    
    test('unpin returns true if was pinned', () {
      final key = createKey('test text');
      cache.pin(key);
      expect(cache.unpin(key), isTrue);
    });
    
    test('unpin returns false if not pinned', () {
      final key = createKey('test text');
      expect(cache.unpin(key), isFalse);
    });
    
    test('isPinned reflects pin state', () {
      final key = createKey('test text');
      expect(cache.isPinned(key), isFalse);
      
      cache.pin(key);
      expect(cache.isPinned(key), isTrue);
      
      cache.unpin(key);
      expect(cache.isPinned(key), isFalse);
    });
  });
  
  group('AudioCache pruning with pinned files', () {
    test('pruneIfNeeded skips pinned files when over budget', () async {
      // Create multiple files
      final key1 = createKey('file 1');
      final key2 = createKey('file 2');
      final key3 = createKey('file 3');
      
      await createCachedFile(key1, sizeBytes: 1000);
      await createCachedFile(key2, sizeBytes: 1000);
      await createCachedFile(key3, sizeBytes: 1000);
      
      // Mark usage so LRU order is key1 (oldest), key2, key3 (newest)
      await cache.markUsed(key1);
      await Future.delayed(const Duration(milliseconds: 10));
      await cache.markUsed(key2);
      await Future.delayed(const Duration(milliseconds: 10));
      await cache.markUsed(key3);
      
      // Pin key1 (the oldest - would normally be deleted first)
      cache.pin(key1);
      
      // Prune with tiny budget
      await cache.pruneIfNeeded(
        budget: const CacheBudget(
          maxSizeBytes: 2000, // Only room for 2 files
          maxAgeMs: 999999999,
        ),
      );
      
      // key1 should still exist (pinned)
      final file1 = await cache.fileFor(key1);
      expect(await file1.exists(), isTrue, reason: 'Pinned file should not be deleted');
      
      // key2 should be deleted (oldest unpinned)
      final file2 = await cache.fileFor(key2);
      expect(await file2.exists(), isFalse, reason: 'Oldest unpinned file should be deleted');
      
      // key3 should still exist (newest)
      final file3 = await cache.fileFor(key3);
      expect(await file3.exists(), isTrue, reason: 'Newest file should not be deleted');
    });
    
    test('pruneIfNeeded skips pinned files even if too old', () async {
      final key = createKey('old file');
      final file = await createCachedFile(key);
      
      // Backdate the file to make it "old"
      final oldTime = DateTime.now().subtract(const Duration(days: 30));
      await file.setLastModified(oldTime);
      
      // Pin the file
      cache.pin(key);
      
      // Prune with short max age
      await cache.pruneIfNeeded(
        budget: const CacheBudget(
          maxSizeBytes: 999999999,
          maxAgeMs: 1000, // 1 second max age
        ),
      );
      
      // File should still exist because it's pinned
      expect(await file.exists(), isTrue);
    });
    
    test('clear also clears pinned files set', () async {
      final key = createKey('test');
      await createCachedFile(key);
      cache.pin(key);
      
      expect(cache.isPinned(key), isTrue);
      
      await cache.clear();
      
      expect(cache.isPinned(key), isFalse);
    });
  });
  
  group('AudioCache basic operations', () {
    test('fileFor creates directory if needed', () async {
      final subDir = Directory('${tempDir.path}/subdir');
      final subCache = FileAudioCache(cacheDir: subDir);
      
      final key = createKey('test');
      final file = await subCache.fileFor(key);
      
      expect(await subDir.exists(), isTrue);
      expect(file.path, contains('subdir'));
    });
    
    test('isReady returns false for non-existent file', () async {
      final key = createKey('missing');
      expect(await cache.isReady(key), isFalse);
    });
    
    test('isReady returns false for empty file', () async {
      final key = createKey('empty');
      final file = await cache.fileFor(key);
      await file.writeAsBytes([]);
      
      expect(await cache.isReady(key), isFalse);
    });
    
    test('isReady returns true for valid file', () async {
      final key = createKey('valid');
      await createCachedFile(key);
      
      expect(await cache.isReady(key), isTrue);
    });
    
    test('getTotalSize returns correct size', () async {
      await createCachedFile(createKey('file1'), sizeBytes: 100);
      await createCachedFile(createKey('file2'), sizeBytes: 200);
      
      final size = await cache.getTotalSize();
      expect(size, equals(300));
    });
    
    test('deleteByPrefix removes matching files', () async {
      final key1 = createKey('prefix_match_1', voice: 'voice-a');
      final key2 = createKey('prefix_match_2', voice: 'voice-a');
      final key3 = createKey('no_match', voice: 'voice-b');
      
      final file1 = await createCachedFile(key1);
      final file2 = await createCachedFile(key2);
      final file3 = await createCachedFile(key3);
      
      // Get the prefix (voice ID is part of the filename)
      final prefix = 'voice-a';
      await cache.deleteByPrefix(prefix);
      
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);
      expect(await file3.exists(), isTrue);
    });
  });
  
  group('AudioCache concurrent access protection', () {
    test('pinned file survives concurrent prune', () async {
      final key = createKey('concurrent');
      await createCachedFile(key);
      
      // Pin before any pruning
      cache.pin(key);
      
      // Run multiple concurrent prunes
      await Future.wait([
        cache.pruneIfNeeded(budget: const CacheBudget(maxSizeBytes: 0)),
        cache.pruneIfNeeded(budget: const CacheBudget(maxSizeBytes: 0)),
        cache.pruneIfNeeded(budget: const CacheBudget(maxSizeBytes: 0)),
      ]);
      
      final file = await cache.fileFor(key);
      expect(await file.exists(), isTrue);
    });
    
    test('unpin allows file to be pruned', () async {
      final key = createKey('unpin_test');
      await createCachedFile(key);
      
      cache.pin(key);
      
      // First prune - should not delete
      await cache.pruneIfNeeded(budget: const CacheBudget(maxSizeBytes: 0));
      final file = await cache.fileFor(key);
      expect(await file.exists(), isTrue);
      
      // Unpin
      cache.unpin(key);
      
      // Second prune - should delete
      await cache.pruneIfNeeded(budget: const CacheBudget(maxSizeBytes: 0));
      expect(await file.exists(), isFalse);
    });
  });
}
