import 'dart:async';

import 'demand_signal.dart';

/// Monitors buffer status and emits [DemandSignal]s.
///
/// The BufferGauge tracks how far ahead the synthesis system is compared
/// to current playback position, and emits signals that the
/// [ConcurrencyGovernor] uses to adjust synthesis concurrency.
///
/// Example usage:
/// ```dart
/// final gauge = BufferGauge(
///   getBufferAheadMs: () => coordinator.estimateBufferedAheadMs(...),
///   getPlaybackRate: () => playbackState.playbackRate,
///   isPlaying: () => playbackState.isPlaying,
/// );
///
/// gauge.demandStream.listen((signal) {
///   concurrencyGovernor.respondToSignal(signal);
/// });
///
/// gauge.start();
/// ```
class BufferGauge {
  /// Function that returns current buffered audio ahead in milliseconds.
  final int Function() getBufferAheadMs;

  /// Function that returns current playback rate (1.0 = normal).
  final double Function() getPlaybackRate;

  /// Function that returns whether playback is currently active.
  final bool Function() isPlaying;

  /// How often to sample buffer status.
  final Duration sampleInterval;

  Timer? _sampleTimer;
  final _demandController = StreamController<DemandSignal>.broadcast();
  DemandSignal? _lastSignal;

  /// Creates a BufferGauge with the required callbacks.
  ///
  /// [getBufferAheadMs] should return the estimated buffered audio in ms.
  /// [getPlaybackRate] should return the current playback speed multiplier.
  /// [isPlaying] should return whether audio is currently playing.
  /// [sampleInterval] controls how often to check buffer status.
  BufferGauge({
    required this.getBufferAheadMs,
    required this.getPlaybackRate,
    required this.isPlaying,
    this.sampleInterval = const Duration(seconds: 1),
  });

  /// Stream of demand signals based on buffer status.
  ///
  /// Emits whenever:
  /// - The demand level changes
  /// - Periodically at [sampleInterval] during playback
  Stream<DemandSignal> get demandStream => _demandController.stream;

  /// The most recently emitted demand signal.
  DemandSignal? get currentSignal => _lastSignal;

  /// Current demand level (convenience getter).
  DemandLevel? get currentLevel => _lastSignal?.level;

  /// Whether the gauge is actively monitoring.
  bool get isMonitoring => _sampleTimer != null;

  /// Start monitoring buffer status.
  ///
  /// The gauge will sample at [sampleInterval] and emit [DemandSignal]s
  /// when the demand level changes or periodically during playback.
  void start() {
    if (_sampleTimer != null) return; // Already running

    _sampleTimer = Timer.periodic(sampleInterval, (_) => _sample());

    // Emit initial signal immediately
    _sample();
  }

  /// Stop monitoring buffer status.
  void stop() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
  }

  /// Force a sample and emit if changed.
  ///
  /// Useful when playback state changes (seek, rate change, etc).
  void forceSample() => _sample();

  void _sample() {
    // Only emit signals during active playback
    if (!isPlaying()) {
      return;
    }

    final bufferMs = getBufferAheadMs();
    final bufferSeconds = bufferMs / 1000.0;
    final playbackRate = getPlaybackRate();

    final level = DemandThresholds.calculateLevel(bufferSeconds, playbackRate);

    final signal = DemandSignal(
      level: level,
      bufferSeconds: bufferSeconds,
      playbackRate: playbackRate,
      timestamp: DateTime.now(),
    );

    // Only emit if level changed or it's a critical/emergency situation
    // (we want frequent updates in emergency situations)
    final shouldEmit = _lastSignal == null ||
        _lastSignal!.level != level ||
        level == DemandLevel.critical ||
        level == DemandLevel.emergency;

    if (shouldEmit) {
      _lastSignal = signal;
      _demandController.add(signal);
    }
  }

  /// Dispose of resources.
  void dispose() {
    stop();
    _demandController.close();
  }
}

/// Extension for testing and debugging.
extension BufferGaugeDebug on BufferGauge {
  /// Get a snapshot of current state for debugging.
  Map<String, dynamic> get debugSnapshot => {
        'isMonitoring': isMonitoring,
        'currentLevel': currentLevel?.name,
        'bufferSeconds': currentSignal?.bufferSeconds,
        'playbackRate': currentSignal?.playbackRate,
      };
}
