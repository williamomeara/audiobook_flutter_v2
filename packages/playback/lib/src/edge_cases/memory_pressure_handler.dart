import 'dart:async';
import 'dart:developer' as developer;

import '../adaptive_prefetch.dart';

/// Callback when memory pressure requires action.
typedef MemoryPressureAction = Future<void> Function(MemoryPressure level);

/// Handles memory pressure events during playback.
///
/// When the system reports memory pressure:
/// 1. Reduces prefetch window size
/// 2. Pauses new synthesis operations (if critical)
/// 3. Requests cache trimming
/// 4. Triggers rollback if performance degrades
///
/// Integrates with Android's ComponentCallbacks2.onTrimMemory().
class MemoryPressureHandler {
  MemoryPressureHandler({
    required MemoryPressureAction onReducePrefetch,
    required MemoryPressureAction onPauseSynthesis,
    required MemoryPressureAction onTrimCache,
    required MemoryPressureAction onResumeSynthesis,
    Duration recoveryDelay = const Duration(seconds: 10),
  }) : _onReducePrefetch = onReducePrefetch,
       _onPauseSynthesis = onPauseSynthesis,
       _onTrimCache = onTrimCache,
       _onResumeSynthesis = onResumeSynthesis,
       _recoveryDelay = recoveryDelay;

  final MemoryPressureAction _onReducePrefetch;
  final MemoryPressureAction _onPauseSynthesis;
  final MemoryPressureAction _onTrimCache;
  final MemoryPressureAction _onResumeSynthesis;
  final Duration _recoveryDelay;

  MemoryPressure _currentPressure = MemoryPressure.none;
  Timer? _recoveryTimer;
  bool _synthesisPaused = false;
  DateTime? _lastPressureTime;

  /// Current memory pressure level.
  MemoryPressure get currentPressure => _currentPressure;

  /// Whether synthesis is currently paused due to memory pressure.
  bool get isSynthesisPaused => _synthesisPaused;

  /// Time since last pressure event, or null if never pressured.
  Duration? get timeSinceLastPressure => _lastPressureTime != null
      ? DateTime.now().difference(_lastPressureTime!)
      : null;

  /// Handle a memory pressure event from the platform.
  ///
  /// [level] is the pressure level reported by the OS.
  Future<void> handlePressure(MemoryPressure level) async {
    // Track the event
    _lastPressureTime = DateTime.now();
    
    // Log pressure changes
    if (level != _currentPressure) {
      developer.log(
        '[MemoryPressureHandler] Pressure changed: $_currentPressure -> $level',
        name: 'MemoryPressureHandler',
      );
    }

    // Cancel any pending recovery
    _recoveryTimer?.cancel();
    _recoveryTimer = null;

    _currentPressure = level;

    switch (level) {
      case MemoryPressure.none:
        // Pressure relieved - resume normal operation
        if (_synthesisPaused) {
          developer.log(
            '[MemoryPressureHandler] Memory pressure relieved, resuming synthesis',
            name: 'MemoryPressureHandler',
          );
          _synthesisPaused = false;
          await _onResumeSynthesis(level);
        }
        break;

      case MemoryPressure.moderate:
        // Moderate pressure - reduce prefetch but keep synthesis running
        developer.log(
          '[MemoryPressureHandler] Moderate pressure - reducing prefetch',
          name: 'MemoryPressureHandler',
        );
        await _onReducePrefetch(level);
        await _onTrimCache(level);
        
        // Schedule recovery check if pressure doesn't increase
        _scheduleRecoveryCheck();
        break;

      case MemoryPressure.critical:
        // Critical pressure - pause synthesis and aggressively trim
        developer.log(
          '[MemoryPressureHandler] CRITICAL pressure - pausing synthesis',
          name: 'MemoryPressureHandler',
        );
        
        if (!_synthesisPaused) {
          _synthesisPaused = true;
          await _onPauseSynthesis(level);
        }
        
        await _onReducePrefetch(level);
        await _onTrimCache(level);
        
        // Schedule recovery check
        _scheduleRecoveryCheck();
        break;
    }
  }

  /// Schedule a check to see if we can resume normal operation.
  void _scheduleRecoveryCheck() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(_recoveryDelay, () async {
      // If we're still at critical, stay paused
      if (_currentPressure == MemoryPressure.critical) {
        developer.log(
          '[MemoryPressureHandler] Still critical after recovery delay',
          name: 'MemoryPressureHandler',
        );
        return;
      }

      // If we haven't received new pressure events, try resuming
      if (_synthesisPaused && _currentPressure != MemoryPressure.critical) {
        developer.log(
          '[MemoryPressureHandler] Recovery timer: attempting resume',
          name: 'MemoryPressureHandler',
        );
        _synthesisPaused = false;
        await _onResumeSynthesis(_currentPressure);
      }
    });
  }

  /// Manually trigger cache trimming.
  Future<void> requestCacheTrim() async {
    developer.log(
      '[MemoryPressureHandler] Manual cache trim requested',
      name: 'MemoryPressureHandler',
    );
    await _onTrimCache(_currentPressure);
  }

  /// Check if synthesis should proceed given current pressure.
  bool canStartSynthesis() {
    if (_synthesisPaused) {
      developer.log(
        '[MemoryPressureHandler] Synthesis blocked: paused for memory pressure',
        name: 'MemoryPressureHandler',
      );
      return false;
    }
    return true;
  }

  /// Dispose resources.
  void dispose() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }
}
