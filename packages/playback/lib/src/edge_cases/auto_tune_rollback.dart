import 'dart:developer' as developer;
import 'config_snapshot.dart';

/// Manages configuration snapshots and rollback for auto-tuning.
///
/// When auto-tuning changes configuration (e.g., during calibration), this
/// class maintains snapshots that allow reverting to previous known-good
/// settings if performance degrades.
///
/// Rollback triggers:
/// - Buffer underrun rate increases by >50% compared to baseline
/// - Synthesis failure rate exceeds 10%
/// - Explicit user request
class AutoTuneRollback {
  AutoTuneRollback({
    int maxSnapshots = 5,
    double underrunThreshold = 1.5,
    double failureRateThreshold = 0.10,
  }) : _maxSnapshots = maxSnapshots,
       _underrunThreshold = underrunThreshold,
       _failureRateThreshold = failureRateThreshold;

  final int _maxSnapshots;
  final double _underrunThreshold;
  final double _failureRateThreshold;
  
  final List<ConfigSnapshot> _snapshots = [];
  PerformanceMetrics? _baselineMetrics;
  bool _isCalibrating = false;

  /// All stored snapshots (oldest first).
  List<ConfigSnapshot> get snapshots => List.unmodifiable(_snapshots);
  
  /// Most recent snapshot, if any.
  ConfigSnapshot? get latestSnapshot => _snapshots.isNotEmpty ? _snapshots.last : null;
  
  /// Whether calibration is in progress.
  bool get isCalibrating => _isCalibrating;

  /// Save a configuration snapshot before making changes.
  ///
  /// Call this before auto-tuning or manual configuration changes.
  void saveSnapshot(ConfigSnapshot snapshot) {
    _snapshots.add(snapshot);
    
    // Keep only the most recent snapshots
    while (_snapshots.length > _maxSnapshots) {
      _snapshots.removeAt(0);
    }
    
    developer.log(
      '[AutoTuneRollback] Saved snapshot: ${snapshot.reason}',
      name: 'AutoTuneRollback',
    );
  }

  /// Set baseline metrics before starting calibration.
  ///
  /// These metrics are used to detect performance degradation.
  void setBaseline(PerformanceMetrics metrics) {
    _baselineMetrics = metrics;
    developer.log(
      '[AutoTuneRollback] Baseline set: $metrics',
      name: 'AutoTuneRollback',
    );
  }

  /// Mark calibration as starting.
  void startCalibration() {
    _isCalibrating = true;
    developer.log(
      '[AutoTuneRollback] Calibration started',
      name: 'AutoTuneRollback',
    );
  }

  /// Mark calibration as complete.
  void endCalibration() {
    _isCalibrating = false;
    developer.log(
      '[AutoTuneRollback] Calibration ended',
      name: 'AutoTuneRollback',
    );
  }

  /// Check if rollback is needed based on current performance vs baseline.
  ///
  /// Returns the snapshot to rollback to, or null if no rollback needed.
  RollbackDecision checkForRollback(PerformanceMetrics currentMetrics) {
    if (_snapshots.isEmpty) {
      return RollbackDecision.noRollbackNeeded();
    }

    // Check for high failure rate (absolute threshold)
    if (currentMetrics.synthesisFailureRate > _failureRateThreshold) {
      developer.log(
        '[AutoTuneRollback] High failure rate detected: '
        '${(currentMetrics.synthesisFailureRate * 100).toStringAsFixed(1)}% > '
        '${(_failureRateThreshold * 100).toStringAsFixed(0)}%',
        name: 'AutoTuneRollback',
      );
      return RollbackDecision.rollbackRequired(
        snapshot: _snapshots.last,
        reason: 'High synthesis failure rate',
      );
    }

    // Check for degraded buffer performance (relative to baseline)
    if (_baselineMetrics != null) {
      final baselineRate = _baselineMetrics!.bufferUnderrunRate;
      final currentRate = currentMetrics.bufferUnderrunRate;
      
      // Only compare if baseline had meaningful data
      if (baselineRate > 0 && currentRate > baselineRate * _underrunThreshold) {
        developer.log(
          '[AutoTuneRollback] Underrun rate increased: '
          '${currentRate.toStringAsFixed(1)}/hr > '
          '${(baselineRate * _underrunThreshold).toStringAsFixed(1)}/hr baseline',
          name: 'AutoTuneRollback',
        );
        return RollbackDecision.rollbackRequired(
          snapshot: _snapshots.last,
          reason: 'Buffer underrun rate increased',
        );
      }
    }

    return RollbackDecision.noRollbackNeeded();
  }

  /// Force a rollback to the most recent snapshot.
  ///
  /// Returns the snapshot to restore, or null if no snapshots available.
  ConfigSnapshot? forceRollback({String? reason}) {
    if (_snapshots.isEmpty) {
      developer.log(
        '[AutoTuneRollback] Force rollback requested but no snapshots available',
        name: 'AutoTuneRollback',
      );
      return null;
    }

    final snapshot = _snapshots.removeLast();
    developer.log(
      '[AutoTuneRollback] Force rollback: ${reason ?? "user requested"} -> $snapshot',
      name: 'AutoTuneRollback',
    );
    return snapshot;
  }

  /// Clear all snapshots (e.g., after confirming good performance).
  void clearSnapshots() {
    _snapshots.clear();
    _baselineMetrics = null;
    developer.log(
      '[AutoTuneRollback] Snapshots cleared',
      name: 'AutoTuneRollback',
    );
  }

  /// Export snapshots for persistence.
  List<Map<String, dynamic>> toJson() => 
      _snapshots.map((s) => s.toJson()).toList();

  /// Import snapshots from persistence.
  void fromJson(List<dynamic> json) {
    _snapshots.clear();
    for (final item in json) {
      if (item is Map<String, dynamic>) {
        _snapshots.add(ConfigSnapshot.fromJson(item));
      }
    }
    developer.log(
      '[AutoTuneRollback] Loaded ${_snapshots.length} snapshots',
      name: 'AutoTuneRollback',
    );
  }
}

/// Result of a rollback check.
class RollbackDecision {
  RollbackDecision._({
    required this.needsRollback,
    this.snapshot,
    this.reason,
  });

  factory RollbackDecision.noRollbackNeeded() => RollbackDecision._(
    needsRollback: false,
  );

  factory RollbackDecision.rollbackRequired({
    required ConfigSnapshot snapshot,
    required String reason,
  }) => RollbackDecision._(
    needsRollback: true,
    snapshot: snapshot,
    reason: reason,
  );

  /// Whether a rollback is needed.
  final bool needsRollback;
  
  /// The snapshot to rollback to (if needsRollback is true).
  final ConfigSnapshot? snapshot;
  
  /// Reason for rollback (if needsRollback is true).
  final String? reason;

  @override
  String toString() => needsRollback 
      ? 'RollbackDecision(rollback: $reason -> $snapshot)'
      : 'RollbackDecision(no rollback needed)';
}
