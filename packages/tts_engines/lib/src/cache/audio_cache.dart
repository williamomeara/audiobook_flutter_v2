import 'dart:io';

import 'package:core_domain/core_domain.dart';

/// Budget configuration for audio cache.
class CacheBudget {
  const CacheBudget({
    this.maxSizeBytes = 500 * 1024 * 1024, // 500 MB default
    this.maxAgeMs = 7 * 24 * 60 * 60 * 1000, // 7 days default
  });

  /// Maximum total cache size in bytes.
  final int maxSizeBytes;

  /// Maximum age for cache entries in milliseconds.
  final int maxAgeMs;

  static const defaultBudget = CacheBudget();
}

/// Interface for audio file caching.
abstract interface class AudioCache {
  /// Get or create the file for a cache key.
  Future<File> fileFor(CacheKey key);

  /// Check if a cached file is ready (exists and is complete).
  Future<bool> isReady(CacheKey key);

  /// Mark a cache entry as recently used (for LRU).
  Future<void> markUsed(CacheKey key);

  /// Prune cache if it exceeds budget.
  Future<void> pruneIfNeeded({CacheBudget budget = CacheBudget.defaultBudget});

  /// Delete all cache entries with a given prefix.
  Future<void> deleteByPrefix(String prefix);

  /// Get the total cache size in bytes.
  Future<int> getTotalSize();

  /// Clear all cached files.
  Future<void> clear();
}

/// File-based audio cache implementation with LRU eviction.
class FileAudioCache implements AudioCache {
  FileAudioCache({required this.cacheDir});

  /// Directory where cache files are stored.
  final Directory cacheDir;

  /// Track last-used times for LRU eviction.
  final Map<String, DateTime> _usageTimes = {};

  @override
  Future<File> fileFor(CacheKey key) async {
    await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/${key.toFilename()}');
  }

  @override
  Future<bool> isReady(CacheKey key) async {
    final file = await fileFor(key);
    if (!await file.exists()) return false;
    
    // Check file has content (not empty or incomplete)
    final stat = await file.stat();
    return stat.size > 44; // WAV header is at least 44 bytes
  }

  @override
  Future<void> markUsed(CacheKey key) async {
    _usageTimes[key.toFilename()] = DateTime.now();
  }

  @override
  Future<void> pruneIfNeeded({
    CacheBudget budget = CacheBudget.defaultBudget,
  }) async {
    if (!await cacheDir.exists()) return;

    final files = await _getSortedCacheFiles();
    var totalSize = 0;
    final now = DateTime.now();
    final maxAge = Duration(milliseconds: budget.maxAgeMs);

    // Calculate total size and mark files for deletion
    final toDelete = <File>[];
    
    for (final file in files) {
      final stat = await file.stat();
      final age = now.difference(stat.modified);
      
      // Delete if too old
      if (age > maxAge) {
        toDelete.add(file);
        continue;
      }
      
      totalSize += stat.size;
    }

    // If still over budget, delete oldest files first
    if (totalSize > budget.maxSizeBytes) {
      // Sort by last modified (oldest first)
      files.sort((a, b) {
        final aTime = _usageTimes[a.uri.pathSegments.last] ?? DateTime(2000);
        final bTime = _usageTimes[b.uri.pathSegments.last] ?? DateTime(2000);
        return aTime.compareTo(bTime);
      });

      for (final file in files) {
        if (totalSize <= budget.maxSizeBytes) break;
        if (toDelete.contains(file)) continue;
        
        final stat = await file.stat();
        toDelete.add(file);
        totalSize -= stat.size;
      }
    }

    // Delete marked files
    for (final file in toDelete) {
      try {
        await file.delete();
        _usageTimes.remove(file.uri.pathSegments.last);
      } catch (_) {
        // Best effort deletion
      }
    }
  }

  @override
  Future<void> deleteByPrefix(String prefix) async {
    if (!await cacheDir.exists()) return;

    await for (final entity in cacheDir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if (name.startsWith(prefix)) {
          try {
            await entity.delete();
            _usageTimes.remove(name);
          } catch (_) {
            // Best effort
          }
        }
      }
    }
  }

  @override
  Future<int> getTotalSize() async {
    if (!await cacheDir.exists()) return 0;

    var total = 0;
    await for (final entity in cacheDir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  @override
  Future<void> clear() async {
    if (!await cacheDir.exists()) return;

    await for (final entity in cacheDir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Best effort
      }
    }
    _usageTimes.clear();
  }

  /// Get all cache files sorted by last modified time.
  Future<List<File>> _getSortedCacheFiles() async {
    final files = <File>[];
    
    if (!await cacheDir.exists()) return files;

    await for (final entity in cacheDir.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        files.add(entity);
      }
    }

    return files;
  }

  /// Get filename for a cache key (convenience method).
  String filenameForKey(CacheKey key) => key.toFilename();
}
