import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

/// Memory pressure levels from the platform.
///
/// These correspond to Android's ComponentCallbacks2 trim levels.
enum MemoryPressure {
  /// No memory pressure.
  none,

  /// Moderate pressure - reduce memory usage if possible.
  moderate,

  /// Critical pressure - free as much memory as possible.
  critical,
}

/// Storage information from the platform.
class StorageInfo {
  const StorageInfo({
    required this.availableBytes,
    required this.totalBytes,
  });

  /// Available storage in bytes.
  final int availableBytes;

  /// Total storage capacity in bytes.
  final int totalBytes;

  /// Used storage in bytes.
  int get usedBytes => totalBytes - availableBytes;

  /// Usage percentage (0-100).
  double get usagePercent =>
      totalBytes > 0 ? (usedBytes / totalBytes) * 100 : 0;

  /// Available storage in megabytes.
  int get availableMB => availableBytes ~/ (1024 * 1024);

  /// Available storage in gigabytes.
  double get availableGB => availableBytes / (1024 * 1024 * 1024);

  /// Is storage critically low (< 500 MB available)?
  bool get isCriticallyLow => availableBytes < 500 * 1024 * 1024;

  /// Is storage low (< 1 GB available)?
  bool get isLow => availableBytes < 1024 * 1024 * 1024;

  @override
  String toString() =>
      'StorageInfo(available: ${availableGB.toStringAsFixed(1)} GB, '
      'total: ${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB)';
}

/// Platform channel handler for system events.
///
/// Provides access to:
/// - Memory pressure events from the OS
/// - Storage information for cache auto-configuration
///
/// This is a singleton to ensure only one channel listener is registered.
class SystemChannel {
  SystemChannel._();

  static final instance = SystemChannel._();

  static const _channelName = 'io.eist.app/system';
  final _channel = const MethodChannel(_channelName);

  final _memoryPressureController =
      StreamController<MemoryPressure>.broadcast();

  bool _initialized = false;

  /// Stream of memory pressure events from the platform.
  Stream<MemoryPressure> get memoryPressure => _memoryPressureController.stream;

  /// Initialize the platform channel.
  ///
  /// Safe to call multiple times - will only initialize once.
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);

    developer.log(
      'SystemChannel: Initialized',
      name: 'SystemChannel',
    );
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'memoryPressure':
        final levelStr = call.arguments as String;
        final level = _parseMemoryPressure(levelStr);

        developer.log(
          'SystemChannel: Memory pressure: $level',
          name: 'SystemChannel',
        );

        _memoryPressureController.add(level);
        break;

      default:
        developer.log(
          'SystemChannel: Unknown method: ${call.method}',
          name: 'SystemChannel',
        );
    }
  }

  MemoryPressure _parseMemoryPressure(String level) {
    return switch (level) {
      'critical' => MemoryPressure.critical,
      'moderate' => MemoryPressure.moderate,
      _ => MemoryPressure.none,
    };
  }

  /// Get storage information from the platform.
  ///
  /// Returns storage info, or a fallback with 0 values on error.
  Future<StorageInfo> getStorageInfo() async {
    if (!Platform.isAndroid) {
      // iOS would need a different implementation
      return const StorageInfo(availableBytes: 0, totalBytes: 0);
    }

    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>('getStorageInfo');

      if (result == null) {
        return const StorageInfo(availableBytes: 0, totalBytes: 0);
      }

      return StorageInfo(
        availableBytes: (result['availableBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (result['totalBytes'] as num?)?.toInt() ?? 0,
      );
    } catch (e, stackTrace) {
      developer.log(
        'SystemChannel: Error getting storage info: $e',
        name: 'SystemChannel',
        error: e,
        stackTrace: stackTrace,
      );
      return const StorageInfo(availableBytes: 0, totalBytes: 0);
    }
  }

  /// Dispose resources.
  void dispose() {
    _memoryPressureController.close();
  }
}
