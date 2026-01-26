import 'dart:async';
import 'dart:developer' as dev;

import 'demand_signal.dart';
import 'dynamic_semaphore.dart';

/// Governs synthesis concurrency by adjusting semaphore slots based on demand.
///
/// The ConcurrencyGovernor is the bridge between [DemandController] (which
/// determines when to scale) and [DynamicSemaphore] (which controls actual
/// concurrency). It applies changes to engine-specific semaphores.
///
/// ## Responsibilities
/// - Adjust semaphore slots in response to demand signals
/// - Track concurrency per engine
/// - Log changes for debugging
/// - Provide status for developer UI
///
/// ## Example
/// ```dart
/// final governor = ConcurrencyGovernor(
///   engineSemaphores: {
///     'kokoro': DynamicSemaphore(2),
///     'piper': DynamicSemaphore(2),
///   },
/// );
///
/// // Wire up to demand controller
/// demandController.onConcurrencyChange = (concurrency, reason) {
///   governor.setConcurrency(concurrency, reason: reason);
/// };
/// ```
class ConcurrencyGovernor {
  /// Map of engine type to its semaphore.
  final Map<String, DynamicSemaphore> engineSemaphores;

  /// Whether to log concurrency changes.
  final bool enableLogging;

  /// Stream controller for concurrency change events.
  final _changeController = StreamController<ConcurrencyChangeEvent>.broadcast();

  /// History of recent changes (for debugging).
  final _changeHistory = <ConcurrencyChangeEvent>[];
  static const int _maxHistorySize = 20;

  /// Current target concurrency (applied to new semaphores).
  int _currentTargetConcurrency = 2;

  ConcurrencyGovernor({
    required this.engineSemaphores,
    this.enableLogging = true,
  });

  /// Stream of concurrency change events.
  Stream<ConcurrencyChangeEvent> get changes => _changeController.stream;

  /// Register a new semaphore (call when coordinator creates one).
  /// Applies current target concurrency to the new semaphore.
  void registerSemaphore(String engineType, DynamicSemaphore semaphore) {
    engineSemaphores[engineType] = semaphore;
    
    // Apply current target concurrency to new semaphore
    if (semaphore.maxSlots != _currentTargetConcurrency) {
      _setConcurrencyForEngine(engineType, _currentTargetConcurrency);
    }
    
    if (enableLogging) {
      dev.log(
        '[$engineType] Registered semaphore (maxSlots: ${semaphore.maxSlots}, '
        'target: $_currentTargetConcurrency)',
        name: 'ConcurrencyGovernor',
      );
    }
  }

  /// Get current concurrency for a specific engine.
  int getConcurrency(String engineType) {
    return engineSemaphores[engineType]?.maxSlots ?? 1;
  }

  /// Get active (in-use) count for a specific engine.
  int getActiveCount(String engineType) {
    return engineSemaphores[engineType]?.activeCount ?? 0;
  }

  /// Set concurrency for all engines.
  ///
  /// This is the main method called by [DemandController] when demand changes.
  void setConcurrency(int concurrency, {DemandLevel? reason}) {
    _currentTargetConcurrency = concurrency;
    for (final entry in engineSemaphores.entries) {
      _setConcurrencyForEngine(entry.key, concurrency, reason: reason);
    }
  }

  /// Set concurrency for a specific engine.
  ///
  /// Use this when engines need different concurrency levels
  /// (e.g., Piper is lighter than Kokoro).
  void setConcurrencyForEngine(
    String engineType,
    int concurrency, {
    DemandLevel? reason,
  }) {
    _setConcurrencyForEngine(engineType, concurrency, reason: reason);
  }

  void _setConcurrencyForEngine(
    String engineType,
    int concurrency, {
    DemandLevel? reason,
  }) {
    final semaphore = engineSemaphores[engineType];
    if (semaphore == null) return;

    final oldConcurrency = semaphore.maxSlots;
    if (oldConcurrency == concurrency) return;

    semaphore.maxSlots = concurrency;

    final event = ConcurrencyChangeEvent(
      engineType: engineType,
      oldConcurrency: oldConcurrency,
      newConcurrency: concurrency,
      reason: reason,
      timestamp: DateTime.now(),
    );

    _recordChange(event);

    if (enableLogging) {
      dev.log(
        '[$engineType] Concurrency: $oldConcurrency → $concurrency '
        '(reason: ${reason?.name ?? "manual"})',
        name: 'ConcurrencyGovernor',
      );
    }
  }

  void _recordChange(ConcurrencyChangeEvent event) {
    _changeHistory.add(event);
    if (_changeHistory.length > _maxHistorySize) {
      _changeHistory.removeAt(0);
    }
    _changeController.add(event);
  }

  /// Get recent change history.
  List<ConcurrencyChangeEvent> get changeHistory =>
      List.unmodifiable(_changeHistory);

  /// Get a snapshot of all engine states.
  Map<String, EngineStatus> get engineStatuses {
    return engineSemaphores.map((type, sem) => MapEntry(
          type,
          EngineStatus(
            engineType: type,
            maxConcurrency: sem.maxSlots,
            activeCount: sem.activeCount,
            waitingCount: sem.waitingCount,
          ),
        ));
  }

  /// Dispose of resources.
  void dispose() {
    _changeController.close();
  }
}

/// Event emitted when concurrency changes.
class ConcurrencyChangeEvent {
  final String engineType;
  final int oldConcurrency;
  final int newConcurrency;
  final DemandLevel? reason;
  final DateTime timestamp;

  ConcurrencyChangeEvent({
    required this.engineType,
    required this.oldConcurrency,
    required this.newConcurrency,
    this.reason,
    required this.timestamp,
  });

  /// Whether this was an increase.
  bool get isIncrease => newConcurrency > oldConcurrency;

  /// Whether this was an emergency change.
  bool get isEmergency =>
      reason == DemandLevel.emergency || reason == DemandLevel.critical;

  @override
  String toString() =>
      'ConcurrencyChange($engineType: $oldConcurrency→$newConcurrency, '
      'reason: ${reason?.name ?? "manual"})';
}

/// Status of a synthesis engine.
class EngineStatus {
  final String engineType;
  final int maxConcurrency;
  final int activeCount;
  final int waitingCount;

  EngineStatus({
    required this.engineType,
    required this.maxConcurrency,
    required this.activeCount,
    required this.waitingCount,
  });

  /// Available slots.
  int get available => maxConcurrency - activeCount;

  /// Utilization percentage (0-100).
  double get utilization =>
      maxConcurrency > 0 ? (activeCount / maxConcurrency) * 100 : 0;

  /// Whether under pressure (high utilization + waiters).
  bool get isUnderPressure => waitingCount > 0 && utilization > 80;

  Map<String, dynamic> toJson() => {
        'engineType': engineType,
        'maxConcurrency': maxConcurrency,
        'activeCount': activeCount,
        'waitingCount': waitingCount,
        'available': available,
        'utilization': utilization.toStringAsFixed(1),
        'underPressure': isUnderPressure,
      };
}
