import 'dart:async';
import 'dart:collection';

/// A semaphore that supports dynamic slot count adjustment at runtime.
///
/// Unlike the basic [Semaphore], this allows increasing or decreasing
/// the maximum concurrent permits without replacing the semaphore object.
///
/// ## Best Practices (from research)
///
/// - **Increasing slots**: Safe - immediately wake waiting tasks
/// - **Decreasing slots**: Cannot revoke in-use permits; just prevents new acquires
///   until natural release brings count below new limit
/// - **Never replace** the semaphore object at runtime - risk of deadlocks
/// - **Track permits** to avoid over-release
///
/// ## Example
/// ```dart
/// final sem = DynamicSemaphore(2);
///
/// // Later, scale up based on demand
/// sem.maxSlots = 4; // Immediately wakes 2 waiting tasks if any
///
/// // Scale down during coast
/// sem.maxSlots = 1; // Won't affect current 4 active; just limits future
/// ```
class DynamicSemaphore {
  int _maxSlots;
  int _activeSlots = 0;
  final Queue<Completer<void>> _waitQueue = Queue();

  /// Create a semaphore with initial [maxSlots] concurrent permits.
  DynamicSemaphore(int maxSlots)
      : _maxSlots = maxSlots,
        assert(maxSlots > 0);

  /// Current maximum concurrent permits.
  int get maxSlots => _maxSlots;

  /// Adjust maximum concurrent permits at runtime.
  ///
  /// **Increasing:** Immediately wakes waiting tasks up to the new limit.
  /// **Decreasing:** Cannot revoke active permits. New limit takes effect
  /// as tasks naturally release, blocking new acquires until count is below limit.
  set maxSlots(int value) {
    if (value < 1) value = 1; // Minimum 1 slot
    if (value == _maxSlots) return;

    final oldMax = _maxSlots;
    _maxSlots = value;

    // If increasing, wake waiting tasks
    if (value > oldMax) {
      _wakeWaiters();
    }
    // If decreasing, no action needed - just affects future acquires
  }

  /// Number of permits currently in use.
  int get activeCount => _activeSlots;

  /// Number of available permits (can be negative if over-subscribed during scale-down).
  int get available => _maxSlots - _activeSlots;

  /// Whether any permits are immediately available.
  bool get hasAvailable => _activeSlots < _maxSlots;

  /// Number of tasks waiting for a permit.
  int get waitingCount => _waitQueue.length;

  /// Acquire a permit, waiting if necessary.
  ///
  /// Returns a [Future] that completes when a permit is acquired.
  /// Call [release] when done.
  Future<void> acquire() async {
    if (_activeSlots < _maxSlots) {
      _activeSlots++;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  /// Try to acquire a permit without waiting.
  ///
  /// Returns `true` if a permit was acquired, `false` if none available.
  bool tryAcquire() {
    if (_activeSlots < _maxSlots) {
      _activeSlots++;
      return true;
    }
    return false;
  }

  /// Release a permit.
  ///
  /// If tasks are waiting, the first one is woken.
  /// If no waiters and under limit, decrements active count.
  void release() {
    if (_waitQueue.isNotEmpty && _activeSlots < _maxSlots) {
      // Wake a waiter (active count stays same)
      final waiter = _waitQueue.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    } else if (_activeSlots > 0) {
      _activeSlots--;
      // Check if we can wake any waiters now
      _wakeWaiters();
    }
  }

  /// Execute [action] with automatic acquire/release.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }

  void _wakeWaiters() {
    // Wake as many waiters as we have available slots
    while (_waitQueue.isNotEmpty && _activeSlots < _maxSlots) {
      final waiter = _waitQueue.removeFirst();
      if (!waiter.isCompleted) {
        _activeSlots++;
        waiter.complete();
      }
    }
  }

  /// Cancel all waiting acquires.
  ///
  /// Use during shutdown. Completes all waiters' futures with an error.
  void cancelAllWaiters([Object? error]) {
    error ??= StateError('Semaphore cancelled');
    while (_waitQueue.isNotEmpty) {
      final waiter = _waitQueue.removeFirst();
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }
}

/// Extension for testing and debugging.
extension DynamicSemaphoreDebug on DynamicSemaphore {
  /// Get a snapshot of current state.
  Map<String, dynamic> get debugSnapshot => {
        'maxSlots': maxSlots,
        'activeCount': activeCount,
        'available': available,
        'waitingCount': waitingCount,
        'hasAvailable': hasAvailable,
      };
}
