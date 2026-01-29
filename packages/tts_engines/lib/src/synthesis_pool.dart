import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:core_domain/core_domain.dart';

import 'interfaces/ai_voice_engine.dart';
import 'interfaces/segment_synth_request.dart';
import 'cache/audio_cache.dart';

/// Synthesis pool for managing concurrent TTS requests.
///
/// Features:
/// - Deduplication of identical requests
/// - Cancellation support
/// - Concurrent limit to avoid OOM
/// - Priority-based scheduling
class SynthesisPool {
  SynthesisPool({
    required AiVoiceEngine engine,
    required AudioCache cache,
    this.maxConcurrent = 2,
  })  : _engine = engine,
        _cache = cache;

  final AiVoiceEngine _engine;
  final AudioCache _cache;
  final int maxConcurrent;

  /// Pending futures by cache key (for deduplication).
  final Map<String, Completer<File>> _pending = {};

  /// Active requests by operation ID.
  final Map<String, SegmentSynthRequest> _activeRequests = {};

  /// Queue of pending requests.
  final Queue<SegmentSynthRequest> _queue = Queue();

  /// Currently executing count.
  int _executingCount = 0;

  /// Disposed flag.
  bool _disposed = false;

  /// Enqueue a synthesis request.
  ///
  /// Returns a future that completes when synthesis is done.
  /// If an identical request is already pending, returns the same future.
  Future<File> enqueue(SegmentSynthRequest request) {
    if (_disposed) {
      return Future.error(
        StateError('SynthesisPool is disposed'),
      );
    }

    final key = request.cacheKey;

    // Check for existing pending request
    if (_pending.containsKey(key)) {
      return _pending[key]!.future;
    }

    final completer = Completer<File>();
    _pending[key] = completer;
    _activeRequests[request.opId] = request;
    _queue.add(request);

    _scheduleNext();

    return completer.future;
  }

  /// Cancel a specific request by operation ID.
  void cancel(String opId) {
    final request = _activeRequests[opId];
    if (request != null) {
      request.cancel();
      _engine.cancelSynth(opId);
      
      // Complete with error if still pending
      final completer = _pending[request.cacheKey];
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          SynthesisException('Cancelled', voiceId: request.voiceId),
        );
      }
      
      _cleanup(request);
    }
  }

  /// Cancel all pending and active requests.
  void cancelAll() {
    for (final opId in _activeRequests.keys.toList()) {
      cancel(opId);
    }
    _queue.clear();
  }

  /// Get the number of pending requests.
  int get pendingCount => _pending.length;

  /// Get the number of currently executing requests.
  int get executingCount => _executingCount;

  /// Dispose the pool and cancel all requests.
  Future<void> dispose() async {
    _disposed = true;
    cancelAll();
  }

  void _scheduleNext() {
    while (_executingCount < maxConcurrent && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      
      if (request.isCancelled) {
        _cleanup(request);
        continue;
      }

      _executingCount++;
      _execute(request);
    }
  }

  Future<void> _execute(SegmentSynthRequest request) async {
    final key = request.cacheKey;
    final completer = _pending[key];

    if (completer == null || completer.isCompleted) {
      _executingCount--;
      _scheduleNext();
      return;
    }

    try {
      // Check cache first
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: request.voiceId,
        text: request.normalizedText,
        playbackRate: request.playbackRate,
      );

      if (await _cache.isReady(cacheKey)) {
        final file = await _cache.fileFor(cacheKey);
        await _cache.markUsed(cacheKey);
        completer.complete(file);
      } else {
        // Synthesize
        final result = await _engine.synthesizeSegment(request);

        if (request.isCancelled) {
          if (!completer.isCompleted) {
            completer.completeError(
              SynthesisException('Cancelled', voiceId: request.voiceId),
            );
          }
        } else if (result.success && result.outputFile != null) {
          // Note: This pool is legacy - the main synthesis flow uses SynthesisCoordinator
          // which handles full cache registration. markUsed here provides basic tracking,
          // and CacheReconciliationService handles any orphan files on startup.
          await _cache.markUsed(cacheKey);
          completer.complete(File(result.outputFile!));
        } else {
          completer.completeError(
            SynthesisException(
              result.errorMessage ?? 'Synthesis failed',
              voiceId: request.voiceId,
            ),
          );
        }
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(
          SynthesisException(e.toString(), voiceId: request.voiceId),
        );
      }
    } finally {
      _cleanup(request);
      _executingCount--;
      _scheduleNext();
    }
  }

  void _cleanup(SegmentSynthRequest request) {
    _pending.remove(request.cacheKey);
    _activeRequests.remove(request.opId);
  }
}

/// Model cache manager for device-aware memory management.
class ModelCacheManager {
  ModelCacheManager({
    required AiVoiceEngine engine,
    required this.deviceMemoryMB,
  }) : _engine = engine;

  final AiVoiceEngine _engine;
  final int deviceMemoryMB;

  /// Get max models to keep loaded based on device RAM.
  int get maxLoadedModels {
    if (deviceMemoryMB <= 4096) return 1;  // 4GB
    if (deviceMemoryMB <= 8192) return 2;  // 8GB
    return 3;  // 12GB+
  }

  /// Ensure memory is within budget before loading a new model.
  Future<void> ensureMemoryBudget() async {
    final loadedCount = await _engine.getLoadedModelCount();
    
    while (loadedCount >= maxLoadedModels) {
      await _engine.unloadLeastUsedModel();
      
      // Prevent infinite loop
      final newCount = await _engine.getLoadedModelCount();
      if (newCount >= loadedCount) break;
    }
  }

  /// Clear all models from memory.
  Future<void> clearAll() async {
    await _engine.clearAllModels();
  }
}
