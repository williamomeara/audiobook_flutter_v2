import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// Memory information snapshot.
class MemoryInfo {
  const MemoryInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    this.lowMemory = false,
  });

  /// Total memory on device.
  final int totalBytes;

  /// Free memory available.
  final int freeBytes;

  /// Memory used by the app.
  final int usedBytes;

  /// Whether the system reports low memory.
  final bool lowMemory;

  /// Memory usage as a percentage (0.0 to 1.0).
  double get usageRatio => totalBytes > 0 ? usedBytes / totalBytes : 0.0;

  @override
  String toString() =>
      'MemoryInfo(total: ${_formatBytes(totalBytes)}, free: ${_formatBytes(freeBytes)}, used: ${_formatBytes(usedBytes)}, lowMemory: $lowMemory)';

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Monitors memory availability for safe parallel synthesis.
abstract class MemoryMonitor {
  /// Check if there's at least [bytes] of memory available.
  Future<bool> hasSufficientMemory(int bytes);

  /// Get current memory info.
  Future<MemoryInfo> getMemoryInfo();

  /// Whether the system is reporting low memory pressure.
  Future<bool> get isLowMemory;
}

/// Default implementation using platform channel to query Android memory.
class PlatformMemoryMonitor implements MemoryMonitor {
  static const _channel = MethodChannel('com.example.audiobook/memory');

  /// Memory threshold below which synthesis should wait (200 MB).
  static const int defaultThresholdBytes = 200 * 1024 * 1024;

  /// Fallback memory info when platform call fails.
  static const _fallbackMemoryInfo = MemoryInfo(
    totalBytes: 4 * 1024 * 1024 * 1024, // Assume 4GB device
    freeBytes: 500 * 1024 * 1024, // Assume 500MB free
    usedBytes: 200 * 1024 * 1024, // Assume 200MB app usage
    lowMemory: false,
  );

  @override
  Future<bool> hasSufficientMemory(int bytes) async {
    try {
      final info = await getMemoryInfo();
      // Check both free memory and low memory flag
      return info.freeBytes >= bytes && !info.lowMemory;
    } catch (e) {
      developer.log('MemoryMonitor: Failed to check memory: $e');
      // Assume sufficient on failure - synthesis will fail on its own if OOM
      return true;
    }
  }

  @override
  Future<MemoryInfo> getMemoryInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getMemoryInfo');
      if (result == null) return _fallbackMemoryInfo;

      return MemoryInfo(
        totalBytes: result['totalBytes'] as int? ?? 0,
        freeBytes: result['freeBytes'] as int? ?? 0,
        usedBytes: result['usedBytes'] as int? ?? 0,
        lowMemory: result['lowMemory'] as bool? ?? false,
      );
    } on MissingPluginException {
      developer.log('MemoryMonitor: Platform channel not available, using fallback');
      return _fallbackMemoryInfo;
    } catch (e) {
      developer.log('MemoryMonitor: Error getting memory info: $e');
      return _fallbackMemoryInfo;
    }
  }

  @override
  Future<bool> get isLowMemory async {
    final info = await getMemoryInfo();
    return info.lowMemory;
  }
}

/// Mock memory monitor for testing.
class MockMemoryMonitor implements MemoryMonitor {
  MemoryInfo _info;
  bool _sufficient;

  MockMemoryMonitor({
    MemoryInfo? initialInfo,
    bool sufficient = true,
  })  : _info = initialInfo ??
            const MemoryInfo(
              totalBytes: 4 * 1024 * 1024 * 1024,
              freeBytes: 1 * 1024 * 1024 * 1024,
              usedBytes: 200 * 1024 * 1024,
              lowMemory: false,
            ),
        _sufficient = sufficient;

  void setMemoryInfo(MemoryInfo info) => _info = info;
  void setSufficientMemory(bool sufficient) => _sufficient = sufficient;

  @override
  Future<bool> hasSufficientMemory(int bytes) async => _sufficient;

  @override
  Future<MemoryInfo> getMemoryInfo() async => _info;

  @override
  Future<bool> get isLowMemory async => _info.lowMemory;
}
