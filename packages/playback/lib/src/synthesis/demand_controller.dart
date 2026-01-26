import 'dart:async';

import 'buffer_gauge.dart';
import 'demand_signal.dart';

/// Callback when concurrency should be adjusted.
typedef ConcurrencyChangeCallback = void Function(
    int newConcurrency, DemandLevel reason);

/// Controller that monitors demand and manages synthesis concurrency.
///
/// DemandController is the main orchestrator for auto-calibration:
/// 1. Uses [BufferGauge] to monitor buffer status
/// 2. Responds to [DemandSignal]s with concurrency adjustments
/// 3. Applies hysteresis to prevent thrashing
/// 4. Respects device capability ceilings
///
/// Example usage:
/// ```dart
/// final controller = DemandController(
///   bufferGauge: gauge,
///   onConcurrencyChange: (newConcurrency, reason) {
///     coordinator.setConcurrency(newConcurrency);
///   },
///   baselineConcurrency: 2,
///   maxConcurrency: 4,
/// );
///
/// controller.start();
/// ```
class DemandController {
  /// Buffer gauge that provides demand signals.
  final BufferGauge bufferGauge;

  /// Callback when concurrency should change.
  final ConcurrencyChangeCallback onConcurrencyChange;

  /// Learned optimal concurrency for this device.
  /// Used as the baseline for cruise mode.
  int baselineConcurrency;

  /// Maximum concurrency allowed (device capability ceiling).
  int maxConcurrency;

  /// Minimum time between non-emergency concurrency changes.
  final Duration cooldownPeriod;

  int _currentConcurrency;
  DateTime? _lastChange;
  StreamSubscription<DemandSignal>? _signalSubscription;

  /// Creates a DemandController.
  ///
  /// [bufferGauge] monitors buffer status and emits demand signals.
  /// [onConcurrencyChange] is called when concurrency should be adjusted.
  /// [baselineConcurrency] is the learned optimal concurrency (default 2).
  /// [maxConcurrency] is the device's absolute limit (default 4).
  /// [cooldownPeriod] prevents thrashing (default 5 seconds).
  DemandController({
    required this.bufferGauge,
    required this.onConcurrencyChange,
    this.baselineConcurrency = 2,
    this.maxConcurrency = 4,
    this.cooldownPeriod = const Duration(seconds: 5),
  }) : _currentConcurrency = baselineConcurrency;

  /// Current concurrency level.
  int get currentConcurrency => _currentConcurrency;

  /// Whether the controller is actively managing concurrency.
  bool get isActive => _signalSubscription != null;

  /// Current demand level from the buffer gauge.
  DemandLevel? get currentDemandLevel => bufferGauge.currentLevel;

  /// Time since last concurrency change.
  Duration? get timeSinceLastChange =>
      _lastChange != null ? DateTime.now().difference(_lastChange!) : null;

  /// Start managing concurrency based on demand.
  void start() {
    if (_signalSubscription != null) return; // Already running

    // Subscribe to demand signals
    _signalSubscription = bufferGauge.demandStream.listen(_handleSignal);

    // Start the buffer gauge if not already running
    bufferGauge.start();
  }

  /// Stop managing concurrency.
  void stop() {
    _signalSubscription?.cancel();
    _signalSubscription = null;
    bufferGauge.stop();
  }

  /// Update the baseline concurrency (from learning or settings).
  void updateBaseline(int newBaseline) {
    baselineConcurrency = newBaseline.clamp(1, maxConcurrency);
  }

  /// Update the maximum concurrency (from device detection).
  void updateMaxConcurrency(int newMax) {
    maxConcurrency = newMax.clamp(1, 8); // Hard cap at 8
    // Also update baseline if it exceeded new max
    if (baselineConcurrency > maxConcurrency) {
      baselineConcurrency = maxConcurrency;
    }
  }

  void _handleSignal(DemandSignal signal) {
    final recommended = signal.recommendedConcurrency(
      baselineConcurrency: baselineConcurrency,
      maxConcurrency: maxConcurrency,
    );

    // Check if we should change
    if (recommended == _currentConcurrency) return;

    // Emergency situations bypass cooldown
    if (signal.bypassesCooldown) {
      _setConcurrency(recommended, signal.level);
      return;
    }

    // Normal changes respect cooldown
    if (_lastChange != null &&
        DateTime.now().difference(_lastChange!) < cooldownPeriod) {
      return; // Too soon, skip this change
    }

    // Gradual changes: only move by 1 at a time (except emergency)
    int targetConcurrency;
    if (recommended > _currentConcurrency) {
      targetConcurrency = _currentConcurrency + 1;
    } else {
      targetConcurrency = _currentConcurrency - 1;
    }

    _setConcurrency(targetConcurrency, signal.level);
  }

  void _setConcurrency(int newConcurrency, DemandLevel reason) {
    final clamped = newConcurrency.clamp(1, maxConcurrency);
    if (clamped == _currentConcurrency) return;

    _currentConcurrency = clamped;
    _lastChange = DateTime.now();

    onConcurrencyChange(clamped, reason);
  }

  /// Dispose of resources.
  void dispose() {
    stop();
    bufferGauge.dispose();
  }
}

/// Extension for testing and debugging.
extension DemandControllerDebug on DemandController {
  /// Get a snapshot of current state for debugging.
  Map<String, dynamic> get debugSnapshot => {
        'isActive': isActive,
        'currentConcurrency': currentConcurrency,
        'baselineConcurrency': baselineConcurrency,
        'maxConcurrency': maxConcurrency,
        'currentDemandLevel': currentDemandLevel?.name,
        'timeSinceLastChange': timeSinceLastChange?.inSeconds,
        ...bufferGauge.debugSnapshot,
      };
}
