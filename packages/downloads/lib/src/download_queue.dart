import 'dart:async';

/// State of the download queue.
class DownloadQueueState {
  const DownloadQueueState({
    this.queued = const [],
    this.active = const [],
  });

  final List<String> queued;
  final List<String> active;

  bool get isEmpty => queued.isEmpty && active.isEmpty;
  bool isQueued(String id) => queued.contains(id);
  bool isActive(String id) => active.contains(id);
  bool contains(String id) => isQueued(id) || isActive(id);
}

/// Manages a queue of downloads with concurrency limits.
class DownloadQueue {
  DownloadQueue({this.maxConcurrent = 1});

  final int maxConcurrent;
  final List<_QueuedDownload> _queue = [];
  final Set<String> _active = {};
  final Set<String> _cancelled = {};
  final _stateController = StreamController<DownloadQueueState>.broadcast();
  bool _processing = false;

  /// Add a download to the queue.
  /// Returns a future that completes when the download finishes.
  Future<void> enqueue(String id, Future<void> Function() downloadFn) {
    // Don't add duplicates
    if (_active.contains(id) || _queue.any((q) => q.id == id)) {
      return Future.value();
    }

    final completer = Completer<void>();
    _queue.add(_QueuedDownload(id, downloadFn, completer));
    _notifyState();
    _processQueue();
    return completer.future;
  }

  /// Cancel a queued or active download.
  void cancel(String id) {
    // Remove from queue if queued
    final removed = _queue.where((q) => q.id == id).toList();
    _queue.removeWhere((q) => q.id == id);

    // Complete with error for cancelled items
    for (final item in removed) {
      item.completer.completeError(DownloadCancelledException(id));
    }

    // Mark as cancelled (active downloads will check this)
    if (_active.contains(id)) {
      _cancelled.add(id);
    }

    _notifyState();
  }

  /// Check if a download was cancelled.
  bool isCancelled(String id) => _cancelled.contains(id);

  /// Clear cancelled flag (call after handling cancellation).
  void clearCancelled(String id) => _cancelled.remove(id);

  /// Move a download to the front of the queue.
  void prioritize(String id) {
    final idx = _queue.indexWhere((q) => q.id == id);
    if (idx > 0) {
      final item = _queue.removeAt(idx);
      _queue.insert(0, item);
      _notifyState();
    }
  }

  /// Get current queue state.
  DownloadQueueState get currentState => DownloadQueueState(
        queued: _queue.map((q) => q.id).toList(),
        active: _active.toList(),
      );

  /// Stream of queue state changes.
  Stream<DownloadQueueState> get stateStream => _stateController.stream;

  void _processQueue() {
    if (_processing) return;
    _processing = true;

    Future(() async {
      while (_active.length < maxConcurrent && _queue.isNotEmpty) {
        final item = _queue.removeAt(0);

        // Skip if cancelled while queued
        if (_cancelled.contains(item.id)) {
          _cancelled.remove(item.id);
          item.completer.completeError(DownloadCancelledException(item.id));
          continue;
        }

        _active.add(item.id);
        _notifyState();

        try {
          await item.downloadFn();

          // Check if cancelled during download
          if (_cancelled.contains(item.id)) {
            _cancelled.remove(item.id);
            item.completer.completeError(DownloadCancelledException(item.id));
          } else {
            item.completer.complete();
          }
        } catch (e) {
          item.completer.completeError(e);
        } finally {
          _active.remove(item.id);
          _cancelled.remove(item.id);
          _notifyState();
        }
      }
      _processing = false;
    });
  }

  void _notifyState() {
    _stateController.add(currentState);
  }

  /// Dispose the queue.
  void dispose() {
    _stateController.close();

    // Complete all pending with error
    for (final item in _queue) {
      item.completer.completeError(DownloadQueueDisposedException());
    }
    _queue.clear();
    _active.clear();
    _cancelled.clear();
  }
}

class _QueuedDownload {
  _QueuedDownload(this.id, this.downloadFn, this.completer);

  final String id;
  final Future<void> Function() downloadFn;
  final Completer<void> completer;
}

/// Exception thrown when a download is cancelled.
class DownloadCancelledException implements Exception {
  DownloadCancelledException(this.downloadId);
  final String downloadId;

  @override
  String toString() => 'Download cancelled: $downloadId';
}

/// Exception thrown when the queue is disposed.
class DownloadQueueDisposedException implements Exception {
  @override
  String toString() => 'Download queue was disposed';
}
