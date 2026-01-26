import 'dart:io';

import 'package:core_domain/core_domain.dart';

/// Q3: WAV header size constant (standard PCM format).
/// Used for checking if audio files are complete (must be > header size).
const kWavHeaderSize = 44;

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
  /// Returns the WAV file path (for writing new entries).
  Future<File> fileFor(CacheKey key);

  /// Get the actual playable file for a cache key.
  /// Returns the M4A file if it exists, otherwise the WAV file.
  /// This allows transparent playback of both compressed and uncompressed entries.
  Future<File?> playableFileFor(CacheKey key);

  /// Check if a cached file is ready (exists and is complete).
  /// Returns true if either WAV or M4A version exists.
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
  
  /// Pin a file to prevent it from being evicted during pruning.
  /// Returns true if the file was pinned, false if already pinned.
  bool pin(CacheKey key);
  
  /// Unpin a file, allowing it to be evicted if needed.
  /// Returns true if the file was unpinned, false if wasn't pinned.
  bool unpin(CacheKey key);
  
  /// Check if a file is currently pinned.
  bool isPinned(CacheKey key);
  
  /// Get the cache directory.
  Directory get directory;
}

/// File-based audio cache implementation with LRU eviction.
class FileAudioCache implements AudioCache {
  FileAudioCache({required this.cacheDir});

  /// Directory where cache files are stored.
  final Directory cacheDir;

  /// Track last-used times for LRU eviction.
  final Map<String, DateTime> _usageTimes = {};
  
  /// Set of pinned filenames that should not be evicted.
  final Set<String> _pinnedFiles = {};

  @override
  Directory get directory => cacheDir;

  @override
  Future<File> fileFor(CacheKey key) async {
    await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/${key.toFilename()}');
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
  Future<bool> isReady(CacheKey key) async {
    final wavFile = await fileFor(key);
    final m4aPath = wavFile.path.replaceAll('.wav', '.m4a');
    final m4aFile = File(m4aPath);
    
    // Check M4A first (compressed version)
    if (await m4aFile.exists()) {
      final stat = await m4aFile.stat();
      if (stat.size > 0) return true;
    }
    
    // Check WAV (uncompressed)
    if (await wavFile.exists()) {
      final stat = await wavFile.stat();
      return stat.size > kWavHeaderSize;
    }
    
    return false;
  }

  @override
  Future<void> markUsed(CacheKey key) async {
    _usageTimes[key.toFilename()] = DateTime.now();
  }
  
  @override
  bool pin(CacheKey key) {
    final filename = key.toFilename();
    if (_pinnedFiles.contains(filename)) return false;
    _pinnedFiles.add(filename);
    return true;
  }
  
  @override
  bool unpin(CacheKey key) {
    final filename = key.toFilename();
    return _pinnedFiles.remove(filename);
  }
  
  @override
  bool isPinned(CacheKey key) {
    return _pinnedFiles.contains(key.toFilename());
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
      final filename = file.uri.pathSegments.last;
      final stat = await file.stat();
      final age = now.difference(stat.modified);
      
      // Skip pinned files - they are currently in use
      if (_pinnedFiles.contains(filename)) {
        totalSize += stat.size;
        continue;
      }
      
      // Delete if too old (and not pinned)
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
        
        // Skip pinned files
        final filename = file.uri.pathSegments.last;
        if (_pinnedFiles.contains(filename)) continue;
        
        final stat = await file.stat();
        toDelete.add(file);
        totalSize -= stat.size;
      }
    }

    // Delete marked files (all non-pinned)
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
    _pinnedFiles.clear();
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
