import 'dart:async';
import 'dart:collection';

/// Simple semaphore for concurrency control.
///
/// Limits the number of concurrent operations. When all slots are taken,
/// new acquirers wait until a slot is released.
class Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final Queue<Completer<void>> _waiters = Queue();

  /// Create a semaphore with [maxCount] concurrent slots.
  Semaphore(this._maxCount) : assert(_maxCount > 0);

  /// Number of available slots.
  int get available => _maxCount - _currentCount;

  /// Whether any slots are available.
  bool get hasAvailable => _currentCount < _maxCount;

  /// Current number of active acquisitions.
  int get activeCount => _currentCount;

  /// Maximum concurrent count.
  int get maxCount => _maxCount;

  /// Acquire a slot. Returns immediately if available, otherwise waits.
  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  /// Try to acquire a slot without waiting.
  /// Returns true if acquired, false if no slots available.
  bool tryAcquire() {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return true;
    }
    return false;
  }

  /// Release a slot. If waiters are queued, the first one is resumed.
  void release() {
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      waiter.complete();
    } else if (_currentCount > 0) {
      _currentCount--;
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
}
