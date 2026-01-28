import 'package:sqflite/sqflite.dart';

/// Data Access Object for model_metrics table.
///
/// Tracks per-model TTS synthesis performance for adaptive optimization.
class ModelMetricsDao {
  final Database _db;

  ModelMetricsDao(this._db);

  /// Get metrics for a model.
  Future<Map<String, dynamic>?> getMetrics(String modelId) async {
    final results = await _db.query(
      'model_metrics',
      where: 'model_id = ?',
      whereArgs: [modelId],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Record a synthesis operation and update running averages.
  Future<void> recordSynthesis(
      String modelId, String engineId, int durationMs, int charCount) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final charsPerSecond = charCount / (durationMs / 1000.0);

    // Try to get existing metrics
    final existing = await getMetrics(modelId);

    if (existing == null) {
      // Insert new record
      await _db.insert('model_metrics', {
        'model_id': modelId,
        'engine_id': engineId,
        'avg_latency_ms': durationMs,
        'avg_chars_per_second': charsPerSecond,
        'total_syntheses': 1,
        'total_chars_synthesized': charCount,
        'last_used_at': now,
      });
    } else {
      // Update with exponential moving average (alpha = 0.1)
      const alpha = 0.1;
      final oldAvgLatency = existing['avg_latency_ms'] as int? ?? durationMs;
      final oldAvgCps = existing['avg_chars_per_second'] as double? ?? charsPerSecond;
      final totalSyntheses = (existing['total_syntheses'] as int? ?? 0) + 1;
      final totalChars = (existing['total_chars_synthesized'] as int? ?? 0) + charCount;

      final newAvgLatency = (alpha * durationMs + (1 - alpha) * oldAvgLatency).round();
      final newAvgCps = alpha * charsPerSecond + (1 - alpha) * oldAvgCps;

      await _db.update(
        'model_metrics',
        {
          'avg_latency_ms': newAvgLatency,
          'avg_chars_per_second': newAvgCps,
          'total_syntheses': totalSyntheses,
          'total_chars_synthesized': totalChars,
          'last_used_at': now,
        },
        where: 'model_id = ?',
        whereArgs: [modelId],
      );
    }
  }

  /// Get average latency for a model.
  Future<int?> getAverageLatency(String modelId) async {
    final result = await _db.rawQuery('''
      SELECT avg_latency_ms FROM model_metrics
      WHERE model_id = ?
    ''', [modelId]);
    if (result.isEmpty) return null;
    return result.first['avg_latency_ms'] as int?;
  }

  /// Get average chars per second for a model.
  Future<double?> getAverageCharsPerSecond(String modelId) async {
    final result = await _db.rawQuery('''
      SELECT avg_chars_per_second FROM model_metrics
      WHERE model_id = ?
    ''', [modelId]);
    if (result.isEmpty) return null;
    return result.first['avg_chars_per_second'] as double?;
  }

  /// Get all metrics for an engine.
  Future<List<Map<String, dynamic>>> getMetricsForEngine(String engineId) async {
    return await _db.query(
      'model_metrics',
      where: 'engine_id = ?',
      whereArgs: [engineId],
      orderBy: 'last_used_at DESC',
    );
  }

  /// Get total synthesis count across all models.
  Future<int> getTotalSynthesisCount() async {
    final result = await _db.rawQuery(
      'SELECT SUM(total_syntheses) as total FROM model_metrics',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total characters synthesized across all models.
  Future<int> getTotalCharsSynthesized() async {
    final result = await _db.rawQuery(
      'SELECT SUM(total_chars_synthesized) as total FROM model_metrics',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete metrics for a model.
  Future<void> deleteMetrics(String modelId) async {
    await _db.delete(
      'model_metrics',
      where: 'model_id = ?',
      whereArgs: [modelId],
    );
  }

  /// Delete all metrics for an engine.
  Future<void> deleteMetricsForEngine(String engineId) async {
    await _db.delete(
      'model_metrics',
      where: 'engine_id = ?',
      whereArgs: [engineId],
    );
  }
}
