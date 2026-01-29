import 'package:logging/logging.dart';

/// Tracks performance metrics for SSOT operations.
///
/// This service monitors database query latency and cache operations
/// to detect performance degradation or bottlenecks.
class SsotMetrics {
  SsotMetrics._();

  static final _logger = Logger('SsotMetrics');

  /// Query operation metrics
  static final _queryMetrics = <String, _OperationMetrics>{};

  /// Cache operation metrics
  static final _cacheMetrics = <String, _OperationMetrics>{};

  /// Record a database query operation
  ///
  /// Usage:
  /// ```dart
  /// final stopwatch = Stopwatch()..start();
  /// final result = await dao.query(...);
  /// SsotMetrics.recordQuery('getAllBooks', stopwatch.elapsedMilliseconds);
  /// ```
  static void recordQuery(String operationName, int elapsedMs) {
    final metrics = _queryMetrics.putIfAbsent(
      operationName,
      () => _OperationMetrics(operationName, isQuery: true),
    );
    metrics.record(elapsedMs);

    if (elapsedMs > 100) {
      _logger.warning(
        'Slow query detected: $operationName took ${elapsedMs}ms',
      );
    }
  }

  /// Record a cache operation
  ///
  /// Usage:
  /// ```dart
  /// final stopwatch = Stopwatch()..start();
  /// manager.registerEntry(entry);
  /// SsotMetrics.recordCacheOp('registerEntry', stopwatch.elapsedMilliseconds);
  /// ```
  static void recordCacheOperation(String operationName, int elapsedMs) {
    final metrics = _cacheMetrics.putIfAbsent(
      operationName,
      () => _OperationMetrics(operationName, isQuery: false),
    );
    metrics.record(elapsedMs);

    if (elapsedMs > 50) {
      _logger.warning(
        'Slow cache operation: $operationName took ${elapsedMs}ms',
      );
    }
  }

  /// Get query metrics summary
  static Map<String, String> getQueryMetrics() {
    return {
      for (final entry in _queryMetrics.entries)
        entry.key: entry.value.summary(),
    };
  }

  /// Get cache operation metrics summary
  static Map<String, String> getCacheMetrics() {
    return {
      for (final entry in _cacheMetrics.entries)
        entry.key: entry.value.summary(),
    };
  }

  /// Log all metrics to logger
  static void logMetricsSummary() {
    _logger.info('=== SSOT Query Metrics ===');
    for (final summary in getQueryMetrics().entries) {
      _logger.info('${summary.key}: ${summary.value}');
    }

    _logger.info('=== SSOT Cache Metrics ===');
    for (final summary in getCacheMetrics().entries) {
      _logger.info('${summary.key}: ${summary.value}');
    }
  }

  /// Reset all metrics (useful for testing)
  static void reset() {
    _queryMetrics.clear();
    _cacheMetrics.clear();
  }
}

/// Individual operation metrics tracker
class _OperationMetrics {
  _OperationMetrics(this.name, {required this.isQuery});

  final String name;
  final bool isQuery;
  final List<int> durations = [];
  int count = 0;

  void record(int durationMs) {
    durations.add(durationMs);
    count++;
  }

  String summary() {
    if (durations.isEmpty) return 'No data';

    final avg = durations.reduce((a, b) => a + b) ~/ durations.length;
    final min = durations.reduce((a, b) => a < b ? a : b);
    final max = durations.reduce((a, b) => a > b ? a : b);

    return 'count=$count, avg=${avg}ms, min=${min}ms, max=${max}ms';
  }
}
